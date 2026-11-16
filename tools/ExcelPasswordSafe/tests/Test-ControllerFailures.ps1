#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $toolRoot 'runtime/Common.ps1')
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Wait until Excel tests finish before running controller fault tests.' }
if(-not $EvidenceDirectory) { $EvidenceDirectory=Join-Path (Join-Path (Split-Path -Parent (Split-Path -Parent $toolRoot)) 'artifacts/excel-password-safe/controller-faults') ([guid]::NewGuid().ToString('N')) }
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$runtime=Join-Path $EvidenceDirectory 'isolated-test-runtime'
[void][IO.Directory]::CreateDirectory($runtime)
foreach($name in @('Engine.ps1','Common.ps1')) { [IO.File]::Copy((Join-Path $toolRoot ('runtime/'+$name)),(Join-Path $runtime $name)) }
# An isolated fixture worker exercises the REAL copied controller's transaction.
# No fault hook exists in shipped runtime. No Excel/application is started here.
$fixtureWorker=@'
param([string]$JobPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
$job=Get-Content -LiteralPath $JobPath -Raw -Encoding UTF8 | ConvertFrom-Json
$config=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixture-config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
[IO.File]::WriteAllText([string]$job.temp,'synthetic validated output')
if($config.case -eq 'InterruptedWorker') { exit 17 }
$hash=Get-Sha $job.temp
if($config.case -eq 'TamperedOutput') { [IO.File]::WriteAllText([string]$job.temp,'tampered output') }
if($config.case -eq 'TamperedSnapshot') { [IO.File]::WriteAllText([string]$job.input,'tampered snapshot') }
if($config.case -eq 'ExternalSourceReplace') {
 $external=[string]$config.source+'.new'
 [IO.File]::WriteAllText($external,'external newer source')
 [IO.File]::Replace($external,[string]$config.source,([string]$config.source+'.external-prior'))
}
if($config.case -eq 'CancelAfterValidation') { [IO.File]::WriteAllText((Join-Path ([IO.Path]::GetDirectoryName($JobPath)) 'cancel'),'cancel') }
Write-Json @{status='Validated';category='Validated';stage='Verify';hresults='';message='';tempHash=$hash} ([string]$job.result)
'@
[IO.File]::WriteAllText((Join-Path $runtime 'ExcelPassword.Worker.ps1'),$fixtureWorker,(New-Object Text.UTF8Encoding($true)))
$records=New-Object 'System.Collections.Generic.List[object]'
$secure=ConvertTo-SecureString 'Test-42!' -AsPlainText -Force
try { $cipher=ConvertFrom-SecureString $secure } finally { $secure.Dispose() }
foreach($case in @('InterruptedWorker','TamperedOutput','TamperedSnapshot','ExternalSourceReplace','CancelAfterValidation','SuccessfulTransaction')) {
    $source=Join-Path $EvidenceDirectory ($case+'.xlsx')
    [IO.File]::WriteAllText($source,'original synthetic source')
    $before=Get-Sha $source
    $run=Join-Path $EvidenceDirectory ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($run); Set-PrivateDirectory $run
    $request=Join-Path $run 'request.json'
    Write-Json @{case=$case;source=$source} (Join-Path $runtime 'fixture-config.json')
    Write-Json @{schemaVersion=1;path=$source;mode='Encrypt';oldSecret='';newSecret=$cipher;expectedHash=$before} $request
    $script=Join-Path $runtime 'Engine.ps1'
    $p=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+$script+'" -RequestPath "'+$request+'"') -PassThru -WindowStyle Hidden
    try { if(-not $p.WaitForExit(15000)) { $p.Kill(); throw 'Fixture controller timed out.' } } finally { $p.Dispose() }
    $result=Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected=switch($case) {
        'InterruptedWorker' {'WorkerCrashed'}
        'TamperedOutput' {'TempChanged'}
        'TamperedSnapshot' {'SnapshotChanged'}
        'ExternalSourceReplace' {'SourceChanged'}
        'CancelAfterValidation' {'Cancelled'}
        'SuccessfulTransaction' {'ReplacedAndVerified'}
    }
    $passed=$result.category -eq $expected -and (Get-Sha $result.backup) -eq $before -and -not [IO.File]::Exists($request) -and -not [IO.File]::Exists((Join-Path $run 'worker-job.json'))
    if($case -eq 'SuccessfulTransaction') {
        $passed=$passed -and $result.status -eq 'Success' -and $result.recoveryRemoved -and -not [IO.File]::Exists($result.recovery) -and [IO.File]::ReadAllText($source) -eq 'synthetic validated output'
    } elseif($case -eq 'ExternalSourceReplace') {
        $passed=$passed -and [IO.File]::ReadAllText($source) -eq 'external newer source'
    } else { $passed=$passed -and (Get-Sha $source) -eq $before }
    if($case -eq 'InterruptedWorker') { $passed=$passed -and [IO.File]::Exists($result.temp) -and [IO.File]::Exists($result.inputCopy) }
    $records.Add([pscustomobject]@{case=$case;passed=$passed;category=$result.category;expected=$expected;run=$run})
    Write-Json @{status=$(if($passed){'PASS'}else{'FAIL'});count=$records.Count;results=$records.ToArray();excelCom='NOT RUN (isolated fixture worker)'} (Join-Path $EvidenceDirectory 'controller-results.json')
    if(-not $passed) { throw ('Fault test failed: '+$case+' actual='+$result.category+' '+$run) }
}
Write-Output "PASS: $($records.Count) controller fault/transaction cases; $EvidenceDirectory"
