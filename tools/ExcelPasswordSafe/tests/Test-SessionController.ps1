#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $toolRoot 'runtime/Common.ps1')
if(-not $EvidenceDirectory) { $EvidenceDirectory=Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $toolRoot)) 'artifacts/excel-password-safe/session-controller') ([guid]::NewGuid().ToString('N')) }
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$encoding=New-Object Text.UTF8Encoding($true)
$snapshot=Join-Path $EvidenceDirectory 'runtime-snapshot'
[void][IO.Directory]::CreateDirectory($snapshot)
foreach($name in @('Engine.ps1','Common.ps1')) { [IO.File]::Copy((Join-Path $toolRoot ('runtime/'+$name)),(Join-Path $snapshot $name)) }

# These overrides exist ONLY in the copied fixture runtime. EXCEL enumeration
# returns an ordinary fixture PowerShell process; the real identity validator,
# transaction, private backup, hashes and File.Replace remain in use. A unique
# mutex prevents conflict with real product/Excel tests running at the same time.
$fixtureOverrides=@'
$script:FixtureRealIdentity=${function:Test-ProcessIdentity}
$script:FixtureRealWriteJson=${function:Write-Json}
$script:FixtureRealSha=${function:Get-Sha}
function Get-EngineMutexName { 'Local\ExcelPasswordSafe.SessionFixture.'+([IO.Path]::GetFileName($PSScriptRoot)) }
function Get-Process {
 param([string]$Name,[object]$ErrorAction)
 if($Name -ne 'EXCEL') { throw 'Fixture forbids unrelated process enumeration.' }
 $identityPath=Join-Path $PSScriptRoot 'fixture-excel.json'
 if([IO.File]::Exists($identityPath)) {
  $identity=Get-Content -LiteralPath $identityPath -Raw -Encoding UTF8 | ConvertFrom-Json
  [pscustomobject]@{Id=[int]$identity.pid}
 }
}
function Test-ProcessIdentity([int]$ProcessId,[string]$StartTicks) {
 $config=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixture-config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($ProcessId -eq $config.ownerPid -and [IO.File]::Exists((Join-Path $PSScriptRoot 'fixture-owner-gone'))) { return $false }
 & $script:FixtureRealIdentity $ProcessId $StartTicks
}
function Get-Sha([string]$Path) {
 $hash=& $script:FixtureRealSha $Path
 $config=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixture-config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($config.case -eq 'UnsafeSignalBeforeCommit' -and $PID -eq $config.ownerPid -and [IO.Path]::GetFileName($Path) -match '^\.eps-[0-9a-f]{32}\.xlsx$') {
  $progressPath=Join-Path ([IO.Path]::GetDirectoryName([string]$config.entries[0].request)) 'progress.json'
  if([IO.File]::Exists($progressPath)) {
   $progress=Get-Content -LiteralPath $progressPath -Raw -Encoding UTF8 | ConvertFrom-Json
   if($progress.stage -eq 'Commit') {
    # Inject after the validated output has been hashed, immediately before
    # the controller's final source/session checks. No shipped hook is used.
    $sessionDirectory=Join-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) 'session'
    Write-Json @{category='WorkerSessionUnsafe'} (Join-Path $sessionDirectory 'unsafe.json')
   }
  }
 }
 return $hash
}
function Write-Json($Value,[string]$Path) {
 & $script:FixtureRealWriteJson $Value $Path
 $config=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixture-config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($config.case -eq 'OwnerGoneBeforeCommit' -and [IO.Path]::GetFileName($Path) -eq 'progress.json' -and $Value.stage -eq 'Commit') {
  [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'fixture-owner-gone'),'fixture-only owner identity loss')
 }
 if($config.case -eq 'SessionLostBeforeCommit' -and [IO.Path]::GetFileName($Path) -eq 'progress.json' -and $Value.stage -eq 'Commit') {
  $identity=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixture-excel.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  # The fixture identity is the child PowerShell started by this isolated test.
  $child=[Diagnostics.Process]::GetProcessById([int]$identity.pid)
  try { $child.Kill(); [void]$child.WaitForExit(5000) } finally { $child.Dispose() }
 }
}
'@
$fixtureWorker=@'
param([string]$SessionPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
$session=Get-Content -LiteralPath $SessionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$directory=[IO.Path]::GetDirectoryName($SessionPath)
$config=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixture-config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$self=[Diagnostics.Process]::GetCurrentProcess()
try { $start=$self.StartTime.ToUniversalTime().Ticks.ToString() } finally { $self.Dispose() }
Write-Json @{pid=$PID;start=$start} (Join-Path $PSScriptRoot 'fixture-excel.json')
$deadline=[DateTime]::UtcNow.AddSeconds(40)
while([DateTime]::UtcNow -lt $deadline) {
 if([IO.File]::Exists((Join-Path $directory 'stop'))) {
  Write-Json @{sessionToken=$session.token;status='Stopped';workbooksClosed=$true;excelExited=$true} (Join-Path $directory 'finished.json')
  exit 0
 }
 $nextPath=Join-Path $directory 'next-job.json'
 if(-not [IO.File]::Exists($nextPath)) { Start-Sleep -Milliseconds 20; continue }
 $envelope=Get-Content -LiteralPath $nextPath -Raw -Encoding UTF8 | ConvertFrom-Json
 [IO.File]::Delete($nextPath)
 $job=Get-Content -LiteralPath $envelope.jobPath -Raw -Encoding UTF8 | ConvertFrom-Json
 if($config.case -eq 'ExitedBeforeResult') { exit 17 }
 [IO.File]::WriteAllText([string]$job.temp,('validated fixture output '+$envelope.sequence))
 if($config.case -eq 'MissingResult') { exit 18 }
 $result=@{status='Validated';category='Validated';stage='Verify';hresults='';message='';tempHash=(Get-Sha $job.temp);sessionToken=$session.token;sequence=$envelope.sequence;sessionReady=$true;workbooksClosed=$true;excelPid=$PID;excelStartTicks=$start}
 switch($config.case) {
  'BadToken' { $result.sessionToken='different-session' }
  'BadSequence' { $result.sequence=[int]$envelope.sequence+1 }
  'MissingSessionReady' { $result.Remove('sessionReady') }
  'MissingWorkbooksClosed' { $result.Remove('workbooksClosed') }
  'MissingExcelStart' { $result.Remove('excelStartTicks') }
  'WorkbooksRemain' { $result.workbooksClosed=$false }
  'SessionNotReady' { $result.sessionReady=$false }
  'StringSessionReady' { $result.sessionReady='True' }
  'StringWorkbooksClosed' { $result.workbooksClosed='True' }
  'IdentityMismatch' { $result.excelStartTicks='1' }
  'IdentityRebound' {
   if($envelope.sequence -eq 2) {
    $result.excelPid=[int]$config.ownerPid; $result.excelStartTicks=[string]$config.ownerStart
    Write-Json @{pid=$result.excelPid;start=$result.excelStartTicks} (Join-Path $PSScriptRoot 'fixture-excel.json')
   }
  }
  'TamperedOutput' { [IO.File]::WriteAllText([string]$job.temp,'changed after validation') }
 }
 Write-Json $result ([string]$job.result)
}
exit 19
'@
$runner=@'
param([string]$ConfigPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$config=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$self=[Diagnostics.Process]::GetCurrentProcess()
try { $ownerStart=$self.StartTime.ToUniversalTime().Ticks.ToString() } finally { $self.Dispose() }
$config.ownerPid=$PID; $config.ownerStart=$ownerStart
Write-Json $config $ConfigPath
$session=@{directory=(Join-Path ([IO.Path]::GetDirectoryName($PSScriptRoot)) 'session');token=[guid]::NewGuid().ToString('N');sequence=0;process=$null;healthy=$false;excelPid=0;excelStartTicks='';userOwnerPid=$PID;userOwnerStart=$ownerStart}
$runs=New-Object 'System.Collections.Generic.List[object]'
$summary=@{runs=@();workerStopped=$false;error='';sequence=0}
try {
 foreach($entry in @($config.entries)) {
  if($config.case -eq 'UnsafeSignalAtPreflight' -and $session.sequence -eq 1) {
   # The first job establishes a genuine fixture process identity. The next
   # call must reject this signal before it takes a backup or publishes a job.
   Write-Json @{category='WorkerSessionUnsafe'} (Join-Path $session.directory 'unsafe.json')
  }
  & (Join-Path $PSScriptRoot 'Engine.ps1') -RequestPath ([string]$entry.request) -WorkerSession $session | Out-Null
  $resultPath=Join-Path ([IO.Path]::GetDirectoryName([string]$entry.request)) 'result.json'
  $runs.Add((Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json))
  if(-not $session.healthy) { break }
 }
} catch { $summary.error=$_.Exception.Message }
finally {
 if($null -ne $session.process) {
  try {
   if(-not $session.process.HasExited) {
    [IO.File]::WriteAllText((Join-Path $session.directory 'stop'),'stop')
    if(-not $session.process.WaitForExit(5000)) { $session.process.Kill(); [void]$session.process.WaitForExit(5000) }
   }
   $summary.workerStopped=$session.process.HasExited
  } finally { $session.process.Dispose() }
 }
 $summary.sequence=$session.sequence; $summary.runs=$runs.ToArray()
 Write-Json $summary ([string]$config.summary)
}
'@
$cases=@('ValidSequentialJobs','BadToken','BadSequence','MissingSessionReady','MissingWorkbooksClosed','MissingExcelStart','WorkbooksRemain','SessionNotReady','StringSessionReady','StringWorkbooksClosed','IdentityMismatch','IdentityRebound','MissingResult','ExitedBeforeResult','OwnerGoneBeforeCommit','SessionLostBeforeCommit','UnsafeSignalBeforeCommit','UnsafeSignalAtPreflight','TamperedOutput')
$records=New-Object 'System.Collections.Generic.List[object]'
$secure=ConvertTo-SecureString 'Fixture-42!' -AsPlainText -Force
try { $cipher=ConvertFrom-SecureString $secure } finally { $secure.Dispose() }
$assertions=0
foreach($case in $cases) {
 $caseRoot=Join-Path $EvidenceDirectory $case
 $runtime=Join-Path $caseRoot ([guid]::NewGuid().ToString('N'))
 [void][IO.Directory]::CreateDirectory($runtime)
 foreach($name in @('Engine.ps1','Common.ps1')) { [IO.File]::Copy((Join-Path $snapshot $name),(Join-Path $runtime $name)) }
 [IO.File]::AppendAllText((Join-Path $runtime 'Common.ps1'),("`r`n"+$fixtureOverrides),$encoding)
 [IO.File]::WriteAllText((Join-Path $runtime 'ExcelPassword.Worker.ps1'),$fixtureWorker,$encoding)
 [IO.File]::WriteAllText((Join-Path $runtime 'fixture-runner.ps1'),$runner,$encoding)
 $count=if($case -eq 'ValidSequentialJobs'){3}elseif($case -in @('IdentityRebound','UnsafeSignalAtPreflight')){2}else{1}
 $entries=@()
 for($index=1;$index -le $count;$index++) {
  $source=Join-Path $caseRoot ('source-'+$index+'.xlsx')
  [IO.File]::WriteAllText($source,('original synthetic source '+$index))
  $before=Get-Sha $source
  $run=Join-Path $caseRoot ([guid]::NewGuid().ToString('N'))
  [void][IO.Directory]::CreateDirectory($run); Set-PrivateDirectory $run
  $request=Join-Path $run 'request.json'
  Write-Json @{schemaVersion=1;path=$source;mode='Encrypt';oldSecret='';newSecret=$cipher;expectedHash=$before} $request
  $entries+=@{source=$source;before=$before;request=$request;run=$run}
 }
 $summaryPath=Join-Path $caseRoot 'runner-result.json'
 $configPath=Join-Path $runtime 'fixture-config.json'
 Write-Json @{case=$case;ownerPid=0;ownerStart='';entries=$entries;summary=$summaryPath} $configPath
 $script=Join-Path $runtime 'fixture-runner.ps1'
 $process=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$script+'" -ConfigPath "'+$configPath+'"') -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $caseRoot 'stdout.log') -RedirectStandardError (Join-Path $caseRoot 'stderr.log')
 try {
  if(-not $process.WaitForExit(20000)) { $process.Kill(); throw ('Fixture controller timed out: '+$case) }
 } finally { $process.Dispose() }
 if(-not [IO.File]::Exists($summaryPath)) { throw ('Fixture controller produced no summary: '+$case) }
 $summary=Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
 $checks=New-Object 'System.Collections.Generic.List[object]'
 $checks.Add(@{name='controller completed';passed=([string]$summary.error -eq '')})
 $checks.Add(@{name='fixture worker stopped';passed=($summary.workerStopped -eq $true)})
 $expectedSequence=if($case -eq 'UnsafeSignalAtPreflight'){1}else{$count}
 $checks.Add(@{name='expected job count';passed=(@($summary.runs).Count -eq $count -and $summary.sequence -eq $expectedSequence)})
 for($index=0;$index -lt @($summary.runs).Count;$index++) {
  $result=@($summary.runs)[$index]; $entry=$entries[$index]
  $success=$case -eq 'ValidSequentialJobs' -or ($case -in @('IdentityRebound','UnsafeSignalAtPreflight') -and $index -eq 0)
  if($case -eq 'UnsafeSignalAtPreflight' -and $index -eq 1) {
   $checks.Add(@{name='preflight unsafe signal rejected';passed=($result.status -eq 'Failed' -and $result.category -eq 'WorkerSessionUnsafe')})
   $checks.Add(@{name='preflight original unchanged';passed=((Get-Sha $entry.source) -eq $entry.before)})
   $checks.Add(@{name='preflight no backup or work copies created';passed=(-not $result.backup -and -not $result.inputCopy -and -not $result.temp)})
   $checks.Add(@{name='preflight secret request removed';passed=(-not [IO.File]::Exists($entry.request) -and -not [IO.File]::Exists((Join-Path $entry.run 'worker-job.json')))})
   continue
  }
  $checks.Add(@{name=('backup exact '+$index);passed=($result.backup -and [IO.File]::Exists($result.backup) -and (Get-Sha $result.backup) -eq $entry.before)})
  $checks.Add(@{name=('secret files removed '+$index);passed=(-not [IO.File]::Exists($entry.request) -and -not [IO.File]::Exists((Join-Path $entry.run 'worker-job.json')))})
  if($success) {
   $checks.Add(@{name=('validated output committed '+$index);passed=($result.status -eq 'Success' -and $result.category -eq 'ReplacedAndVerified' -and [IO.File]::ReadAllText($entry.source) -eq ('validated fixture output '+($index+1)))})
   $checks.Add(@{name=('owned intermediates removed '+$index);passed=(-not [IO.File]::Exists($result.inputCopy) -and -not [IO.File]::Exists($result.temp) -and -not [IO.File]::Exists($result.recovery) -and $result.recoveryRemoved -eq $true)})
  } else {
   $expected=if($case -eq 'OwnerGoneBeforeCommit'){@('OwnerExited')}elseif($case -in @('MissingResult','ExitedBeforeResult')){@('WorkerCrashed')}elseif($case -eq 'TamperedOutput'){@('TempChanged')}else{@('WorkerSessionUnsafe','WorkerInterrupted')}
   $checks.Add(@{name=('failure classified '+$index);passed=($result.status -in @('Failed','Cancelled') -and $result.category -in $expected)})
   $checks.Add(@{name=('original unchanged '+$index);passed=((Get-Sha $entry.source) -eq $entry.before)})
   if($case -in @('OwnerGoneBeforeCommit','TamperedOutput')) {
    $checks.Add(@{name=('idle failure safely cleaned '+$index);passed=(-not [IO.File]::Exists($result.inputCopy) -and -not [IO.File]::Exists($result.temp))})
   } else {
    $checks.Add(@{name=('uncertain input preserved '+$index);passed=([IO.File]::Exists($result.inputCopy))})
    if($case -ne 'ExitedBeforeResult') { $checks.Add(@{name=('uncertain output preserved '+$index);passed=([IO.File]::Exists($result.temp))}) }
   }
  }
 }
 $assertions+=$checks.Count
 $passed=@($checks | Where-Object { -not $_.passed }).Count -eq 0
 $records.Add(@{case=$case;passed=$passed;checks=$checks.ToArray();categories=@($summary.runs | ForEach-Object { $_.category })})
 Write-Json @{status=$(if(@($records | Where-Object { -not $_.passed }).Count){'FAIL'}else{'PASS'});caseCount=$records.Count;assertionCount=$assertions;results=$records.ToArray();realExcel='NOT RUN; isolated enumeration and mutex';engineHash=(Get-Sha (Join-Path $snapshot 'Engine.ps1'));commonHash=(Get-Sha (Join-Path $snapshot 'Common.ps1'))} (Join-Path $EvidenceDirectory 'session-controller-results.json')
}
if(@($records | Where-Object { -not $_.passed }).Count) { throw ('Session controller fixture failed: '+(@($records | Where-Object { -not $_.passed } | ForEach-Object { $_.case }) -join ', ')) }
Write-Output "PASS: $($records.Count) session controller cases, $assertions assertions; $EvidenceDirectory"
