#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RequestPath,
    [ValidateRange(30,3600)][int]$TimeoutSeconds=180,
    [string]$CancellationPath='',
    [hashtable]$WorkerSession=$null
)
. (Join-Path $PSScriptRoot 'Common.ps1')

# Restrict ACL changes to a dedicated new GUID-named run directory.
$RequestPath=[IO.Path]::GetFullPath($RequestPath)
$runDir=[IO.Path]::GetDirectoryName($RequestPath)
if([IO.Path]::GetFileName($RequestPath) -cne 'request.json' -or [IO.Path]::GetFileName($runDir) -notmatch '^(?:[0-9a-fA-F]{32}|[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12})$') { throw 'DedicatedRunDirectoryRequired' }
Assert-NoReparse $RequestPath
Set-PrivateDirectory $runDir
$resultPath=Join-Path $runDir 'result.json'
$progressPath=Join-Path $runDir 'progress.json'
$statePath=Join-Path $runDir 'state.json'
$jobPath=Join-Path $runDir 'worker-job.json'
$workerResultPath=Join-Path $runDir 'worker-result.json'
foreach($reserved in @($resultPath,$progressPath,$statePath,$jobPath,$workerResultPath)) {
    if(Test-Path -LiteralPath $reserved) { throw 'RunAlreadyUsed' }
}
$record=[ordered]@{schemaVersion=1;status='Failed';category='';message='';path='';mode='';backup='';recovery='';recoveryRemoved=$false;sourceHash='';resultHash='';stage='Preflight';hresults='';time='';temp='';inputCopy='';backend='Excel'}
$mutex=$null; $locked=$false; $hold=$null; $worker=$null; $inputCopy=''; $temp=''; $preserveTemp=$false; $request=$null
$sessionBusy=$false
function Assert-SessionOwner {
    if($null -ne $WorkerSession -and $WorkerSession.userOwnerPid -gt 0 -and -not (Test-ProcessIdentity $WorkerSession.userOwnerPid $WorkerSession.userOwnerStart)) { throw 'OwnerExited' }
}
function Assert-SessionIdle {
    if($null -ne $WorkerSession -and [IO.File]::Exists((Join-Path $WorkerSession.directory 'unsafe.json'))) { throw 'WorkerSessionUnsafe' }
    if($null -eq $WorkerSession -or $null -eq $WorkerSession.process) {
        if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'ExistingExcel' }
        return
    }
    if($WorkerSession.process.HasExited -or -not $WorkerSession.healthy) { throw 'WorkerSessionUnsafe' }
    $excel=@(Get-Process EXCEL -ErrorAction SilentlyContinue)
    if($excel.Count -ne 1 -or $excel[0].Id -ne $WorkerSession.excelPid -or -not (Test-ProcessIdentity $WorkerSession.excelPid $WorkerSession.excelStartTicks)) { throw 'WorkerSessionUnsafe' }
}
function Set-Progress([string]$Stage,[string]$Message) {
    $script:record.stage=$Stage
    Write-Json @{schemaVersion=1;stage=$Stage;message=$Message} $progressPath
}
function Save-State([string]$State) {
    Write-Json @{schemaVersion=1;state=$State;path=$record.path;mode=$record.mode;backup=$record.backup;recovery=$record.recovery;temp=$temp;inputCopy=$inputCopy;sourceHash=$record.sourceHash;resultHash=$record.resultHash;time=[DateTime]::UtcNow.ToString('o')} $statePath
}
try {
    if((Get-Item -LiteralPath $RequestPath).Length -gt 65536) { throw 'InvalidRequest' }
    $request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Request $request
    $record.mode=[string]$request.mode
    $record.path=Assert-LocalWorkbook ([string]$request.path)
    $record.sourceHash=[string]$request.expectedHash
    Assert-NotCancelled $runDir $CancellationPath
    $mutex=New-Object Threading.Mutex($false,(Get-EngineMutexName))
    try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
    if(-not $locked) { throw 'AnotherOperationRunning' }
    Assert-SessionOwner
    Assert-SessionIdle
    $hold=[IO.File]::Open($record.path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
    if((Get-StreamSha $hold) -ne $record.sourceHash) { throw 'SourceChanged' }
    $ext=[IO.Path]::GetExtension($record.path)
    $record.backup=Join-Path $runDir ('original'+$ext)
    if(Test-Path -LiteralPath $record.backup) { throw 'RunAlreadyUsed' }
    Set-Progress 'Backup' '원본을 백업하고 있습니다.'
    Save-State 'Planned'
    Assert-NotCancelled $runDir $CancellationPath
    $out=[IO.File]::Open($record.backup,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $hold.Position=0; $hold.CopyTo($out); $out.Flush($true) } finally { $out.Dispose(); $hold.Position=0 }
    if((Get-Sha $record.backup) -ne $record.sourceHash) { throw 'BackupChanged' }
    Save-State 'BackedUp'
    Assert-NotCancelled $runDir $CancellationPath
    $id=[guid]::NewGuid().ToString('N')
    $parent=[IO.Path]::GetDirectoryName($record.path)
    $inputCopy=Join-Path $parent ('.eps-'+$id+'-source'+$ext)
    $temp=Join-Path $parent ('.eps-'+$id+$ext)
    $record.inputCopy=$inputCopy; $record.temp=$temp
    [IO.File]::Copy($record.backup,$inputCopy,$false)
    if((Get-Sha $inputCopy) -ne $record.sourceHash) { throw 'SnapshotChanged' }
    # The direct codec only writes a new temporary file. Both backends converge
    # on the same approval, backup, cancellation and atomic replacement checks.
    # An unsupported format may use Excel; a password/integrity failure may not.
    $r=$null
    $cryptoAssembly=Join-Path $PSScriptRoot 'ExcelPasswordSafe.Crypto.dll'
    if($ext -in @('.xlsx','.xlsm') -and [IO.File]::Exists($cryptoAssembly)) {
        Set-Progress 'Worker' '암호와 파일 내용을 확인하고 있습니다.'
        Save-State 'WorkerStarted'
        if(-not ('ExcelPasswordSafe.Crypto.DirectCrypto' -as [type])) { Add-Type -Path $cryptoAssembly }
        $old=''; $new=''
        try {
            $old=[string](Unprotect-Text $request.oldSecret); $new=[string](Unprotect-Text $request.newSecret)
            $direct=[ExcelPasswordSafe.Crypto.DirectCrypto]::Operate($inputCopy,$temp,$ext,[string]$request.mode,$old,$new)
        } finally { $old=''; $new='' }
        Assert-SessionOwner
        Assert-NotCancelled $runDir $CancellationPath
        Assert-SessionIdle
        if($direct.Supported) {
            $record.backend='DirectOoxml'
            $r=[pscustomobject]@{status=$direct.Status;category=$direct.Category;message=$direct.Message;hresults='';tempHash=''}
            if($r.status -eq 'Validated') {
                if([string]$direct.TempHash -notmatch '^[0-9a-fA-F]{64}$') { throw 'InvalidDirectValidation' }
                $r.tempHash=[string]$direct.TempHash
            }
            Write-Json $r $workerResultPath
            [IO.File]::Delete($RequestPath)
            $request.oldSecret=''; $request.newSecret=''
        } elseif([IO.File]::Exists($temp)) { throw 'UnexpectedDirectOutput' }
    }
    if($null -eq $r) {
    Write-Json @{mode=$request.mode;input=$inputCopy;backup=$record.backup;temp=$temp;result=$workerResultPath;oldSecret=$request.oldSecret;newSecret=$request.newSecret} $jobPath
    # Do not retain even DPAPI ciphertext longer than the job needs it.
    [IO.File]::Delete($RequestPath)
    $request.oldSecret=''; $request.newSecret=''
    Set-Progress 'Worker' 'Excel에서 저장하고 암호와 내용을 확인하고 있습니다.'
    Save-State 'WorkerStarted'
    $workerScript=Join-Path $PSScriptRoot 'ExcelPassword.Worker.ps1'
    if($null -ne $WorkerSession) {
        if($null -eq $WorkerSession.process) {
            [void][IO.Directory]::CreateDirectory($WorkerSession.directory); Set-PrivateDirectory $WorkerSession.directory
            $sessionPath=Join-Path $WorkerSession.directory 'session.json'
            $controller=[Diagnostics.Process]::GetCurrentProcess()
            try { $controllerStart=$controller.StartTime.ToUniversalTime().Ticks.ToString() } finally { $controller.Dispose() }
            Write-Json @{schemaVersion=1;ownerPid=$PID;ownerStartTicks=$controllerStart;token=$WorkerSession.token} $sessionPath
            $arguments='-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$workerScript+'" -SessionPath "'+$sessionPath+'"'
            $WorkerSession.process=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru -WindowStyle Hidden
        }
        $worker=$WorkerSession.process
        $WorkerSession.sequence++
        $sessionBusy=$true; $WorkerSession.healthy=$false
        Write-Json @{token=$WorkerSession.token;sequence=$WorkerSession.sequence;jobPath=$jobPath} (Join-Path $WorkerSession.directory 'next-job.json')
    } else {
        $arguments='-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$workerScript+'" -JobPath "'+$jobPath+'"'
        $worker=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru -WindowStyle Hidden
    }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true) {
        if($null -ne $WorkerSession -and [IO.File]::Exists($workerResultPath)) { break }
        if($worker.WaitForExit(100)) { break }
        $ownerGone=$null -ne $WorkerSession -and $WorkerSession.userOwnerPid -gt 0 -and -not (Test-ProcessIdentity $WorkerSession.userOwnerPid $WorkerSession.userOwnerStart)
        if($record.stage -ne 'Cancelling' -and ($ownerGone -or [IO.File]::Exists((Join-Path $runDir 'cancel')) -or ($CancellationPath -and [IO.File]::Exists($CancellationPath)))) { Set-Progress 'Cancelling' '현재 Excel 확인이 끝나면 원본을 바꾸지 않고 취소합니다.' }
        if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            # Terminate only the PowerShell child that this invocation started.
            $preserveTemp=$true
            $worker.Kill(); $worker.WaitForExit()
            throw 'WorkerTimeout'
        }
    }
    [IO.File]::Delete($jobPath)
    if(-not [IO.File]::Exists($workerResultPath)) { $preserveTemp=$true; throw 'WorkerCrashed' }
    if($null -ne $WorkerSession) { $preserveTemp=$true }
    $r=Get-Content -LiteralPath $workerResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if($null -ne $WorkerSession) {
        foreach($field in @('sessionToken','sequence','sessionReady','workbooksClosed','excelPid','excelStartTicks')) {
            if($null -eq $r.PSObject.Properties[$field]) { throw 'WorkerSessionUnsafe' }
        }
        if($r.sessionToken -cne $WorkerSession.token -or $r.sequence -ne $WorkerSession.sequence -or $r.sessionReady -isnot [bool] -or $r.sessionReady -ne $true -or $r.workbooksClosed -isnot [bool] -or $r.workbooksClosed -ne $true) { throw 'WorkerSessionUnsafe' }
        if($WorkerSession.excelPid -gt 0 -and ($r.excelPid -ne $WorkerSession.excelPid -or [string]$r.excelStartTicks -cne $WorkerSession.excelStartTicks)) { throw 'WorkerSessionUnsafe' }
        $WorkerSession.excelPid=[int]$r.excelPid; $WorkerSession.excelStartTicks=[string]$r.excelStartTicks; $WorkerSession.healthy=$true
        Assert-SessionIdle
        $sessionBusy=$false; $preserveTemp=$false
    } else {
        for($wait=0;$wait -lt 20 -and @(Get-Process EXCEL -ErrorAction SilentlyContinue).Count;$wait++) { Start-Sleep -Milliseconds 250 }
        if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { $preserveTemp=$true; throw 'ExcelStillRunning' }
    }
    }
    Assert-SessionOwner
    Assert-NotCancelled $runDir $CancellationPath
    $record.hresults=$r.hresults
    if($r.status -eq 'Skipped') { $record.status='Skipped'; $record.category=$r.category; Save-State 'Skipped' }
    elseif($r.status -ne 'Validated') { $record.category=$r.category; throw 'WorkerFailed' }
    else {
        if((Get-Sha $inputCopy) -ne $record.sourceHash) { throw 'SnapshotChanged' }
        $record.resultHash=$r.tempHash
        Save-State 'Validated'
        Set-Progress 'Commit' '확인한 결과를 원본 위치에 저장하고 있습니다.'
        # Recheck all evidence before recording commit intent; no delete/move fallback.
        Assert-NoReparse $record.path
        if((Get-Sha $temp) -ne $r.tempHash) { throw 'TempChanged' }
        if((Get-Sha $record.path) -ne $record.sourceHash -or (Get-StreamSha $hold) -ne $record.sourceHash) { throw 'SourceChanged' }
        if((Get-Sha $record.backup) -ne $record.sourceHash) { throw 'BackupChanged' }
        Assert-NotCancelled $runDir $CancellationPath
        Assert-SessionOwner
        if($null -ne $WorkerSession) { Assert-SessionIdle }
        $record.recovery=Join-Path $parent ('.eps-'+$id+'.recovery')
        $preserveTemp=$true
        Save-State 'CommitIntent'
        try {
            $record.resultHash=Invoke-GuardedReplace $record.path $temp $record.backup $record.recovery $record.sourceHash $r.tempHash $hold
            Save-State 'Committed'
        } catch { $record.category='CommitUncertain'; throw }
        $record.status='Success'; $record.category='ReplacedAndVerified'; $preserveTemp=$false
    }
} catch {
    $known=@('InvalidRequest','CurrentPasswordRequired','NewPasswordLength','PasswordUnchanged','LocalPathRequired','FileNotFound','LocalNtfsRequired','UnsupportedExtension','TemporaryFileNotSupported','ReadOnlyAttribute','OfflineFileUnsupported','FileInUse','AnotherOperationRunning','ExistingExcel','SourceChanged','RunAlreadyUsed','BackupChanged','SnapshotChanged','WorkerTimeout','WorkerCrashed','ExcelStillRunning','WorkerSessionUnsafe','TempChanged','Cancelled','OwnerExited')
    if(-not $record.category) {
        if($_.Exception.Message -in $known) { $record.category=$_.Exception.Message }
        elseif($_.Exception.Message -like 'ReparsePoint:*') { $record.category='ReparsePoint' }
        else { $record.category=Get-Category $_ $record.stage }
    }
    if($record.category -in @('Cancelled','OwnerExited')) { $record.status='Cancelled' }
    if($record.category -eq 'WorkerSessionUnsafe') { $preserveTemp=$true; if($null -ne $WorkerSession) { $WorkerSession.healthy=$false } }
    if(-not $record.hresults) { $record.hresults=Get-HResults $_ }
    # Stable categories, not COM exception text: passwords cannot enter this log.
    $record.message=$record.category
} finally {
    # Any failure while monitoring the child (for example a full log disk) must
    # not leave a live writer while its temporary files are being removed.
    if($null -ne $worker -and -not $worker.HasExited -and ($null -eq $WorkerSession -or $sessionBusy)) {
        $preserveTemp=$true
        if($null -ne $WorkerSession) { $WorkerSession.healthy=$false }
        if($null -ne $WorkerSession -and [IO.File]::Exists($workerResultPath)) {
            # An unsafe ACK can precede the worker's own graceful cleanup.
            # Let it finish without abandoning its owned Excel instance.
            try {
                [IO.File]::WriteAllText((Join-Path $WorkerSession.directory 'stop'),'stop')
                [void]$worker.WaitForExit(10000)
            } catch {}
        }
        try { $worker.Kill(); [void]$worker.WaitForExit(5000) } catch {}
        if($record.category -notin @('WorkerTimeout','WorkerSessionUnsafe')) { $record.category='WorkerInterrupted'; $record.message='WorkerInterruptedExcelMayRemain' }
    }
    if($null -ne $hold) { $hold.Dispose() }
    if($null -ne $worker -and $null -eq $WorkerSession) { $worker.Dispose() }
    foreach($secretPath in @($RequestPath,$jobPath)) { if([IO.File]::Exists($secretPath)) { try { [IO.File]::Delete($secretPath) } catch { $record.message='TemporaryCleanupIncomplete' } } }
    $request=$null
    if(-not $preserveTemp) {
        foreach($ownedPath in @($inputCopy,$temp)) {
            if($ownedPath -and [IO.File]::Exists($ownedPath)) {
                try { [IO.File]::Delete($ownedPath) } catch { $record.message='TemporaryCleanupIncomplete' }
            }
        }
        if($record.status -eq 'Success' -and $record.recovery -and [IO.File]::Exists($record.recovery)) {
            try {
                if((Get-Sha $record.backup) -ne $record.sourceHash -or (Get-Sha $record.recovery) -ne $record.sourceHash -or (Get-Sha $record.path) -ne $record.resultHash) { throw 'RecoveryCleanupNotSafe' }
                [IO.File]::Delete($record.recovery)
                $record.recoveryRemoved=$true
            } catch { $record.message='TemporaryCleanupIncomplete' }
        }
    }
    if($null -ne $mutex) { if($locked) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
    $record.time=[DateTime]::UtcNow.ToString('o')
    if(-not $record.message) { $record.message=$record.category }
    Write-Json $record $resultPath
}
if($record.status -in @('Success','Skipped')) { exit 0 }
if($record.status -eq 'Cancelled') { exit 2 }
exit 1
