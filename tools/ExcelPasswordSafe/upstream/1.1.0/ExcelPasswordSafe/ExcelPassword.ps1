#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param(
    [ValidateSet('Encrypt','Decrypt')][string]$Mode='Encrypt',
    [string]$Root,
    [string]$BackupRoot,
    [string]$RetryLog,
    [switch]$Execute,
    [ValidateRange(1,3)][int]$MaxAttempts=2,
    [ValidateRange(30,3600)][int]$TimeoutSeconds=180
)
. (Join-Path $PSScriptRoot 'Common.ps1')
if($env:OS -ne 'Windows_NT') { throw 'Windows desktop Excel is required.' }
if(-not $Root) { $Root=Read-Host 'Target folder (subfolders included)' }
$Root=[IO.Path]::GetFullPath($Root).TrimEnd('\')
if(-not (Test-Path -LiteralPath $Root -PathType Container)) { throw 'Target directory not found.' }
Assert-NoReparse $Root
if($Root.StartsWith('\\') -or $Root.Length -le 3) { throw 'Use a local subfolder, not UNC or an entire drive.' }
$drive=New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($Root))
if($drive.DriveType -ne [IO.DriveType]::Fixed -or $drive.DriveFormat -ne 'NTFS') { throw 'Only local fixed NTFS volumes are supported.' }
if(-not $BackupRoot) { $BackupRoot=$Root+'.ExcelPasswordSafe' }
$BackupRoot=[IO.Path]::GetFullPath($BackupRoot).TrimEnd('\')
if($BackupRoot -eq $Root -or $BackupRoot.StartsWith($Root+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'BackupRoot must be outside the target tree.' }
if($BackupRoot.StartsWith('\\')) { throw 'BackupRoot must be local.' }
$existing=$BackupRoot
while(-not (Test-Path -LiteralPath $existing)) { $existing=Split-Path -Parent $existing }
Assert-NoReparse $existing
$runId=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$runDir=Join-Path $BackupRoot $runId
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
# Backups may be plaintext; restrict inheritance BEFORE any workbook is copied.
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
foreach($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User,(New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'))) {
    $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $runDir -AclObject $acl
$log=Join-Path $runDir 'results.csv'
$planPath=Join-Path $runDir 'plan.csv'
$previous=@{}
if($RetryLog) {
    foreach($row in Import-Csv -LiteralPath $RetryLog) {
        if($row.mode -ne $Mode) { throw 'RetryLog mode mismatch.' }
        $previous[$row.path]=$row
    }
}
$plan=New-Object 'System.Collections.Generic.List[object]'
# Enumeration errors abort BEFORE approval/mutation. Never silently omit denied folders.
try { $candidates=@(Get-Candidates $Root | Sort-Object) }
catch {
    [pscustomobject]@{time=(Get-Date).ToString('o');mode=$Mode;path=$Root;status='Failed';category='EnumerationFailed';message=$_.Exception.Message} | Export-Csv -LiteralPath $log -NoTypeInformation -Encoding UTF8
    throw
}
foreach($path in $candidates) {
    if($RetryLog) {
        if(-not $previous.ContainsKey($path)) { continue }
        if($previous[$path].status -in @('Success','Skipped')) { continue }
        if($previous[$path].category -eq 'CommitUncertain') { throw 'CommitUncertain requires manual inspection before retry.' }
    }
    $hash=''; $errorText=''; $preflightCategory=''; $preflightHResults=''
    try { $hash=Get-Sha $path } catch {
        $errorText=$_.Exception.Message
        $preflightCategory=Get-Category $_ 'Preflight'
        $preflightHResults=Get-HResults $_
    }
    if($RetryLog -and $hash -and $previous[$path].sourceHash -and $hash -ne $previous[$path].sourceHash) {
        $errorText='ChangedSinceRetryLog: inspect manually.'
        $preflightCategory='ChangedSinceRetryLog'
    }
    $relative=$path.Substring($Root.Length+1)
    $plan.Add([pscustomobject]@{path=$path;sourceHash=$hash;backup=(Join-Path (Join-Path $runDir 'originals') $relative);preflightError=$errorText;preflightCategory=$preflightCategory;preflightHResults=$preflightHResults})
}
$plan.ToArray() | Export-Csv -LiteralPath $planPath -NoTypeInformation -Encoding UTF8
Write-Host "Mode: $Mode | Files: $($plan.Count)"
Write-Host "Exact target list: $planPath"
Write-Host "Backup tree (original bytes, including plaintext): $runDir\originals"
Write-Host 'Sequence: lock -> hash -> backup/hash -> COM temp -> reopen/password/content guards -> atomic replace.'
$plan.ToArray() | Format-Table path,backup,preflightError -AutoSize -Wrap | Out-Host
if(-not $Execute) { Write-Host 'PLAN ONLY. Run again with -Execute to review and approve a new plan.'; exit 0 }
if(-not $plan.Count) { exit 0 }
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Close all Excel windows normally, then retry. No Excel process will be forcibly stopped.' }
$token='APPLY-'+$runId
if((Read-Host "Review ALL targets and backups above. Type $token to permit overwrite") -cne $token) { Write-Host 'Cancelled.'; exit 2 }
$oldSecret=Read-Host 'Existing opening password (Enter if none; never put passwords in arguments)' -AsSecureString
$oldCipher=if($oldSecret.Length){ConvertFrom-SecureString $oldSecret}else{''}; $oldSecret.Dispose()
$newCipher=''
if($Mode -eq 'Encrypt') {
    $newSecret=Read-Host 'New opening password (1-15 characters for cross-format compatibility)' -AsSecureString
    $confirmSecret=Read-Host 'Repeat new password' -AsSecureString
    $newCipher=ConvertFrom-SecureString $newSecret
    $a=Unprotect-Text $newCipher; $b=Unprotect-Text (ConvertFrom-SecureString $confirmSecret)
    try { if($a.Length -lt 1 -or $a.Length -gt 15 -or $a -cne $b) { throw 'Password mismatch or unsupported length.' } }
    finally { $a=''; $b=''; $newSecret.Dispose(); $confirmSecret.Dispose() }
}
$mutex=New-Object Threading.Mutex($false,'Local\ExcelPasswordSafe.Controller')
if(-not $mutex.WaitOne(0)) { $mutex.Dispose(); throw 'Another ExcelPasswordSafe run is active.' }
$systemFailures=0; $circuit=$false; $hadFailure=$false
try {
    foreach($entry in $plan.ToArray()) {
        $record=[ordered]@{time='';run=$runId;mode=$Mode;path=$entry.path;sourceHash=$entry.sourceHash;backup=$entry.backup;temp='';attempt=0;status='Failed';category='';stage='Preflight';hresults='';message='';resultHash=''}
        $hold=$null; $worker=$null; $jobPath=''; $resultPath=''; $temp=''; $inputCopy=''; $statePath=Join-Path $runDir ([guid]::NewGuid().ToString('N')+'.state.json'); $preserveTemp=$false
        try {
            if($circuit) { $record.category='SystemCircuitOpen'; throw 'COM environment requires inspection; no further files opened.' }
            if($entry.preflightError) { $record.category=$entry.preflightCategory; $record.hresults=$entry.preflightHResults; throw $entry.preflightError }
            Assert-NoReparse $entry.path
            $attrs=(Get-Item -LiteralPath $entry.path -Force).Attributes
            if($attrs -band [IO.FileAttributes]::ReadOnly) { $record.category='ReadOnlyAttribute'; throw 'File is read-only.' }
            $ownerFile=Join-Path (Split-Path -Parent $entry.path) ('~$'+[IO.Path]::GetFileName($entry.path))
            if(Test-Path -LiteralPath $ownerFile) { $record.category='FileInUse'; throw 'Excel owner file exists; close the file normally.' }
            # Deny writes throughout backup/conversion/commit; allow delete for ReplaceFile.
            $hold=[IO.File]::Open($entry.path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::Read -bor [IO.FileShare]::Delete))
            if((Get-StreamSha $hold) -ne $entry.sourceHash) { $record.category='SourceChanged'; throw 'Source changed after approval.' }
            $record.stage='Backup'
            New-Item -ItemType Directory -Path (Split-Path -Parent $entry.backup) -Force | Out-Null
            $out=[IO.File]::Open($entry.backup,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try { $hold.Position=0; $hold.CopyTo($out); $out.Flush($true) } finally { $out.Dispose(); $hold.Position=0 }
            if((Get-Sha $entry.backup) -ne $entry.sourceHash) { throw 'BackupHashMismatch' }
            for($attempt=1;$attempt -le $MaxAttempts;$attempt++) {
                $record.attempt=$attempt; $record.stage='Worker'
                if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { $record.category='ExistingExcel'; $circuit=$true; throw 'Excel is running; close it normally before retry.' }
                $id=[guid]::NewGuid().ToString('N')
                $temp=Join-Path (Split-Path -Parent $entry.path) ('.eps-'+$id+[IO.Path]::GetExtension($entry.path))
                $record.temp=$temp
                $inputCopy=Join-Path (Split-Path -Parent $entry.path) ('.eps-'+$id+'-source'+[IO.Path]::GetExtension($entry.path))
                [IO.File]::Copy($entry.backup,$inputCopy,$false)
                if((Get-Sha $inputCopy) -ne $entry.sourceHash) { throw 'SnapshotHashMismatch' }
                $jobPath=Join-Path $runDir ($id+'.job.json'); $resultPath=Join-Path $runDir ($id+'.result.json')
                Write-Json @{mode=$Mode;input=$inputCopy;backup=$entry.backup;temp=$temp;result=$resultPath;oldSecret=$oldCipher;newSecret=$newCipher} $jobPath
                $workerScript=Join-Path $PSScriptRoot 'ExcelPassword.Worker.ps1'
                $arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "'+$workerScript+'" -JobPath "'+$jobPath+'"'
                $worker=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru -WindowStyle Hidden
                if(-not $worker.WaitForExit($TimeoutSeconds*1000)) {
                    # Terminate ONLY the exact PowerShell child created above. Never EXCEL.
                    $worker.Kill(); $worker.WaitForExit(); $circuit=$true; $preserveTemp=$true
                    $record.category='WorkerTimeout'; throw 'Worker timed out. Excel may remain; inspect manually. Source was not replaced.'
                }
                if(-not (Test-Path -LiteralPath $resultPath)) { $record.category='WorkerCrashed'; $circuit=$true; throw 'Worker exited without a result.' }
                $r=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
                $record.category=$r.category; $record.stage=$r.stage; $record.hresults=$r.hresults; $record.message=$r.message
                # Give the owned instance a bounded opportunity to exit normally.
                for($wait=0;$wait -lt 10 -and @(Get-Process EXCEL -ErrorAction SilentlyContinue).Count;$wait++) { Start-Sleep -Milliseconds 500 }
                if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { $circuit=$true; $preserveTemp=$true; $record.category='ExcelStillRunning'; throw 'Excel remains running; inspect and close normally.' }
                Remove-Item -LiteralPath $jobPath -Force; $jobPath=''
                if($r.status -in @('Validated','Skipped')) { break }
                if($r.category -in @('ComRegistrationOrLibrary','ComServerError','ComStartFailed','ComCleanupFailed')) {
                    $systemFailures++
                    if($systemFailures -ge 2 -or $r.category -eq 'ComRegistrationOrLibrary') { $circuit=$true }
                }
                if($circuit -or $attempt -eq $MaxAttempts -or $r.category -notin @('ComServerError','FileInUse')) { break }
                if(Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
                if(Test-Path -LiteralPath $inputCopy) { Remove-Item -LiteralPath $inputCopy -Force }
                Start-Sleep -Seconds $attempt
            }
            if($r.status -eq 'Skipped') { $record.status='Skipped' }
            elseif($r.status -ne 'Validated') { throw 'Worker failed; source retained. See category, stage and HRESULT.' }
            else {
                $record.stage='Commit'
                Write-Json @{state='Validated';path=$entry.path;backup=$entry.backup;temp=$temp;sourceHash=$entry.sourceHash;tempHash=$r.tempHash} $statePath
                if((Get-Sha $temp) -ne $r.tempHash) { $record.category='TempChanged'; throw 'Temporary output changed after validation.' }
                if((Get-Sha $entry.path) -ne $entry.sourceHash -or (Get-StreamSha $hold) -ne $entry.sourceHash) { $record.category='SourceChanged'; throw 'Source changed before commit.' }
                if((Get-Sha $entry.backup) -ne $entry.sourceHash) { $record.category='BackupChanged'; throw 'Backup changed before commit.' }
                $recovery=Join-Path (Split-Path -Parent $entry.path) ('.eps-'+[guid]::NewGuid().ToString('N')+'.recovery')
                $preserveTemp=$true
                Write-Json @{state='CommitIntent';path=$entry.path;backup=$entry.backup;temp=$temp;recovery=$recovery;sourceHash=$entry.sourceHash;tempHash=$r.tempHash} $statePath
                # No delete-then-move fallback. On any uncertain result retain evidence.
                try {
                    $record.resultHash=Invoke-GuardedReplace $entry.path $temp $entry.backup $recovery $entry.sourceHash $r.tempHash $hold
                } catch { $record.category='CommitUncertain'; $circuit=$true; throw }
                Write-Json @{state='Committed';path=$entry.path;backup=$entry.backup;recovery=$recovery;sourceHash=$entry.sourceHash;resultHash=$record.resultHash} $statePath
                $record.status='Success'; $record.category='ReplacedAndVerified'; $preserveTemp=$false
                $record.message='Original backup and atomic recovery retained: '+$recovery
                $systemFailures=0
            }
        } catch {
            if(-not $record.category -or $record.category -eq 'Validated') { $record.category=Get-Category $_ $record.stage }
            if(-not $record.hresults) { $record.hresults=Get-HResults $_ }
            if(-not $record.message) { $record.message=$_.Exception.Message }
            $hadFailure=$true
        } finally {
            if($null -ne $hold) { $hold.Dispose() }
            if($null -ne $worker) { $worker.Dispose() }
            if($jobPath -and (Test-Path -LiteralPath $jobPath)) { Remove-Item -LiteralPath $jobPath -Force }
            if(-not $preserveTemp -and $inputCopy -and (Test-Path -LiteralPath $inputCopy)) { Remove-Item -LiteralPath $inputCopy -Force -ErrorAction SilentlyContinue }
            if(-not $preserveTemp -and $temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
            $record.time=(Get-Date).ToString('o')
            [pscustomobject]$record | Export-Csv -LiteralPath $log -NoTypeInformation -Encoding UTF8 -Append
            Write-Host ($record.status+' | '+$record.category+' | '+$entry.path)
        }
    }
} finally { $oldCipher=''; $newCipher=''; $mutex.ReleaseMutex(); $mutex.Dispose() }
Write-Host "Results: $log"
if($hadFailure) { exit 1 } else { exit 0 }
