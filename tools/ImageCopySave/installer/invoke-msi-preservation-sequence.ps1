[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MsiPath,
    [Parameter(Mandatory=$true)][string]$RollbackMsiPath,
    [Parameter(Mandatory=$true)][string]$PreviousMetadata,
    [ValidateSet('Inspect','Run')][string]$Action='Inspect',
    [switch]$RequestElevation,
    [switch]$Elevated,
    [string]$FrozenPlanPath='',
    [string]$ExpectedPlanHash='',
    [string]$ExpectedSequenceHash=''
)
# Authorized release-verification sequence. Default Inspect is read-only with
# respect to installed products/registry. Run requires an explicit normal UAC
# launch and never deletes unknown files or automatically recovers failed steps.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$utf8=New-Object Text.UTF8Encoding($false)
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Plain-Path([string]$Path,[string]$Subdirectory) {
    $full=[IO.Path]::GetFullPath($Path)
    $boundary=[IO.Path]::GetFullPath((Join-Path $root $Subdirectory)).TrimEnd('\')+'\'
    if (-not $full.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw 'Sequence path escaped its worktree boundary.' }
    $part=$full
    while ($part) {
        $attrs=$null
        try { $attrs=[IO.File]::GetAttributes($part) } catch [IO.FileNotFoundException] {} catch [IO.DirectoryNotFoundException] {}
        if ($null -ne $attrs -and ($attrs -band [IO.FileAttributes]::ReparsePoint)) { throw 'Sequence paths may not traverse reparse points.' }
        $part=[IO.Path]::GetDirectoryName($part)
    }
    return $full
}
$sequenceHash=Hash $PSCommandPath
if ($Elevated) {
    if ($Action -ne 'Run' -or $RequestElevation -or $ExpectedPlanHash -notmatch '^[A-Fa-f0-9]{64}$' -or $ExpectedSequenceHash -ne $sequenceHash) { throw 'Invalid or changed elevated sequence request.' }
    $FrozenPlanPath=Plain-Path $FrozenPlanPath 'artifacts/image-copy-save/msi-preservation-sequence'
    if ((Hash $FrozenPlanPath) -ne $ExpectedPlanHash) { throw 'Approved sequence inputs changed before elevation.' }
    $frozen=Get-Content -LiteralPath $FrozenPlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($frozen.schema -ne 1 -or $frozen.action -ne 'Run' -or $frozen.sequenceSha256 -ne $sequenceHash) { throw 'Invalid frozen sequence plan.' }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Normal Windows administrator approval is required.' }
    if ($identity.User.Value -ne $frozen.initiatingUserSid) { throw 'Elevation used another user account; the per-user collision checks would not have the approved context.' }
    if ($MsiPath -ne $frozen.msi -or $RollbackMsiPath -ne $frozen.rollbackMsi -or $PreviousMetadata -ne $frozen.previousMetadata) { throw 'Elevated arguments differ from the approved plan.' }
    # Validate every script before executing any script from the approved plan.
    foreach ($source in $frozen.sources) {
        $path=Plain-Path (Join-Path $root $source.path) 'tools/ImageCopySave/installer'
        if ((Hash $path) -ne $source.sha256) { throw "Sequence dependency changed: $($source.path)" }
    }
} elseif ($FrozenPlanPath -or $ExpectedPlanHash -or $ExpectedSequenceHash) { throw 'Internal elevation arguments are not accepted by the normal entry point.' }
$lifecycle=Join-Path $PSScriptRoot 'test-msi-lifecycle.ps1'
$preservation=Join-Path $PSScriptRoot 'test-msi-preservation.ps1'
$verifier=Join-Path $PSScriptRoot 'verify-msi.ps1'
$legacyPinPath=Join-Path $PSScriptRoot 'baselines/0.1.1.json'
$legacyPin=Get-Content -LiteralPath $legacyPinPath -Raw -Encoding UTF8 | ConvertFrom-Json
function Read-Build([string]$Path,[bool]$Rollback,[bool]$Legacy=$false) {
    $path=Plain-Path $Path 'artifacts/image-copy-save/msi'
    $metadataPath=Plain-Path (Join-Path ([IO.Path]::GetDirectoryName($path)) 'build-metadata.json') 'artifacts/image-copy-save/msi'
    $metadata=Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $hash=Hash $path
    if ($metadata.status -ne 'PASS' -or [bool]$metadata.rollbackTest -ne $Rollback -or $hash -ne $metadata.msiSha256 -or $metadata.upgradeCode -ne '{78C90F77-8CC3-4B10-BA9A-00E84ADAF375}') { throw 'Artifact identity, kind, or hash differs from the verified build.' }
    if ($Legacy) {
        if ($metadata.version -ne '0.1.1' -or $metadata.productCode -ne $legacyPin.productCode -or $hash -ne $legacyPin.msiSha256 -or @($metadata.files).Count -ne @($legacyPin.files).Count) { throw 'Previous MSI is not the audited legacy 0.1.1 package.' }
        $expected=@{}
        foreach ($file in $legacyPin.files) { $expected[$file.path]=$file.sha256 }
        foreach ($file in $metadata.files) { if (-not $expected.ContainsKey($file.path) -or $expected[$file.path] -ne $file.sha256) { throw 'Legacy metadata inventory differs from its audited pin.' }; $expected.Remove($file.path) }
        if ($expected.Count) { throw 'Legacy metadata inventory is incomplete.' }
    } else {
        $verification=(& $verifier -MsiPath $path -AllowRollbackTest:$Rollback) | ConvertFrom-Json
        if ($verification.status -ne 'PASS') { throw 'Package verification failed.' }
    }
    return [pscustomobject]@{ path=$path; metadata=$metadata; metadataPath=$metadataPath; sha256=$hash; metadataSha256=(Hash $metadataPath) }
}
$MsiPath=Plain-Path $MsiPath 'artifacts/image-copy-save/msi'
$RollbackMsiPath=Plain-Path $RollbackMsiPath 'artifacts/image-copy-save/msi'
$PreviousMetadata=Plain-Path $PreviousMetadata 'artifacts/image-copy-save/msi'
if ([IO.Path]::GetFileName($PreviousMetadata) -ne 'build-metadata.json') { throw 'PreviousMetadata must be the original build metadata file.' }
$oldMetadata=Get-Content -LiteralPath $PreviousMetadata -Raw -Encoding UTF8 | ConvertFrom-Json
$product=Read-Build $MsiPath $false
$rollback=Read-Build $RollbackMsiPath $true
$previous=Read-Build $oldMetadata.msi $false $true
if ($previous.metadataPath -ne $PreviousMetadata -or $product.metadata.version -ne '0.2.0' -or [Version]$rollback.metadata.version -le [Version]$product.metadata.version -or $rollback.metadata.productCode -eq $product.metadata.productCode) { throw 'This sequence requires audited legacy 0.1.1, final 0.2.0, and a distinct higher-version rollback package.' }
$sourcePaths=@(
    'tools/ImageCopySave/installer/invoke-msi-preservation-sequence.ps1',
    'tools/ImageCopySave/installer/test-msi-lifecycle.ps1',
    'tools/ImageCopySave/installer/test-msi-preservation.ps1',
    'tools/ImageCopySave/installer/verify-msi.ps1',
    'tools/ImageCopySave/installer/preservation-tests/NativeStream.cs',
    'tools/ImageCopySave/installer/baselines/0.1.1.json'
)
$sources=@($sourcePaths | ForEach-Object { [ordered]@{ path=$_; sha256=(Hash (Join-Path $root $_)) } })
$artifacts=@($product,$rollback,$previous | ForEach-Object {
    [ordered]@{ path=$_.path; sha256=$_.sha256; metadataPath=$_.metadataPath; metadataSha256=$_.metadataSha256 }
})
if ($Elevated) {
    foreach ($artifact in $frozen.artifacts) {
        if ((Hash $artifact.path) -ne $artifact.sha256 -or (Hash $artifact.metadataPath) -ne $artifact.metadataSha256) { throw 'Approved package or metadata changed during elevation.' }
    }
    $output=Plain-Path ([IO.Path]::GetDirectoryName($FrozenPlanPath)) 'artifacts/image-copy-save/msi-preservation-sequence'
} else {
    $output=Plain-Path (Join-Path $root ('artifacts/image-copy-save/msi-preservation-sequence/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[Guid]::NewGuid().ToString('N'))) 'artifacts/image-copy-save/msi-preservation-sequence'
    [IO.Directory]::CreateDirectory($output) | Out-Null
}
Add-Type -AssemblyName System.Web.Extensions
$jsonReader=New-Object System.Web.Script.Serialization.JavaScriptSerializer
$jsonReader.MaxJsonLength=16777216
$steps=New-Object 'System.Collections.Generic.List[object]'
$reportPath=Join-Path $output $(if ($Elevated) {'sequence.json'} else {'inspection.json'})
$report=[ordered]@{ schema=1; status='RUNNING'; action=$Action; elevated=[bool]$Elevated; startedUtc=[DateTime]::UtcNow.ToString('o'); msi=$MsiPath; msiSha256=$product.sha256; rollbackMsi=$RollbackMsiPath; previousMsi=$previous.path; previousMetadata=$PreviousMetadata; steps=@(); stoppedAfter=$null; explorerRestarted=$false; unknownChangesDeleted=$false; finalInstallAttempted=$false }
function Write-Report { $report.steps=@($steps.ToArray()); [IO.File]::WriteAllText($reportPath,($report | ConvertTo-Json -Depth 15),$utf8) }
function Assert-FrozenInputs {
    $expectedSources=$(if($Elevated){$frozen.sources}else{$sources})
    $expectedArtifacts=$(if($Elevated){$frozen.artifacts}else{$artifacts})
    foreach ($source in $expectedSources) { if ((Hash (Join-Path $root $source.path)) -ne $source.sha256) { throw 'An approved test script changed; no next operation was launched.' } }
    foreach ($artifact in $expectedArtifacts) { if ((Hash $artifact.path) -ne $artifact.sha256 -or (Hash $artifact.metadataPath) -ne $artifact.metadataSha256) { throw 'An approved artifact changed; no next operation was launched.' } }
}
function Run-Step([string]$Name,[string]$Script,[hashtable]$Arguments,[string]$Prefix,[string]$ResultSubdirectory) {
    Assert-FrozenInputs
    $start=[DateTime]::UtcNow
    $entry=[ordered]@{ name=$Name; status='RUNNING'; startedUtc=$start.ToString('o'); script=[IO.Path]::GetFileName($Script); requestedAction=$Arguments.Action; resultPath=$null; error=$null }
    $steps.Add($entry); $report.stoppedAfter=$Name; Write-Report
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $failure=$null
    try { & $Script @Arguments 2>&1 | ForEach-Object { $lines.Add([string]$_) } } catch { $failure=$_.Exception.Message; $lines.Add($failure) }
    $log=Join-Path $output ($Name+'.log')
    [IO.File]::WriteAllLines($log,$lines,$utf8)
    $matches=@($lines | Where-Object { $_.StartsWith($Prefix) })
    if ($matches.Count -ne 1) { $entry.status='FAIL'; $entry.error=$failure; Write-Report; throw "$Name did not produce exactly one verified result. See $log. $failure" }
    $resultPath=Plain-Path $matches[0].Substring($Prefix.Length) $ResultSubdirectory
    $result=$jsonReader.DeserializeObject([IO.File]::ReadAllText($resultPath,[Text.Encoding]::UTF8))
    $entry.resultPath=$resultPath; $entry.status=$result['status']; $entry.error=$failure; $entry.finishedUtc=[DateTime]::UtcNow.ToString('o')
    Write-Report
    if ($failure -or $result['status'] -ne 'PASS' -or $result['action'] -ne $Arguments.Action -or $result['msiSha256'] -ne $product.sha256 -or ([DateTimeOffset]::Parse($result['startedUtc'])).UtcDateTime -lt $start.AddSeconds(-1)) { throw "$Name did not return a current complete PASS; later operations were not run. $failure" }
    if ($result['rebootRequired']) { throw "$Name requested a reboot; sequence stopped without restarting Explorer or Windows." }
    return $result
}
function Lifecycle([string]$Operation) {
    $arguments=@{MsiPath=$MsiPath;Action=$Operation}
    if ($Operation -eq 'Upgrade') { $arguments.PreviousMetadata=$PreviousMetadata }
    $result=Run-Step ('lifecycle-'+$Operation.ToLowerInvariant()) $lifecycle $arguments 'Lifecycle result: ' 'artifacts/image-copy-save/msi-lifecycle'
    if ($result['productCode'] -ne $product.metadata.productCode) { throw 'Lifecycle result refers to another product.' }
    if ($Operation -ne 'Inspect') {
        if ($result['exitCode'] -ne 0 -or [bool]$result['installedAfter'] -ne ($Operation -in @('Upgrade','Install','Repair'))) { throw 'Unexpected lifecycle result or installed state.' }
    }
    return $result
}
function Preservation([string]$Operation,[string]$Name) {
    return Run-Step $Name $preservation @{MsiPath=$MsiPath;Action=$Operation;PreviousMsiPath=$previous.path;RollbackMsiPath=$RollbackMsiPath} 'Preservation result: ' 'artifacts/image-copy-save/msi-preservation'
}
function Assert-LegacyDefaultState {
    $machine=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key=$machine.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\'+$previous.metadata.productCode)
        if ($null -eq $key) { throw 'Audited legacy 0.1.1 is not installed; this migration sequence will not adopt another state.' }
        try { if ($key.GetValue('DisplayName') -ne 'ImageCopySave' -or $key.GetValue('DisplayVersion') -ne '0.1.1') { throw 'Installed legacy identity differs.' } } finally { $key.Dispose() }
        $folder=[IO.Path]::GetFullPath((Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Workspace/ImageCopySave'))
        foreach ($file in $previous.metadata.files) {
            $path=[IO.Path]::GetFullPath((Join-Path $folder $file.path))
            if (-not $path.StartsWith(($folder.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Legacy file escaped the installed directory.' }
            $ancestor=$path
            while ($ancestor) { if ([IO.File]::GetAttributes($ancestor) -band [IO.FileAttributes]::ReparsePoint) { throw 'Legacy installation contains a reparse path; no migration was attempted.' }; $ancestor=[IO.Path]::GetDirectoryName($ancestor) }
            if ((Hash $path) -ne $file.sha256) { throw 'Legacy default installation differs; the sequence stopped before migration.' }
        }
        return $folder
    } finally { $machine.Dispose() }
}
Write-Report
try {
    if (-not $Elevated) {
        $inventory=Lifecycle 'Inspect'
        $suiteInventory=Preservation 'Inspect' 'preservation-initial-inspect'
        $legacyFolder=Assert-LegacyDefaultState
        $report.legacyDefaultFolder=$legacyFolder
        $report.suiteCurrentlyReady=[bool]$suiteInventory['preflight']['canRunSuite']
        $report.plannedSequence=@('Upgrade 0.1.1 to 0.2.0 at existing default directory','Remove guarded 0.2.0','Inspect clean state','Run isolated preservation suite with legacy upgrade and 0.2.1 rollback','Install final 0.2.0 at default directory')
        $report.status='PASS'; Write-Report
        if ($Action -eq 'Inspect') { return }
        if (-not $RequestElevation) { throw 'Run requires -RequestElevation for one normal Windows administrator approval. Inspect completed; no installation changed.' }
        Assert-FrozenInputs
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        $plan=[ordered]@{schema=1;action='Run';createdUtc=[DateTime]::UtcNow.ToString('o');initiatingUserSid=$identity.User.Value;sequenceSha256=$sequenceHash;msi=$MsiPath;rollbackMsi=$RollbackMsiPath;previousMetadata=$PreviousMetadata;sources=$sources;artifacts=$artifacts;sequence=$report.plannedSequence}
        $FrozenPlanPath=Join-Path $output 'approved-plan.json'
        [IO.File]::WriteAllText($FrozenPlanPath,($plan | ConvertTo-Json -Depth 12),$utf8)
        $planHash=Hash $FrozenPlanPath
        $launchPath=Join-Path $output 'launch.json'
        $launch=[ordered]@{status='REQUESTING_UAC';requestedUtc=[DateTime]::UtcNow.ToString('o');approvedPlan=$FrozenPlanPath;approvedPlanSha256=$planHash;processId=$null;exitCode=$null}
        [IO.File]::WriteAllText($launchPath,($launch | ConvertTo-Json -Depth 6),$utf8)
        $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,'-MsiPath',$MsiPath,'-RollbackMsiPath',$RollbackMsiPath,'-PreviousMetadata',$PreviousMetadata,'-Action','Run','-Elevated','-FrozenPlanPath',$FrozenPlanPath,'-ExpectedPlanHash',$planHash,'-ExpectedSequenceHash',$sequenceHash)
        $quoted=@($arguments | ForEach-Object { if ($_.Contains('"') -or $_ -match '[\r\n]' -or $_.EndsWith('\')) { throw 'Ambiguous elevation argument.' }; '"'+$_+'"' }) -join ' '
        $child=$null
        try {
            $child=Start-Process -FilePath (Join-Path $env:windir 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $quoted -Verb RunAs -WindowStyle Hidden -PassThru
            $launch.status='RUNNING'; $launch.processId=$child.Id
            [IO.File]::WriteAllText($launchPath,($launch | ConvertTo-Json -Depth 6),$utf8)
            $child.WaitForExit(); $launch.exitCode=$child.ExitCode
            $launch.status=$(if($child.ExitCode -eq 0){'COMPLETED'}else{'CHILD_FAILED_OR_BLOCKED'})
            if ($child.ExitCode -ne 0) { throw 'The elevated sequence stopped. Review sequence.json before any recovery or retry.' }
        } catch { if ($null -eq $child) {$launch.status='ELEVATION_NOT_STARTED'}; $launch.error=$_.Exception.Message; throw }
        finally {
            $launch.finishedUtc=[DateTime]::UtcNow.ToString('o')
            [IO.File]::WriteAllText($launchPath,($launch | ConvertTo-Json -Depth 6),$utf8)
            if ($null -ne $child) { $child.Dispose() }
            Write-Output "Preservation sequence launch: $launchPath"
        }
        return
    }
    Assert-FrozenInputs
    [void](Assert-LegacyDefaultState)
    [void](Lifecycle 'Upgrade')
    [void](Lifecycle 'Remove')
    $clean=Preservation 'Inspect' 'preservation-clean-inspect'
    if (-not $clean['preflight']['canRunSuite']) { throw 'Unknown registration, files, or product state remain after removal; no cleanup or suite was attempted.' }
    $suite=Preservation 'Suite' 'preservation-suite'
    if (@($suite['installedProductsAfter']).Count -ne 0 -or @($suite['tests'] | Where-Object {$_['status'] -ne 'PASS'}).Count -ne 0) { throw 'The suite did not completely pass with no installed fixture product.' }
    $clean=Preservation 'Inspect' 'preservation-final-clean-inspect'
    if (-not $clean['preflight']['canRunSuite']) { throw 'The suite left unknown state; final installation was not attempted.' }
    $report.finalInstallAttempted=$true; Write-Report
    [void](Lifecycle 'Install')
    $report.status='PASS'; $report.finalState='ImageCopySave 0.2.0 installed at the default location; no pending reboot'
} catch {
    $report.status='STOPPED'; $report.error=$_.Exception.Message
    $report.recovery='No automatic product removal, reinstall, recursive cleanup, or overwrite was attempted after the failure.'
    throw
} finally {
    $report.finishedUtc=[DateTime]::UtcNow.ToString('o'); Write-Report
    Write-Output "Preservation sequence result: $reportPath"
}
