#requires -Version 5.1
#requires -PSEdition Desktop
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
$toolRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $toolRoot 'runtime/Common.ps1')
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count) { throw 'Wait until Excel tests finish.' }
if(Test-Path -LiteralPath $EvidenceDirectory) { throw 'Use a new evidence directory.' }
$EvidenceDirectory=[IO.Path]::GetFullPath($EvidenceDirectory)
[void][IO.Directory]::CreateDirectory($EvidenceDirectory)
$runtime=Join-Path $EvidenceDirectory 'isolated-runtime'
[void][IO.Directory]::CreateDirectory($runtime)
foreach($name in @('Engine.ps1','Common.ps1')) { [IO.File]::Copy((Join-Path $toolRoot ('runtime/'+$name)),(Join-Path $runtime $name)) }
# Fault injection is confined to this test copy. The shipped codec has no hooks.
$codec=@'
using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
namespace ExcelPasswordSafe.Crypto {
 public sealed class DirectCryptoResult {
  public bool Supported=true;
  public string Status="Validated",Category="Validated",Message="",TempHash="";
 }
 public static class DirectCrypto {
  public static DirectCryptoResult Operate(string input,string temp,string extension,string mode,string oldPassword,string newPassword) {
   string root=Path.GetDirectoryName(typeof(DirectCrypto).Assembly.Location);
   string[] config=File.ReadAllLines(Path.Combine(root,"fixture.txt"));
   string kind=config[0], source=config[1], run=config[2];
   var result=new DirectCryptoResult();
   if(kind=="Unsupported") { result.Supported=false; return result; }
   if(kind=="IntegrityRejected") { result.Status="Failed";result.Category="IntegrityCheckFailed";return result; }
   File.WriteAllText(temp,"synthetic validated output");
   using(var sha=SHA256.Create()) { result.TempHash=BitConverter.ToString(sha.ComputeHash(File.ReadAllBytes(temp))).Replace("-",""); }
   if(kind=="TamperedOutput") File.WriteAllText(temp,"changed after validation");
   if(kind=="TamperedSnapshot") File.WriteAllText(input,"changed snapshot");
   if(kind=="TamperedBackup") File.WriteAllText(Path.Combine(run,"original.xlsx"),"changed backup");
   if(kind=="ExternalSourceReplace") { File.WriteAllText(source+".new","external source"); File.Replace(source+".new",source,source+".prior"); }
   if(kind=="Cancelled") File.WriteAllText(Path.Combine(run,"cancel"),"cancel");
   if(kind=="SessionUnsafe") File.WriteAllText(Path.Combine(config[3],"unsafe.json"),"{}");
   if(kind=="OwnerExited") {
    // Only the test-created helper owns this marker. It exits voluntarily.
    File.WriteAllText(config[4],"stop");
    try { using(var owner=Process.GetProcessById(Int32.Parse(config[5]))) {
     if(!owner.WaitForExit(10000)) throw new InvalidOperationException("Fixture owner did not exit");
    } } catch(ArgumentException) { }
   }
   if(kind=="UnexpectedOutput") result.Supported=false;
   return result;
  }
 }
}
'@
Add-Type -TypeDefinition $codec -OutputAssembly (Join-Path $runtime 'ExcelPasswordSafe.Crypto.dll')
$worker=@'
param([string]$JobPath)
. (Join-Path $PSScriptRoot 'Common.ps1')
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'worker-used'),'used')
$job=Get-Content -LiteralPath $JobPath -Raw -Encoding UTF8 | ConvertFrom-Json
[IO.File]::WriteAllText([string]$job.temp,'synthetic validated output')
Write-Json @{status='Validated';category='Validated';hresults='';tempHash=(Get-Sha $job.temp)} ([string]$job.result)
'@
[IO.File]::WriteAllText((Join-Path $runtime 'ExcelPassword.Worker.ps1'),$worker,(New-Object Text.UTF8Encoding($true)))
$runner=@'
param([string]$Configuration)
$fixture=Get-Content -LiteralPath $Configuration -Raw -Encoding UTF8 | ConvertFrom-Json
if($fixture.case -in @('InertSessionSuccess','SessionUnsafe','OwnerExited')) {
 $session=@{directory=[string]$fixture.sessionDirectory;token=[guid]::NewGuid().ToString('N');sequence=0;process=$null;healthy=$false;excelPid=0;excelStartTicks='';userOwnerPid=[int]$fixture.ownerPid;userOwnerStart=[string]$fixture.ownerStartTicks}
 & (Join-Path $PSScriptRoot 'Engine.ps1') -RequestPath ([string]$fixture.request) -WorkerSession $session
} else { & (Join-Path $PSScriptRoot 'Engine.ps1') -RequestPath ([string]$fixture.request) }
'@
[IO.File]::WriteAllText((Join-Path $runtime 'fixture-runner.ps1'),$runner,(New-Object Text.UTF8Encoding($true)))
$ownerScript=@'
param([string]$StopPath)
$deadline=[DateTime]::UtcNow.AddSeconds(30)
while(-not [IO.File]::Exists($StopPath) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
'@
[IO.File]::WriteAllText((Join-Path $runtime 'fixture-owner.ps1'),$ownerScript,(New-Object Text.UTF8Encoding($true)))
$secure=ConvertTo-SecureString 'Fixture42!' -AsPlainText -Force
try { $cipher=ConvertFrom-SecureString $secure } finally { $secure.Dispose() }
$records=New-Object 'System.Collections.Generic.List[object]'
foreach($case in @('Success','IntegrityRejected','Unsupported','TamperedOutput','TamperedSnapshot','TamperedBackup','ExternalSourceReplace','Cancelled','UnexpectedOutput','InertSessionSuccess','SessionUnsafe','OwnerExited')) {
    $path=Join-Path $EvidenceDirectory ($case+'.xlsx')
    [IO.File]::WriteAllText($path,'synthetic original')
    $before=Get-Sha $path
    $run=Join-Path $EvidenceDirectory ([guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($run); Set-PrivateDirectory $run
    $sessionDirectory=Join-Path $run 'fixture-session'
    $ownerStop=Join-Path $run 'fixture-owner-stop'
    $owner=$null; $ownerId=0; $ownerStartTicks=''
    if($case -in @('InertSessionSuccess','SessionUnsafe','OwnerExited')) { [void][IO.Directory]::CreateDirectory($sessionDirectory) }
    if($case -eq 'OwnerExited') {
        $owner=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $runtime 'fixture-owner.ps1')+'" -StopPath "'+$ownerStop+'"') -PassThru -WindowStyle Hidden
        [void]$owner.Handle
        $ownerId=$owner.Id; $ownerStartTicks=$owner.StartTime.ToUniversalTime().Ticks.ToString()
    }
    [IO.File]::WriteAllLines((Join-Path $runtime 'fixture.txt'),@($case,$path,$run,$sessionDirectory,$ownerStop,[string]$ownerId))
    $marker=Join-Path $runtime 'worker-used'
    if([IO.File]::Exists($marker)) { [IO.File]::Delete($marker) }
    $request=Join-Path $run 'request.json'
    Write-Json @{schemaVersion=1;path=$path;mode='Encrypt';expectedHash=$before;oldSecret='';newSecret=$cipher} $request
    $configuration=Join-Path $run 'fixture-runner.json'
    Write-Json @{case=$case;request=$request;sessionDirectory=$sessionDirectory;ownerPid=$ownerId;ownerStartTicks=$ownerStartTicks} $configuration
    $process=Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "'+(Join-Path $runtime 'fixture-runner.ps1')+'" -Configuration "'+$configuration+'"') -PassThru -WindowStyle Hidden -RedirectStandardError (Join-Path $run 'stderr.log')
    [void]$process.Handle
    try { if(-not $process.WaitForExit(20000)) { $process.Kill(); throw 'Isolated fixture timeout.' } }
    finally {
        $process.Dispose()
        if($null -ne $owner) {
            try { [IO.File]::WriteAllText($ownerStop,'stop'); if(-not $owner.WaitForExit(10000)) { throw 'Test-created owner did not voluntarily exit.' } }
            finally { $owner.Dispose() }
        }
    }
    $r=Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected=switch($case) { 'Success' {'ReplacedAndVerified'} 'InertSessionSuccess' {'ReplacedAndVerified'} 'SessionUnsafe' {'WorkerSessionUnsafe'} 'OwnerExited' {'OwnerExited'} 'Unsupported' {'ReplacedAndVerified'} 'IntegrityRejected' {'IntegrityCheckFailed'} 'TamperedOutput' {'TempChanged'} 'TamperedSnapshot' {'SnapshotChanged'} 'TamperedBackup' {'BackupChanged'} 'ExternalSourceReplace' {'SourceChanged'} 'Cancelled' {'Cancelled'} 'UnexpectedOutput' {'WorkerFailed'} }
    $pass=$r.category -eq $expected -and ([IO.File]::Exists($marker) -eq ($case -eq 'Unsupported'))
    if($case -in @('Success','Unsupported','InertSessionSuccess')) { $pass=$pass -and $r.status -eq 'Success' -and (Get-Sha $path) -eq $r.resultHash -and (Get-Sha $r.backup) -eq $before }
    elseif($case -eq 'ExternalSourceReplace') { $pass=$pass -and [IO.File]::ReadAllText($path) -eq 'external source' }
    else { $pass=$pass -and (Get-Sha $path) -eq $before }
    $mustBeRemoved=@($request,(Join-Path $run 'worker-job.json'),$r.recovery)
    if($case -eq 'SessionUnsafe') {
        $pass=$pass -and $r.status -eq 'Failed' -and [IO.File]::Exists($r.temp) -and [IO.File]::Exists($r.inputCopy) -and (Get-Sha $r.inputCopy) -eq $before -and (Get-Sha $r.backup) -eq $before
    } else { $mustBeRemoved+=@($r.temp,$r.inputCopy) }
    if($case -eq 'OwnerExited') { $pass=$pass -and $r.status -eq 'Cancelled' -and (Get-Sha $r.backup) -eq $before }
    foreach($file in $mustBeRemoved) { if($file -and [IO.File]::Exists($file)) { $pass=$false } }
    $records.Add(@{case=$case;passed=$pass;category=$r.category;expected=$expected;backend=$r.backend;run=$run})
    Write-Json @{status=$(if($pass){'PASS'}else{'FAIL'});count=$records.Count;results=$records.ToArray();excel='NotRun: isolated codec and worker'} (Join-Path $EvidenceDirectory 'direct-controller-results.json')
    if(-not $pass) { throw ('Direct controller case failed: '+$case+' '+$r.category) }
}
Write-Output ('PASS: '+$records.Count+' direct controller cases; '+$EvidenceDirectory)
