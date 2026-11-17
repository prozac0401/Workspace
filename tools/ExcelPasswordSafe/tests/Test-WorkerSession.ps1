#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Wait until Excel tests finish before running worker session tests.'}
$toolRoot=Split-Path -Parent $PSScriptRoot
if(-not $EvidenceDirectory){$EvidenceDirectory=Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $toolRoot)) 'artifacts/excel-password-safe/worker-session') ([guid]::NewGuid().ToString('N'))}
if(Test-Path -LiteralPath $EvidenceDirectory){throw 'Use a new evidence directory.'}
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($evidence)
$snapshot=Join-Path $evidence 'runtime-snapshot'
[void][IO.Directory]::CreateDirectory($snapshot)
foreach($name in @('Common.ps1','ExcelPassword.Worker.ps1')){[IO.File]::Copy((Join-Path $toolRoot ('runtime/'+$name)),(Join-Path $snapshot $name),$false)}
. (Join-Path $snapshot 'Common.ps1')
$worker=Join-Path $snapshot 'ExcelPassword.Worker.ps1'
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass) { $checks.Add([pscustomobject]@{name=$Name;pass=$Pass}); if(-not $Pass){throw $Name} }
try {
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($worker,[ref]$tokens,[ref]$errors)
Check 'PowerShell51Syntax' ($errors.Count -eq 0)
foreach($case in @('StopBeforeFirstJob','OwnerIdentityChanged','WrongToken','SequenceGap','JobOutsideRun','MalformedQueue')) {
    $directory=Join-Path $evidence $case
    [void][IO.Directory]::CreateDirectory($directory)
    $sessionDir=Join-Path $directory 'worker-session'
    [void][IO.Directory]::CreateDirectory($sessionDir)
    $token=[guid]::NewGuid().ToString('N')
    $owner=[Diagnostics.Process]::GetCurrentProcess()
    try {$ownerTicks=$owner.StartTime.ToUniversalTime().Ticks} finally {$owner.Dispose()}
    if($case -eq 'OwnerIdentityChanged'){$ownerTicks--}
    Write-Json @{schemaVersion=1;ownerPid=$PID;ownerStartTicks=$ownerTicks;token=$token} (Join-Path $sessionDir 'session.json')
    if($case -eq 'StopBeforeFirstJob'){[IO.File]::WriteAllText((Join-Path $sessionDir 'stop'),'stop')}
    if($case -in @('WrongToken','SequenceGap','JobOutsideRun')){
        $queueToken=if($case -eq 'WrongToken'){[guid]::NewGuid().ToString('N')}else{$token}
        $sequence=if($case -eq 'SequenceGap'){2}else{1}
        Write-Json @{token=$queueToken;sequence=$sequence;jobPath=(Join-Path $evidence 'outside/worker-job.json')} (Join-Path $sessionDir 'next-job.json')
    }
    if($case -eq 'MalformedQueue'){[IO.File]::WriteAllText((Join-Path $sessionDir 'next-job.json'),'{bad')}
    $arguments='-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$worker+'" -SessionPath "'+(Join-Path $sessionDir 'session.json')+'"'
    $process=Start-Process (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $directory 'stdout.txt') -RedirectStandardError (Join-Path $directory 'stderr.txt')
    try {$null=$process.Handle;if(-not $process.WaitForExit(15000)){throw ($case+' timed out')};Check ($case+'Exit') ($process.ExitCode -eq 0)}finally{$process.Dispose()}
    $result=Get-Content -LiteralPath (Join-Path $sessionDir 'finished.json') -Raw -Encoding UTF8|ConvertFrom-Json
    $expected=if($case -in @('StopBeforeFirstJob','OwnerIdentityChanged')){'Stopped'}else{'Failed'}
    Check ($case+'Status') ($result.status -eq $expected)
    Check ($case+'NoExcelStarted') ($result.excelPid -eq 0 -and $result.excelExited -eq $true -and $result.workbooksClosed -eq $true)
    Check ($case+'Token') ($result.sessionToken -ceq $token)
}
# Exercise shutdown decisions without any Excel or GUI through direct test doubles.
foreach($name in @('Set-WorkerUnsafeMarker','Show-WorkerApplication','Get-WorkerWorkbookCounts','Assert-WorkerIdle','Stop-WorkerExcel')) {
    $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    Invoke-Expression $function.Extent.Text
}
function Test-WorkerProcess([int]$ProcessId,[long]$StartTicks){$script:identityReads++;return ($script:identityReads -eq 1)}
$script:workerSessionDirectory=Join-Path $evidence 'mock-session'; [void][IO.Directory]::CreateDirectory($script:workerSessionDirectory)
$script:workerSessionToken=[guid]::NewGuid().ToString('N')
$script:identityReads=0;$script:workerOwned=$true;$script:workerExcelPid=123;$script:workerExcelStartTicks=1
$app=[pscustomobject]@{DisplayAlerts=$false;Visible=$false;QuitCalled=$false;ProtectedViewWindows=[pscustomobject]@{Count=0}}
$app|Add-Member ScriptMethod Quit {$this.QuitCalled=$true}
$script:workerApp=$app;$script:workerBooks=[pscustomobject]@{Count=1}
$cleanup=Stop-WorkerExcel
Check 'UnexpectedWorkbookNeverQuit' (-not $app.QuitCalled -and $cleanup.status -eq 'Failed')
Check 'UnexpectedWorkbookVisibleWithAlerts' ($app.DisplayAlerts -and $app.Visible)
Check 'UnexpectedWorkbookNeverClaimsClosed' (-not $cleanup.workbooksClosed)
$script:identityReads=0;$script:workerOwned=$true;$script:workerExcelPid=123;$script:workerExcelStartTicks=1
$app=[pscustomobject]@{DisplayAlerts=$false;Visible=$false;QuitCalled=$false;AlertsAtQuit=$false;ProtectedViewWindows=[pscustomobject]@{Count=0}}
$app|Add-Member ScriptMethod Quit {$this.QuitCalled=$true;$this.AlertsAtQuit=$this.DisplayAlerts}
$script:workerApp=$app;$script:workerBooks=[pscustomobject]@{Count=0}
$cleanup=Stop-WorkerExcel
Check 'KnownEmptyOwnedApplicationQuits' ($app.QuitCalled -and $cleanup.status -eq 'Stopped' -and $cleanup.workbooksClosed -and $cleanup.excelExited)
Check 'PromptsRestoredBeforeQuit' $app.AlertsAtQuit
$script:workerSessionDirectory=Join-Path $evidence 'mock-protected-view-session'; [void][IO.Directory]::CreateDirectory($script:workerSessionDirectory)
$script:identityReads=0;$script:workerOwned=$true;$script:workerExcelPid=123;$script:workerExcelStartTicks=1
$app=[pscustomobject]@{DisplayAlerts=$false;Visible=$false;QuitCalled=$false;ProtectedViewWindows=[pscustomobject]@{Count=1}}
$app|Add-Member ScriptMethod Quit {$this.QuitCalled=$true}
$script:workerApp=$app;$script:workerBooks=[pscustomobject]@{Count=0}
$idleRejected=$false
try { Assert-WorkerIdle } catch { $idleRejected=$true }
Check 'ProtectedViewBlocksIdle' $idleRejected
$marker=Get-Content -LiteralPath (Join-Path $script:workerSessionDirectory 'unsafe.json') -Raw -Encoding UTF8|ConvertFrom-Json
Check 'UnsafeMarkerPublishedBeforeCleanup' ($marker.category -eq 'WorkerSessionUnsafe' -and $marker.sessionToken -ceq $script:workerSessionToken -and -not $app.QuitCalled)
$script:identityReads=0
$cleanup=Stop-WorkerExcel
Check 'ProtectedViewNeverQuit' (-not $app.QuitCalled -and $cleanup.status -eq 'Failed' -and -not $cleanup.workbooksClosed)
Check 'ProtectedViewMadeVisibleWithAlerts' ($app.Visible -and $app.DisplayAlerts)
$script:identityReads=0;$script:mockProtectedReads=0
$app=[pscustomobject]@{DisplayAlerts=$false;Visible=$false;QuitCalled=$false}
$app|Add-Member ScriptMethod Quit {$this.QuitCalled=$true}
$app|Add-Member ScriptProperty ProtectedViewWindows {$script:mockProtectedReads++;[pscustomobject]@{Count=$(if($script:mockProtectedReads -ge 2){1}else{0})}}
$script:workerApp=$app;$script:workerBooks=[pscustomobject]@{Count=0}
$cleanup=Stop-WorkerExcel
Check 'DocumentOpeningBeforeQuitIsRechecked' (-not $app.QuitCalled -and $cleanup.status -eq 'Failed' -and $app.Visible)
Write-Json @{status='PASS';utc=[DateTime]::UtcNow.ToString('o');workerSha256=(Get-Sha $worker);commonSha256=(Get-Sha (Join-Path $snapshot 'Common.ps1'));checks=$checks;passed=$checks.Count;actualExcelStarted=$false;scope='Protocol processes and direct cleanup test doubles only; no real Excel or GUI'} (Join-Path $evidence 'worker-session-results.json')
Write-Host ($checks.Count.ToString()+' checks PASS; no Excel started')
} catch {
    Write-Json @{status='FAIL';utc=[DateTime]::UtcNow.ToString('o');workerSha256=(Get-Sha $worker);checks=$checks;error=$_.Exception.Message;actualExcelStarted=$false} (Join-Path $evidence 'worker-session-results.json')
    throw
}
