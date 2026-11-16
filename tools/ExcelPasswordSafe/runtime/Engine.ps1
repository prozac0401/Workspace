#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RequestPath,
    [ValidateRange(30,3600)][int]$TimeoutSeconds=180
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
$record=[ordered]@{schemaVersion=1;status='Failed';category='';message='';path='';mode='';backup='';recovery='';sourceHash='';resultHash='';stage='Preflight';hresults='';time='';temp='';inputCopy=''}
$mutex=$null; $locked=$false; $hold=$null; $worker=$null; $inputCopy=''; $temp=''; $preserveTemp=$false; $request=$null
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
    Assert-NotCancelled $runDir
    $mutex=New-Object Threading.Mutex($false,(Get-EngineMutexName))
    try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
    if(-not $locked) { throw 'AnotherOperationRunning' }
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'ExistingExcel' }
    $hold=[IO.File]::Open($record.path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
    if((Get-StreamSha $hold) -ne $record.sourceHash) { throw 'SourceChanged' }
    $ext=[IO.Path]::GetExtension($record.path)
    $record.backup=Join-Path $runDir ('original'+$ext)
    if(Test-Path -LiteralPath $record.backup) { throw 'RunAlreadyUsed' }
    Set-Progress 'Backup' '원본을 백업하고 있습니다.'
    Save-State 'Planned'
    Assert-NotCancelled $runDir
    $out=[IO.File]::Open($record.backup,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $hold.Position=0; $hold.CopyTo($out); $out.Flush($true) } finally { $out.Dispose(); $hold.Position=0 }
    if((Get-Sha $record.backup) -ne $record.sourceHash) { throw 'BackupChanged' }
    Save-State 'BackedUp'
    Assert-NotCancelled $runDir
    $id=[guid]::NewGuid().ToString('N')
    $parent=[IO.Path]::GetDirectoryName($record.path)
    $inputCopy=Join-Path $parent ('.eps-'+$id+'-source'+$ext)
    $temp=Join-Path $parent ('.eps-'+$id+$ext)
    $record.inputCopy=$inputCopy; $record.temp=$temp
    [IO.File]::Copy($record.backup,$inputCopy,$false)
    if((Get-Sha $inputCopy) -ne $record.sourceHash) { throw 'SnapshotChanged' }
    Write-Json @{mode=$request.mode;input=$inputCopy;backup=$record.backup;temp=$temp;result=$workerResultPath;oldSecret=$request.oldSecret;newSecret=$request.newSecret} $jobPath
    # Do not retain even DPAPI ciphertext longer than the job needs it.
    [IO.File]::Delete($RequestPath)
    $request.oldSecret=''; $request.newSecret=''
    Set-Progress 'Worker' 'Excel에서 저장하고 암호와 내용을 확인하고 있습니다.'
    Save-State 'WorkerStarted'
    $workerScript=Join-Path $PSScriptRoot 'ExcelPassword.Worker.ps1'
    $arguments='-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$workerScript+'" -JobPath "'+$jobPath+'"'
    $worker=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not $worker.WaitForExit(250)) {
        if([IO.File]::Exists((Join-Path $runDir 'cancel'))) { Set-Progress 'Cancelling' '현재 Excel 확인이 끝나면 원본을 바꾸지 않고 취소합니다.' }
        if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            # Terminate only the PowerShell child that this invocation started.
            $preserveTemp=$true
            $worker.Kill(); $worker.WaitForExit()
            throw 'WorkerTimeout'
        }
    }
    [IO.File]::Delete($jobPath)
    if(-not [IO.File]::Exists($workerResultPath)) { $preserveTemp=$true; throw 'WorkerCrashed' }
    $r=Get-Content -LiteralPath $workerResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    for($wait=0;$wait -lt 20 -and @(Get-Process EXCEL -ErrorAction SilentlyContinue).Count;$wait++) { Start-Sleep -Milliseconds 250 }
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { $preserveTemp=$true; throw 'ExcelStillRunning' }
    Assert-NotCancelled $runDir
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
        Assert-NotCancelled $runDir
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
    $known=@('InvalidRequest','CurrentPasswordRequired','NewPasswordLength','PasswordUnchanged','LocalPathRequired','FileNotFound','LocalNtfsRequired','UnsupportedExtension','TemporaryFileNotSupported','ReadOnlyAttribute','OfflineFileUnsupported','FileInUse','AnotherOperationRunning','ExistingExcel','SourceChanged','RunAlreadyUsed','BackupChanged','SnapshotChanged','WorkerTimeout','WorkerCrashed','ExcelStillRunning','TempChanged','Cancelled')
    if(-not $record.category) {
        if($_.Exception.Message -in $known) { $record.category=$_.Exception.Message }
        elseif($_.Exception.Message -like 'ReparsePoint:*') { $record.category='ReparsePoint' }
        else { $record.category=Get-Category $_ $record.stage }
    }
    if($record.category -eq 'Cancelled') { $record.status='Cancelled' }
    if(-not $record.hresults) { $record.hresults=Get-HResults $_ }
    # Stable categories, not COM exception text: passwords cannot enter this log.
    $record.message=$record.category
} finally {
    # Any failure while monitoring the child (for example a full log disk) must
    # not leave a live writer while its temporary files are being removed.
    if($null -ne $worker -and -not $worker.HasExited) {
        $preserveTemp=$true
        try { $worker.Kill(); [void]$worker.WaitForExit(5000) } catch {}
        if($record.category -ne 'WorkerTimeout') { $record.category='WorkerInterrupted'; $record.message='WorkerInterruptedExcelMayRemain' }
    }
    if($null -ne $hold) { $hold.Dispose() }
    if($null -ne $worker) { $worker.Dispose() }
    foreach($secretPath in @($RequestPath,$jobPath)) { if([IO.File]::Exists($secretPath)) { try { [IO.File]::Delete($secretPath) } catch {} } }
    $request=$null
    if(-not $preserveTemp) {
        foreach($ownedPath in @($inputCopy,$temp)) {
            if($ownedPath -and [IO.File]::Exists($ownedPath)) {
                try { [IO.File]::Delete($ownedPath) } catch { $record.message='TemporaryCleanupIncomplete' }
            }
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
