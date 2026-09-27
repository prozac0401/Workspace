[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$FailedReport,
    [Parameter(Mandatory=$true)][string]$InstalledMsiPath,
    [Parameter(Mandatory=$true)][string]$MsiPath,
    [Parameter(Mandatory=$true)][string]$RollbackMsiPath,
    [Parameter(Mandatory=$true)][string]$PreviousMetadata,
    [ValidateSet('Inspect','Run')][string]$Action='Inspect',
    [switch]$RequestElevation,
    [switch]$Elevated,
    [string]$FrozenPlanPath='',
    [string]$ExpectedPlanHash='',
    [string]$ExpectedRecoveryHash=''
)
# Narrow recovery for a failed, test-owned preservation-suite installation.
# Inspect never changes installed products or registry. Run obtains one normal
# UAC approval, removes only the exact failed fixture through its original MSI,
# runs the rebuilt package's full isolated suite, then installs the final MSI.
# There is no direct registry/file cleanup and no retry after any failed step.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$utf8=New-Object Text.UTF8Encoding($false)
function Hash([string]$Path) {return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
function Plain-Path([string]$Path,[string]$Boundary) {
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    $boundary=[IO.Path]::GetFullPath($Boundary).TrimEnd('\')
    if($full -ne $boundary -and -not $full.StartsWith(($boundary+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Recovery path escaped its exact boundary.'}
    $part=$full
    while($part){
        $attrs=$null
        try{$attrs=[IO.File]::GetAttributes($part)}catch [IO.FileNotFoundException]{}catch [IO.DirectoryNotFoundException]{}
        if($null -ne $attrs -and ($attrs -band [IO.FileAttributes]::ReparsePoint)){throw 'Recovery does not accept reparse paths.'}
        $part=[IO.Path]::GetDirectoryName($part)
    }
    return $full
}
function Artifact([string]$Path,[string]$RelativeBoundary){return Plain-Path $Path (Join-Path $root $RelativeBoundary)}
$recoveryHash=Hash $PSCommandPath
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$admin=(New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($Elevated){
    if($Action -ne 'Run' -or $RequestElevation -or -not $admin -or $ExpectedPlanHash -notmatch '^[A-Fa-f0-9]{64}$' -or $ExpectedRecoveryHash -ne $recoveryHash){throw 'Invalid or changed elevated recovery request.'}
    $FrozenPlanPath=Artifact $FrozenPlanPath 'artifacts/image-copy-save/msi-preservation-recovery'
    if((Hash $FrozenPlanPath) -ne $ExpectedPlanHash){throw 'Approved recovery plan changed before elevation.'}
    $frozen=Get-Content -LiteralPath $FrozenPlanPath -Raw -Encoding UTF8|ConvertFrom-Json
    if($frozen.schema -ne 1 -or $frozen.action -ne 'Run' -or $frozen.recoverySha256 -ne $recoveryHash -or $frozen.initiatingUserSid -ne $identity.User.Value){throw 'Recovery plan or initiating user differs from approval.'}
    if($FailedReport -ne $frozen.failedReport -or $InstalledMsiPath -ne $frozen.installedMsi -or $MsiPath -ne $frozen.msi -or $RollbackMsiPath -ne $frozen.rollbackMsi -or $PreviousMetadata -ne $frozen.previousMetadata){throw 'Elevated recovery arguments differ from approval.'}
    foreach($source in $frozen.sources){$path=Artifact (Join-Path $root $source.path) 'tools/ImageCopySave/installer';if((Hash $path) -ne $source.sha256){throw 'Approved recovery script changed before elevation.'}}
}elseif($FrozenPlanPath -or $ExpectedPlanHash -or $ExpectedRecoveryHash){throw 'Internal elevation arguments cannot be supplied to normal entry.'}
$FailedReport=Artifact $FailedReport 'artifacts/image-copy-save/msi-preservation'
if([IO.Path]::GetFileName($FailedReport) -ne 'result.json'){throw 'Expected an original preservation-suite result.json.'}
$failure=Get-Content -LiteralPath $FailedReport -Raw -Encoding UTF8|ConvertFrom-Json
$failureHash=Hash $FailedReport
$failedDirectory=[IO.Path]::GetDirectoryName($FailedReport)
if([IO.Path]::GetDirectoryName($failedDirectory) -ne (Join-Path $root 'artifacts/image-copy-save/msi-preservation')){throw 'Failed report is not in a direct unique suite directory.'}
if($failure.action -ne 'Suite' -or $failure.status -ne 'FAIL' -or -not $failure.elevated -or $failure.initiatingUserSid -ne $identity.User.Value -or $failure.cleanup -ne 'STOPPED_FOR_REVIEW_NO_AUTOMATIC_PRODUCT_REMOVAL'){throw "Report does not identify this user's stopped elevated test suite."}
$fixtureFolder=Plain-Path $failure.installFolder $failedDirectory
if($fixtureFolder -ne (Join-Path $failedDirectory 'installed-product')){throw 'Report installation path is not the exact test fixture folder.'}
$legacyPinPath=Join-Path $PSScriptRoot 'baselines/0.1.1.json'
$legacyPin=Get-Content -LiteralPath $legacyPinPath -Raw -Encoding UTF8|ConvertFrom-Json
$verifier=Join-Path $PSScriptRoot 'verify-msi.ps1'
function Read-Build([string]$Path,[bool]$IsRollback,[bool]$Legacy=$false){
    $path=Artifact $Path 'artifacts/image-copy-save/msi'
    $metadataPath=Artifact (Join-Path ([IO.Path]::GetDirectoryName($path)) 'build-metadata.json') 'artifacts/image-copy-save/msi'
    $meta=Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8|ConvertFrom-Json
    $hash=Hash $path
    if($meta.status -ne 'PASS' -or [bool]$meta.rollbackTest -ne $IsRollback -or $hash -ne $meta.msiSha256 -or $meta.upgradeCode -ne '{78C90F77-8CC3-4B10-BA9A-00E84ADAF375}'){throw 'Artifact identity, kind or hash differs from verified metadata.'}
    if($Legacy){
        if($meta.version -ne '0.1.1' -or $meta.productCode -ne $legacyPin.productCode -or $hash -ne $legacyPin.msiSha256 -or @($meta.files).Count -ne @($legacyPin.files).Count){throw 'Previous package is not the audited legacy 0.1.1.'}
        $expected=@{};foreach($file in $legacyPin.files){$expected[$file.path]=$file.sha256}
        foreach($file in $meta.files){if(-not $expected.ContainsKey($file.path) -or $expected[$file.path] -ne $file.sha256){throw 'Legacy file inventory differs.'};$expected.Remove($file.path)}
        if($expected.Count){throw 'Legacy inventory is incomplete.'}
    }else{
        $verified=(& $verifier -MsiPath $path -AllowRollbackTest:$IsRollback)|ConvertFrom-Json
        if($verified.status -ne 'PASS'){throw 'Package structural verification did not pass.'}
    }
    return [pscustomobject]@{path=$path;metadata=$meta;metadataPath=$metadataPath;sha256=$hash;metadataSha256=(Hash $metadataPath)}
}
$InstalledMsiPath=Artifact $InstalledMsiPath 'artifacts/image-copy-save/msi'
$MsiPath=Artifact $MsiPath 'artifacts/image-copy-save/msi'
$RollbackMsiPath=Artifact $RollbackMsiPath 'artifacts/image-copy-save/msi'
$PreviousMetadata=Artifact $PreviousMetadata 'artifacts/image-copy-save/msi'
if([IO.Path]::GetFileName($PreviousMetadata) -ne 'build-metadata.json'){throw 'PreviousMetadata must be the original build metadata.'}
$previousMeta=Get-Content -LiteralPath $PreviousMetadata -Raw -Encoding UTF8|ConvertFrom-Json
$installed=Read-Build $InstalledMsiPath $false
$product=Read-Build $MsiPath $false
$rollback=Read-Build $RollbackMsiPath $true
$previous=Read-Build $previousMeta.msi $false $true
if($failure.msi -ne $installed.path -or $failure.msiSha256 -ne $installed.sha256 -or $previous.metadataPath -ne $PreviousMetadata){throw 'Recovery input differs from the stopped test or audited legacy artifact.'}
if($product.sha256 -eq $installed.sha256 -or [Version]$product.metadata.version -lt [Version]$installed.metadata.version -or [Version]$rollback.metadata.version -le [Version]$product.metadata.version -or $rollback.metadata.productCode -eq $product.metadata.productCode){throw 'Recovery requires a rebuilt final MSI and a distinct higher-version rollback MSI.'}
if(@($failure.installedProductsAfter).Count -ne 1 -or $failure.installedProductsAfter[0].key -ne $installed.metadata.productCode -or $failure.installedProductsAfter[0].version -ne $installed.metadata.version -or [IO.Path]::GetFullPath($failure.installedProductsAfter[0].location).TrimEnd('\') -ne $fixtureFolder){throw 'Failed suite did not identify exactly this fixture product.'}
$sourcePaths=@('tools/ImageCopySave/installer/invoke-msi-preservation-recovery.ps1','tools/ImageCopySave/installer/test-msi-lifecycle.ps1','tools/ImageCopySave/installer/test-msi-preservation.ps1','tools/ImageCopySave/installer/verify-msi.ps1','tools/ImageCopySave/installer/preservation-tests/NativeStream.cs','tools/ImageCopySave/installer/baselines/0.1.1.json')
$sources=@($sourcePaths|ForEach-Object{[ordered]@{path=$_;sha256=(Hash (Join-Path $root $_))}})
$artifacts=@($installed,$product,$rollback,$previous|ForEach-Object{[ordered]@{path=$_.path;sha256=$_.sha256;metadataPath=$_.metadataPath;metadataSha256=$_.metadataSha256}})
function Assert-FrozenInputs {
    $expectedSources=$(if($Elevated){$frozen.sources}else{$sources})
    $expectedArtifacts=$(if($Elevated){$frozen.artifacts}else{$artifacts})
    if((Hash $FailedReport) -ne $failureHash -or ($Elevated -and $failureHash -ne $frozen.failedReportSha256)){throw 'Failed-suite evidence changed; recovery stopped.'}
    foreach($source in $expectedSources){if((Hash (Join-Path $root $source.path)) -ne $source.sha256){throw 'Approved recovery dependency changed; next operation was not launched.'}}
    foreach($artifact in $expectedArtifacts){if((Hash $artifact.path) -ne $artifact.sha256 -or (Hash $artifact.metadataPath) -ne $artifact.metadataSha256){throw 'Approved package or metadata changed; next operation was not launched.'}}
}
if($Elevated){Assert-FrozenInputs;$output=Artifact ([IO.Path]::GetDirectoryName($FrozenPlanPath)) 'artifacts/image-copy-save/msi-preservation-recovery'}
else{$output=Artifact (Join-Path $root ('artifacts/image-copy-save/msi-preservation-recovery/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[Guid]::NewGuid().ToString('N'))) 'artifacts/image-copy-save/msi-preservation-recovery';[IO.Directory]::CreateDirectory($output)|Out-Null}
$machine=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
$user=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
$save='{9C030D44-BBFA-48B7-BD63-53470C112830}';$copy='{B481F5D0-A2B3-47D7-A139-B6C2F60B36DE}'
$registryRoots=@("Software\Classes\CLSID\$save","Software\Classes\CLSID\$copy",'Software\Classes\Directory\Background\shell\Workspace.ImageCopySave.Save')+@('png','jpg','jpeg','bmp'|ForEach-Object{'Software\Classes\SystemFileAssociations\.'+$_+'\shell\Workspace.ImageCopySave.Copy'})
function Registry-Snapshot([Microsoft.Win32.RegistryKey]$Base,[string]$Path){
    $key=$Base.OpenSubKey($Path)
    if($null -eq $key){return '<absent>'}
    try{$values=@($key.GetValueNames()|Sort-Object|ForEach-Object{$name=$_;[ordered]@{name=$name;kind=[string]$key.GetValueKind($name);value=$key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}});return ([ordered]@{values=$values;subkeys=@($key.GetSubKeyNames()|Sort-Object)}|ConvertTo-Json -Depth 8 -Compress)}finally{$key.Dispose()}
}
function Associations {
    $rows=@();foreach($base in @($machine,$user)){foreach($ext in @('png','jpg','jpeg','bmp')){foreach($path in @("Software\Classes\.$ext","Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.$ext\UserChoice")){$rows+=(Registry-Snapshot $base $path)}}}
    return ($rows|ConvertTo-Json -Depth 10 -Compress)
}
function Existing-Products {
    $rows=@();foreach($base in @($machine,$user)){$key=$base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall');if($null -eq $key){continue};try{foreach($name in $key.GetSubKeyNames()){$p=$key.OpenSubKey($name);try{if($p -and $p.GetValue('DisplayName') -eq 'ImageCopySave'){$rows+=[ordered]@{code=$name;version=$p.GetValue('DisplayVersion');folder=$p.GetValue('InstallLocation')}}}finally{if($p){$p.Dispose()}}}}finally{$key.Dispose()}}
    return ,$rows
}
$installer=New-Object -ComObject WindowsInstaller.Installer
$database=$installer.OpenDatabase($installed.path,0)
function Query([string]$Sql,[int]$Columns){$view=$database.OpenView($Sql);try{[void]$view.Execute();$rows=@();while($record=$view.Fetch()){$row=@();for($i=1;$i -le $Columns;$i++){$row+=$record.StringData($i)};$rows+=,$row};return ,$rows}finally{[void]$view.Close()}}
$expectedRegistry=@{}

foreach($row in (Query 'SELECT `Root`, `Key`, `Name`, `Value` FROM `Registry`' 4)){
    if($row[0] -ne '2' -or $row[2] -in @('+','-','*')){throw 'Recovery accepts only exact authored HKLM values.'}
    $path=$row[1];$name=$row[2];$value=$row[3].Replace('[INSTALLFOLDER]',$fixtureFolder+'\')
    if($value.Contains('[') -or $value.StartsWith('#')){throw 'Unexpected formatted registry value in fixture package.'}
    if(-not $expectedRegistry.ContainsKey($path)){$expectedRegistry[$path]=@{}}
    if($expectedRegistry[$path].ContainsKey($name)){throw 'Duplicate authored registry value.'}
    $expectedRegistry[$path][$name]=$value
}
if(@($expectedRegistry.Keys).Count -ne 7 -or @($expectedRegistry.Values|ForEach-Object{$_.Keys}).Count -ne 23){throw 'Expected exactly seven authored keys and twenty-three values.'}
$expectedKeys=@{};foreach($path in $expectedRegistry.Keys){$expectedKeys[$path]=$true};foreach($path in $registryRoots){$expectedKeys[$path]=$true}
function Assert-RegistryTree([string]$Path){
    if(-not $expectedKeys.ContainsKey($Path)){throw 'Unknown registry child exists; recovery did not change it.'}
    $key=$machine.OpenSubKey($Path)
    if($null -eq $key){throw 'Fixture registry key is missing; exact recovery preflight failed.'}
    try{
        $expected=$(if($expectedRegistry.ContainsKey($Path)){$expectedRegistry[$Path]}else{@{}})
        if($key.ValueCount -ne $expected.Count){throw 'Registry has missing or unknown values; recovery did not adopt it.'}
        foreach($name in $key.GetValueNames()){if(-not $expected.ContainsKey($name) -or $key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::String -or $key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -ne $expected[$name]){throw 'An installed registry value differs; recovery stopped.'}}
        $children=@($key.GetSubKeyNames())
    }finally{$key.Dispose()}
    foreach($name in $children){Assert-RegistryTree ($Path+'\'+$name)}
}
$expectedFiles=@{};$expectedDirectories=@{}
foreach($entry in $installed.metadata.files){
    $path=Plain-Path (Join-Path $fixtureFolder $entry.path) $fixtureFolder
    if($path -eq $fixtureFolder -or $expectedFiles.ContainsKey($path)){throw 'Invalid or duplicate owned file path.'}
    $expectedFiles[$path]=$entry.sha256
    $directory=[IO.Path]::GetDirectoryName($path)
    while($directory -and $directory.StartsWith($fixtureFolder,[StringComparison]::OrdinalIgnoreCase)){$expectedDirectories[$directory]=$true;if($directory -eq $fixtureFolder){break};$directory=[IO.Path]::GetDirectoryName($directory)}
}
function Assert-DirectoryInventory([string]$Directory){
    [void](Plain-Path $Directory $fixtureFolder)
    if(-not $expectedDirectories.ContainsKey($Directory)){throw 'Unknown directory exists in the fixture; recovery preserved it.'}
    foreach($path in [IO.Directory]::EnumerateFileSystemEntries($Directory)){
        [void](Plain-Path $path $fixtureFolder)
        $attrs=[IO.File]::GetAttributes($path)
        if($attrs -band [IO.FileAttributes]::Directory){Assert-DirectoryInventory $path}
        elseif(-not $expectedFiles.ContainsKey($path)){throw 'Unknown file exists in the fixture; recovery preserved it.'}
    }
}
function Assert-ExactFixture {
    Assert-FrozenInputs
    $products=Existing-Products
    if($products.Count -ne 1 -or $products[0].code -ne $installed.metadata.productCode -or $products[0].version -ne $installed.metadata.version -or [IO.Path]::GetFullPath($products[0].folder).TrimEnd('\') -ne $fixtureFolder){throw 'Installed product identity/location differs from the failed test fixture.'}
    $default=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Workspace/ImageCopySave'
    if(Test-Path -LiteralPath $default){throw 'A default installation directory appeared; recovery will not adopt it.'}
    foreach($path in $registryRoots){if((Registry-Snapshot $user $path) -ne '<absent>'){throw 'A current-user product registration remains; recovery preserved it for review.'};Assert-RegistryTree $path}
    Assert-DirectoryInventory $fixtureFolder
    foreach($path in $expectedFiles.Keys){
        [void](Plain-Path $path $fixtureFolder)
        if(-not [IO.File]::Exists($path) -or (Hash $path) -ne $expectedFiles[$path]){throw 'A fixture-owned file is missing or externally changed.'}
        if(@(Get-Item -LiteralPath $path -Stream *|Where-Object{$_.Stream -ne ':$DATA'}).Count){throw 'A fixture-owned file has an external named stream; recovery preserved it.'}
    }
    return [ordered]@{productCode=$installed.metadata.productCode;version=$installed.metadata.version;directory=$fixtureFolder;verifiedFiles=$expectedFiles.Count;verifiedRegistryValues=23;unknownFiles=0;unknownRegistryValues=0;currentUserCollisions=0;namedStreams=0;reparsePaths=0}
}
function Assert-FixtureRemoved {
    $remaining=Existing-Products
    if($remaining.Count){throw 'A product remains installed; later recovery steps were not run.'}
    foreach($path in $expectedFiles.Keys){if(Test-Path -LiteralPath $path){throw 'Owned fixture file remains after MSI removal.'}}
    foreach($base in @($machine,$user)){foreach($path in $registryRoots){if((Registry-Snapshot $base $path) -ne '<absent>'){throw 'Product registry root remains after removal; no direct cleanup was attempted.'}}}
    if((Associations) -ne $script:associationsBefore){throw 'Image associations changed; they were preserved without automatic reset.'}
}
Add-Type -AssemblyName System.Web.Extensions
$jsonReader=New-Object System.Web.Script.Serialization.JavaScriptSerializer
$jsonReader.MaxJsonLength=16777216
$steps=New-Object 'System.Collections.Generic.List[object]'
$reportPath=Join-Path $output $(if($Elevated){'recovery.json'}else{'inspection.json'})
$report=[ordered]@{schema=1;status='RUNNING';action=$Action;elevated=[bool]$Elevated;startedUtc=[DateTime]::UtcNow.ToString('o');failedReport=$FailedReport;failedReportSha256=$failureHash;installedMsi=$installed.path;installedMsiSha256=$installed.sha256;fixtureFolder=$fixtureFolder;msi=$MsiPath;msiSha256=$product.sha256;rollbackMsi=$RollbackMsiPath;previousMetadata=$PreviousMetadata;steps=@();stoppedAfter=$null;explorerRestarted=$false;unknownChangesDeleted=$false;finalInstallAttempted=$false}
function Write-Report{$report.steps=@($steps.ToArray());[IO.File]::WriteAllText($reportPath,($report|ConvertTo-Json -Depth 15),$utf8)}
function Run-Step([string]$Name,[string]$Script,[hashtable]$Arguments,[string]$Prefix,[string]$ResultBoundary){
    Assert-FrozenInputs
    $start=[DateTime]::UtcNow
    $entry=[ordered]@{name=$Name;status='RUNNING';startedUtc=$start.ToString('o');script=[IO.Path]::GetFileName($Script);requestedAction=$Arguments.Action;resultPath=$null;error=$null}
    $steps.Add($entry);$report.stoppedAfter=$Name;Write-Report
    $lines=New-Object 'System.Collections.Generic.List[string]';$errorText=$null
    try{& $Script @Arguments 2>&1|ForEach-Object{$lines.Add([string]$_)}}catch{$errorText=$_.Exception.Message;$lines.Add($errorText)}
    $log=Join-Path $output ($Name+'.log');[IO.File]::WriteAllLines($log,$lines,$utf8)
    $matches=@($lines|Where-Object{$_.StartsWith($Prefix)})
    if($matches.Count -ne 1){$entry.status='FAIL';$entry.error=$errorText;Write-Report;throw "$Name did not return exactly one result; no next operation was launched. $errorText"}
    $resultPath=Artifact $matches[0].Substring($Prefix.Length) $ResultBoundary
    $data=$jsonReader.DeserializeObject([IO.File]::ReadAllText($resultPath,[Text.Encoding]::UTF8))
    $entry.resultPath=$resultPath;$entry.status=$data['status'];$entry.error=$errorText;$entry.finishedUtc=[DateTime]::UtcNow.ToString('o');Write-Report
    if($errorText -or $data['status'] -ne 'PASS' -or $data['action'] -ne $Arguments.Action -or $data['msiSha256'] -ne $product.sha256 -or ([DateTimeOffset]::Parse($data['startedUtc'])).UtcDateTime -lt $start.AddSeconds(-1) -or $data['rebootRequired']){throw "$Name did not return a current complete PASS; later operations were not run. $errorText"}
    if((Associations) -ne $script:associationsBefore){throw 'Image associations changed during recovery verification; no automatic reset was performed.'}
    return $data
}
function Preservation([string]$Operation,[string]$Name){return Run-Step $Name (Join-Path $PSScriptRoot 'test-msi-preservation.ps1') @{MsiPath=$MsiPath;Action=$Operation;PreviousMsiPath=$previous.path;RollbackMsiPath=$RollbackMsiPath} 'Preservation result: ' 'artifacts/image-copy-save/msi-preservation'}
function Remove-ExactFixture {
    $inspection=Assert-ExactFixture
    $entry=[ordered]@{name='remove-exact-failed-fixture';status='RUNNING';startedUtc=[DateTime]::UtcNow.ToString('o');msiSha256=$installed.sha256;inspection=$inspection;exitCode=$null;log='fixture-remove.msiexec.log'}
    $steps.Add($entry);$report.stoppedAfter=$entry.name;Write-Report
    $log=Join-Path $output $entry.log
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=Join-Path $env:windir 'System32/msiexec.exe';$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.Arguments='/x "'+$installed.path+'" /qn /norestart REBOOT=ReallySuppress MSIRESTARTMANAGERCONTROL=Disable INSTALLFOLDER="'+$fixtureFolder+'" /l*v "'+$log+'"'
    $process=[Diagnostics.Process]::Start($info)
    try{$process.WaitForExit();$entry.exitCode=$process.ExitCode}finally{$process.Dispose()}
    $text=Get-Content -LiteralPath $log -Raw
    if($entry.exitCode -ne 0 -or $text -notmatch 'ImageCopySave ownership guard: PASS \(preflight\)' -or $text -notmatch 'ImageCopySave ownership guard: PASS \(deferred recheck\)'){$entry.status='FAIL';Write-Report;throw 'Exact fixture removal did not complete with both ownership checks; recovery stopped.'}
    Assert-FixtureRemoved
    $entry.status='PASS';$entry.finishedUtc=[DateTime]::UtcNow.ToString('o');$entry.fixtureDirectoryStillExists=[IO.Directory]::Exists($fixtureFolder);Write-Report
}
Write-Report
try{
    $script:associationsBefore=Associations
    $inspection=Assert-ExactFixture
    $report.fixtureInspection=$inspection
    if(-not $Elevated){
        $report.plannedSequence=@('Remove only the exact failed suite installation with its original MSI','Inspect clean installation state','Run the full rebuilt MSI preservation suite including legacy upgrade and rollback','Install the final rebuilt MSI at the default location')
        $report.status='PASS';Write-Report
        if($Action -eq 'Inspect'){return}
        if(-not $RequestElevation){throw 'Run requires -RequestElevation for one normal administrator approval. Inspect completed without changing installation.'}
        Assert-FrozenInputs
        $plan=[ordered]@{schema=1;action='Run';createdUtc=[DateTime]::UtcNow.ToString('o');initiatingUserSid=$identity.User.Value;recoverySha256=$recoveryHash;failedReport=$FailedReport;failedReportSha256=$failureHash;installedMsi=$InstalledMsiPath;msi=$MsiPath;rollbackMsi=$RollbackMsiPath;previousMetadata=$PreviousMetadata;sources=$sources;artifacts=$artifacts;associations=$script:associationsBefore;fixtureInspection=$inspection;sequence=$report.plannedSequence}
        $FrozenPlanPath=Join-Path $output 'approved-plan.json';[IO.File]::WriteAllText($FrozenPlanPath,($plan|ConvertTo-Json -Depth 12),$utf8);$planHash=Hash $FrozenPlanPath
        $launchPath=Join-Path $output 'launch.json';$launch=[ordered]@{status='REQUESTING_UAC';requestedUtc=[DateTime]::UtcNow.ToString('o');approvedPlan=$FrozenPlanPath;approvedPlanSha256=$planHash;processId=$null;exitCode=$null}
        [IO.File]::WriteAllText($launchPath,($launch|ConvertTo-Json -Depth 6),$utf8)
        $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,'-FailedReport',$FailedReport,'-InstalledMsiPath',$InstalledMsiPath,'-MsiPath',$MsiPath,'-RollbackMsiPath',$RollbackMsiPath,'-PreviousMetadata',$PreviousMetadata,'-Action','Run','-Elevated','-FrozenPlanPath',$FrozenPlanPath,'-ExpectedPlanHash',$planHash,'-ExpectedRecoveryHash',$recoveryHash)
        $quoted=@($arguments|ForEach-Object{if($_.Contains('"') -or $_ -match '[\r\n]' -or $_.EndsWith('\')){throw 'Ambiguous elevation argument.'};'"'+$_+'"'}) -join ' '
        $child=$null
        try{
            $child=Start-Process -FilePath (Join-Path $env:windir 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $quoted -Verb RunAs -WindowStyle Hidden -PassThru
            $launch.status='RUNNING';$launch.processId=$child.Id;[IO.File]::WriteAllText($launchPath,($launch|ConvertTo-Json -Depth 6),$utf8)
            $child.WaitForExit();$launch.exitCode=$child.ExitCode;$launch.status=$(if($child.ExitCode -eq 0){'COMPLETED'}else{'CHILD_FAILED_OR_BLOCKED'})
            if($child.ExitCode -ne 0){throw 'Elevated recovery stopped; review recovery.json before any further action.'}
        }catch{if($null -eq $child){$launch.status='ELEVATION_NOT_STARTED'};$launch.error=$_.Exception.Message;throw}
        finally{$launch.finishedUtc=[DateTime]::UtcNow.ToString('o');[IO.File]::WriteAllText($launchPath,($launch|ConvertTo-Json -Depth 6),$utf8);if($child){$child.Dispose()};Write-Output "Preservation recovery launch: $launchPath"}
        return
    }
    if($script:associationsBefore -ne $frozen.associations){throw 'Image associations changed during approval; recovery preserved the new state and stopped.'}
    Remove-ExactFixture
    $clean=Preservation 'Inspect' 'clean-inspect-after-fixture-removal'
    if(-not $clean['preflight']['canRunSuite']){throw 'Unknown state remains after fixture removal; no suite was attempted.'}
    $suite=Preservation 'Suite' 'rebuilt-preservation-suite'
    if(@($suite['installedProductsAfter']).Count -ne 0 -or @($suite['tests']|Where-Object{$_['status'] -ne 'PASS'}).Count){throw 'Rebuilt suite did not fully pass with its fixture removed.'}
    $clean=Preservation 'Inspect' 'clean-inspect-before-final-install'
    if(-not $clean['preflight']['canRunSuite']){throw 'The suite left unknown state; final installation was not attempted.'}
    $report.finalInstallAttempted=$true;Write-Report
    $final=Run-Step 'final-default-install' (Join-Path $PSScriptRoot 'test-msi-lifecycle.ps1') @{MsiPath=$MsiPath;Action='Install'} 'Lifecycle result: ' 'artifacts/image-copy-save/msi-lifecycle'
    if($final['productCode'] -ne $product.metadata.productCode -or $final['exitCode'] -ne 0 -or -not $final['installedAfter']){throw 'Final installation identity or result differs.'}
    $report.status='PASS';$report.finalState='Rebuilt final MSI installed at default location after full preservation suite; no pending reboot'
}catch{$report.status='STOPPED';$report.error=$_.Exception.Message;$report.recovery='No automatic removal, reinstall, direct registry cleanup, or file deletion was attempted after failure.';throw}
finally{$report.finishedUtc=[DateTime]::UtcNow.ToString('o');Write-Report;$machine.Dispose();$user.Dispose();Write-Output "Preservation recovery result: $reportPath"}
