#requires -Version 5.1
#requires -PSEdition Desktop
# Internal worker: it can ONLY write a temporary workbook, never replace a source.
[CmdletBinding(DefaultParameterSetName='Single')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Single')][string]$JobPath,
    [Parameter(Mandatory=$true,ParameterSetName='Session')][string]$SessionPath
)
. (Join-Path $PSScriptRoot 'Common.ps1')
$script:workerApp=$null; $script:workerBooks=$null; $script:workerOwned=$false
$script:workerExcelPid=0; $script:workerExcelStartTicks=0
$script:workerSessionDirectory=''; $script:workerSessionToken=''

function Set-WorkerUnsafeMarker {
    if($script:workerSessionDirectory) {
        try { Write-Json @{schemaVersion=1;sessionToken=$script:workerSessionToken;category='WorkerSessionUnsafe';time=[DateTime]::UtcNow.ToString('o')} (Join-Path $script:workerSessionDirectory 'unsafe.json') } catch { }
    }
}
function Show-WorkerApplication {
    try { $script:workerApp.DisplayAlerts=$true } catch { }
    try { $script:workerApp.Visible=$true } catch { }
}
function Get-WorkerWorkbookCounts {
    $protectedViews=$null
    try {
        $protectedViews=$script:workerApp.ProtectedViewWindows
        [pscustomobject]@{workbooks=[int]$script:workerBooks.Count;protectedViews=[int]$protectedViews.Count}
    } finally { Release-Com $protectedViews }
}

function Test-WorkerProcess([int]$ProcessId,[long]$StartTicks) {
    $process=$null
    try {
        $process=Get-Process -Id $ProcessId -ErrorAction Stop
        return (-not $process.HasExited -and $process.StartTime.ToUniversalTime().Ticks -eq $StartTicks)
    } catch { return $false } finally { if($null -ne $process) { $process.Dispose() } }
}
function Assert-WorkerIdle {
    try {
        if($null -eq $script:workerApp) {
            if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'ExcelOwnershipOrExistingProcess' }
            return
        }
        if(-not $script:workerOwned -or -not (Test-WorkerProcess $script:workerExcelPid $script:workerExcelStartTicks)) { throw 'WorkerSessionUnsafe' }
        $counts=Get-WorkerWorkbookCounts
        if($counts.workbooks -ne 0 -or $counts.protectedViews -ne 0) { throw 'UnexpectedWorkbook' }
        if(@(Get-Process EXCEL -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $script:workerExcelPid }).Count) { throw 'ExcelOwnershipOrExistingProcess' }
    } catch { Set-WorkerUnsafeMarker; throw }
}
function Start-WorkerExcel {
    Assert-WorkerIdle
    if($null -ne $script:workerApp) { return }
    # Compile the signature helper and HWND ownership P/Invoke together once.
    [void](Get-FormulaSignature $null)
    Assert-WorkerIdle
    $script:workerApp=New-Object -ComObject Excel.Application
    [uint32]$excelProcessId=0
    [void][EpsWindow]::GetWindowThreadProcessId([IntPtr]$script:workerApp.Hwnd,[ref]$excelProcessId)
    if(-not $excelProcessId) { throw 'ExcelOwnershipOrExistingProcess' }
    $process=Get-Process -Id $excelProcessId -ErrorAction Stop
    try {
        if($process.ProcessName -ine 'EXCEL') { throw 'ExcelOwnershipOrExistingProcess' }
        $script:workerExcelPid=[int]$excelProcessId
        $script:workerExcelStartTicks=$process.StartTime.ToUniversalTime().Ticks
        $script:workerOwned=$true
    } finally { $process.Dispose() }
    $script:workerBooks=$script:workerApp.Workbooks
    Assert-WorkerIdle
}
function Stop-WorkerExcel {
    $cleanup=[ordered]@{status='Stopped';category='Stopped';excelPid=$script:workerExcelPid;excelStartTicks=$script:workerExcelStartTicks;workbooksClosed=$false;excelExited=$false}
    $quitRequested=$false
    try {
        if($null -eq $script:workerApp) { $cleanup.workbooksClosed=$true; $cleanup.excelExited=$true }
        elseif(-not $script:workerOwned -or -not (Test-WorkerProcess $script:workerExcelPid $script:workerExcelStartTicks)) { throw 'WorkerSessionUnsafe' }
        else {
            $counts=Get-WorkerWorkbookCounts
            if($counts.workbooks -ne 0 -or $counts.protectedViews -ne 0) { throw 'UnexpectedWorkbook' }
            # Restore prompts before Quit, then recheck both collections. A user
            # opening a document concurrently must never lose edits silently.
            $script:workerApp.DisplayAlerts=$true
            $counts=Get-WorkerWorkbookCounts
            if($counts.workbooks -ne 0 -or $counts.protectedViews -ne 0) { throw 'UnexpectedWorkbook' }
            $cleanup.workbooksClosed=$true
            $quitRequested=$true
            $script:workerApp.Quit()
        }
    } catch {
        Set-WorkerUnsafeMarker
        if(-not $quitRequested -and $null -ne $script:workerApp) { Show-WorkerApplication }
        $cleanup.status='Failed'; $cleanup.category='WorkerSessionUnsafe'
    }
    finally {
        try { Release-Com $script:workerBooks } catch { Set-WorkerUnsafeMarker; $cleanup.status='Failed'; $cleanup.category='ComCleanupFailed' }
        try { Release-Com $script:workerApp } catch { Set-WorkerUnsafeMarker; $cleanup.status='Failed'; $cleanup.category='ComCleanupFailed' }
        $script:workerBooks=$null; $script:workerApp=$null
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
    if($script:workerExcelPid) {
        if($quitRequested) {
            for($wait=0;$wait -lt 20 -and (Test-WorkerProcess $script:workerExcelPid $script:workerExcelStartTicks);$wait++) { Start-Sleep -Milliseconds 250 }
        }
        $cleanup.excelExited=-not (Test-WorkerProcess $script:workerExcelPid $script:workerExcelStartTicks)
        if(-not $cleanup.excelExited) { Set-WorkerUnsafeMarker; $cleanup.status='Failed'; if($cleanup.category -eq 'Stopped') { $cleanup.category='ExcelStillRunning' } }
    }
    return $cleanup
}
function Invoke-WorkbookJob($Job) {
    $book=$null; $stage='ComStart'; $old=''; $new=''; $outPassword=''
    $sentinel=[guid]::NewGuid().ToString('N').Substring(0,15)
    $result=[ordered]@{status='Failed';category='WorkerFailed';stage=$stage;hresults='';message='';excelPid=$script:workerExcelPid;excelStartTicks=$script:workerExcelStartTicks;encryptedBefore=$null;sessionReady=$false;workbooksClosed=$false}
    try {
        Start-WorkerExcel
        $script:workerApp.Visible=$false; $script:workerApp.DisplayAlerts=$false; $script:workerApp.EnableEvents=$false
        $script:workerApp.AskToUpdateLinks=$false; $script:workerApp.AutomationSecurity=3
    $old=[string](Unprotect-Text $Job.oldSecret); $new=[string](Unprotect-Text $Job.newSecret)
    if($Job.mode -notin @('Encrypt','Decrypt','ChangePassword')) { throw 'InvalidMode' }
    if($Job.mode -in @('Decrypt','ChangePassword') -and -not $old) { throw 'CurrentPasswordRequired' }
    if($Job.mode -in @('Encrypt','ChangePassword') -and ($new.Length -lt 1 -or $new.Length -gt 15)) { throw 'NewPasswordLength' }
    if($Job.mode -eq 'ChangePassword' -and $old -ceq $new) { throw 'PasswordUnchanged' }
    if(-not $old) { $old=$sentinel }
    $missing=[Type]::Missing
    $stage='Open'
    # Explicit password and write-password avoid missing-argument password prompts.
    $book=$script:workerBooks.Open([string]$Job.input,0,$true,$missing,$old,$sentinel,$true,$missing,$missing,$false,$false,$missing,$false,$false)
    if($null -eq $book) { throw 'WorkbookOpenReturnedNull' }
    $hasPassword=[bool]$book.HasPassword; $result.encryptedBefore=$hasPassword
    $signatureSet=$null
    try { $signatureSet=$book.Signatures; $signed=$signatureSet.Count -gt 0 } finally { Release-Com $signatureSet }
    if($signed -or $book.VBASigned) { $result.category='SignedWorkbookUnsupported'; $result.status='Skipped' }
    elseif($book.MultiUserEditing) { $result.category='SharedWorkbookUnsupported'; $result.status='Skipped' }
    elseif($book.WriteReserved) { $result.category='WriteReservedUnsupported'; $result.status='Skipped' }
    elseif($Job.mode -eq 'Encrypt' -and $hasPassword) { $result.category='AlreadyEncrypted'; $result.status='Skipped' }
    elseif($Job.mode -in @('Decrypt','ChangePassword') -and -not $hasPassword) { $result.category='AlreadyUnencrypted'; $result.status='Skipped' }
    else {
        $format=[int]$book.FileFormat
        if($format -notin @(Get-AllowedFormats ([IO.Path]::GetExtension($Job.backup)))) { throw 'ExtensionAndFileFormatMismatchOrLegacyFormat' }
        $stage='Verify'; $before=Get-WorkbookSignature $book
        $stage='SaveAs'; $outPassword=if($Job.mode -in @('Encrypt','ChangePassword')){$new}else{''}
        # Positional COM arguments: FileName, FileFormat, Password, WriteResPassword...
        $book.SaveAs([string]$Job.temp,$format,$outPassword,'',$false,$false,1,2,$false,$missing,$missing,$false)
        $book.Close($false); Release-Com $book; $book=$null
        $stage='Verify'
        if(-not (Test-Path -LiteralPath $Job.temp) -or (Get-Item -LiteralPath $Job.temp).Length -eq 0) { throw 'EmptyTemporaryFile' }
        # Pin the bytes BEFORE validation so a later modification cannot be
        # accidentally blessed as the workbook that Excel actually reopened.
        $validationHash=Get-Sha $Job.temp
        $verifyPassword=if($outPassword){$outPassword}else{$sentinel}
        $book=$script:workerBooks.Open([string]$Job.temp,0,$true,$missing,$verifyPassword,$sentinel,$true,$missing,$missing,$false,$false,$missing,$false,$false)
        if($null -eq $book) { throw 'VerificationOpenReturnedNull' }
        if([bool]$book.HasPassword -ne ($Job.mode -in @('Encrypt','ChangePassword'))) { throw 'PasswordStateMismatch' }
        if((Get-WorkbookSignature $book) -cne $before) { throw 'WorkbookSignatureMismatch' }
        $book.Close($false); Release-Com $book; $book=$null
        if($Job.mode -in @('Encrypt','ChangePassword')) {
            # Negative test: a deliberately different password MUST fail to open.
            $wrong=if($new -ceq $sentinel){'Wrong-'+$sentinel.Substring(0,8)}else{$sentinel}
            $negativePasswords=@($wrong)
            if($Job.mode -eq 'ChangePassword') { $negativePasswords+=@($old) }
            foreach($negativePassword in $negativePasswords) {
                $unexpected=$null; $rejected=$false
                try { $unexpected=$script:workerBooks.Open([string]$Job.temp,0,$true,$missing,$negativePassword,$sentinel,$true,$missing,$missing,$false,$false,$missing,$false,$false) }
                catch {
                    # Only Excel's normal 1004 qualifies; RPC/library failures are not proof.
                    if((Get-HResults $_) -notmatch '0x800A03EC') { throw }
                    $rejected=$true
                }
                finally { if($null -ne $unexpected) { try { $unexpected.Close($false) } finally { Release-Com $unexpected; $unexpected=$null } } }
                if(-not $rejected) { throw 'WrongPasswordWasNotRejected' }
            }
        }
        if((Get-Sha $Job.temp) -ne $validationHash) { throw 'TemporaryFileChangedDuringValidation' }
        $result.status='Validated'; $result.category='Validated'; $result.tempHash=$validationHash
    }
    } catch {
        $result.category=Get-Category $_ $stage; $result.hresults=Get-HResults $_
        $message=$_.Exception.Message
        if($message -match 'ExtensionAndFileFormatMismatchOrLegacyFormat') { $result.category='UnsupportedOrMismatchedFormat' }
        elseif($message -match 'Excel4MacroSheetNotSupported') { $result.category='Excel4MacroSheetUnsupported' }
        elseif($message -match 'ExcelOwnershipOrExistingProcess|ExcelOwnershipNotProven|ExistingExcel') { $result.category='ExcelOwnershipOrExistingProcess' }
        elseif($message -match 'UnexpectedWorkbook|WorkerSessionUnsafe') { $result.category='WorkerSessionUnsafe' }
        $result.message=$result.category
    } finally {
        $result.stage=$stage; $result.excelPid=$script:workerExcelPid; $result.excelStartTicks=$script:workerExcelStartTicks
        try { if($null -ne $book) { $book.Close($false) } } catch { $result.status='Failed'; $result.category='ComCleanupFailed' }
        try { Release-Com $book } catch { $result.status='Failed'; $result.category='ComCleanupFailed' }
        $book=$null; $old=''; $new=''; $outPassword=''; $negativePassword=''; $negativePasswords=$null; $verifyPassword=''
        try {
            Assert-WorkerIdle
            $result.workbooksClosed=$true
            $result.sessionReady=($null -ne $script:workerApp -and $result.category -notin @('ComCleanupFailed','ComServerError','WorkerSessionUnsafe'))
        } catch { $result.status='Failed'; $result.category='WorkerSessionUnsafe'; $result.message=$result.category }
        if(-not $result.sessionReady) { Set-WorkerUnsafeMarker }
    }
    return $result
}

if($PSCmdlet.ParameterSetName -eq 'Single') {
    $job=Get-Content -LiteralPath $JobPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $result=$null
    try { $result=Invoke-WorkbookJob $job }
    finally {
        $cleanup=Stop-WorkerExcel
        if($null -ne $result) {
            if($cleanup.status -ne 'Stopped') { $result.status='Failed'; $result.category=$cleanup.category }
            $result.sessionReady=$false; $result.workbooksClosed=$cleanup.workbooksClosed
            Write-Json $result ([string]$job.result)
        }
        $job.oldSecret=''; $job.newSecret=''
    }
    return
}

$SessionPath=[IO.Path]::GetFullPath($SessionPath)
Assert-NoReparse $SessionPath
$sessionDir=[IO.Path]::GetDirectoryName($SessionPath)
$batchDir=[IO.Path]::GetDirectoryName($sessionDir)
if([IO.Path]::GetFileName($SessionPath) -cne 'session.json' -or (Get-Item -LiteralPath $SessionPath).Length -gt 65536) { throw 'InvalidWorkerSession' }
$config=Get-Content -LiteralPath $SessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
if($config.schemaVersion -ne 1 -or [string]$config.token -notmatch '^[0-9a-fA-F]{32}$' -or [int]$config.ownerPid -le 0 -or [long]$config.ownerStartTicks -le 0) { throw 'InvalidWorkerSession' }
$sessionToken=[string]$config.token
$script:workerSessionDirectory=$sessionDir; $script:workerSessionToken=$sessionToken
$nextPath=Join-Path $sessionDir 'next-job.json'; $stopPath=Join-Path $sessionDir 'stop'
$sequence=0; $sessionCategory='Stopped'; $sessionFailed=$false
try {
    foreach($reserved in @('ready.json','finished.json','unsafe.json')) { if(Test-Path -LiteralPath (Join-Path $sessionDir $reserved)) { throw 'WorkerSessionAlreadyUsed' } }
    Write-Json @{sessionToken=$sessionToken;sessionReady=$true;excelPid=0;excelStartTicks=0;workbooksClosed=$true} (Join-Path $sessionDir 'ready.json')
    while($true) {
        if(-not (Test-WorkerProcess ([int]$config.ownerPid) ([long]$config.ownerStartTicks))) { $sessionCategory='OwnerExited'; break }
        if([IO.File]::Exists($stopPath)) { break }
        Assert-WorkerIdle
        if(-not [IO.File]::Exists($nextPath)) { Start-Sleep -Milliseconds 100; continue }
        Assert-NoReparse $nextPath
        if((Get-Item -LiteralPath $nextPath).Length -gt 65536) { throw 'InvalidWorkerSessionJob' }
        $next=Get-Content -LiteralPath $nextPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if([string]$next.token -cne $sessionToken -or [long]$next.sequence -ne ($sequence+1)) { throw 'InvalidWorkerSessionSequence' }
        $jobFile=[IO.Path]::GetFullPath([string]$next.jobPath)
        $childDir=[IO.Path]::GetDirectoryName($jobFile)
        if([IO.Path]::GetFileName($jobFile) -cne 'worker-job.json' -or [IO.Path]::GetDirectoryName($childDir) -ine $batchDir -or [IO.Path]::GetFileName($childDir) -notmatch '^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})$') { throw 'InvalidWorkerSessionJob' }
        Assert-NoReparse $jobFile
        if((Get-Item -LiteralPath $jobFile).Length -gt 65536) { throw 'InvalidWorkerSessionJob' }
        $job=Get-Content -LiteralPath $jobFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if([IO.Path]::GetFullPath([string]$job.result) -ine (Join-Path $childDir 'worker-result.json') -or [IO.File]::Exists([string]$job.result)) { throw 'InvalidWorkerSessionResult' }
        [IO.File]::Delete($nextPath)
        $sequence=[long]$next.sequence
        try {
            $result=Invoke-WorkbookJob $job
            $result.sessionToken=$sessionToken; $result.sequence=$sequence
            Write-Json $result ([string]$job.result)
        } finally { $job.oldSecret=''; $job.newSecret=''; $job=$null }
        if(-not $result.sessionReady) { $sessionFailed=$true; $sessionCategory='WorkerSessionUnsafe'; break }
    }
} catch { Set-WorkerUnsafeMarker; $sessionFailed=$true; $sessionCategory='WorkerSessionUnsafe' }
finally {
    $cleanup=Stop-WorkerExcel
    if($cleanup.status -ne 'Stopped') { $sessionFailed=$true; $sessionCategory=$cleanup.category }
    $cleanup.status=if($sessionFailed){'Failed'}else{'Stopped'}
    $cleanup.category=$sessionCategory; $cleanup.sessionToken=$sessionToken; $cleanup.sequence=$sequence
    Write-Json $cleanup (Join-Path $sessionDir 'finished.json')
}
