[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MsiPath,
    [Parameter(Mandatory=$true)][string]$RollbackMsiPath,
    [string]$PreviousMetadata = '',
    [switch]$Elevated,
    [string]$SequenceDirectory = '',
    [string]$ExpectedMsiHash = '',
    [string]$ExpectedRollbackHash = '',
    [string]$ExpectedLifecycleHash = '',
    [string]$ExpectedVerifierHash = '',
    [string]$ExpectedPreviousHash = '',
    [string]$ExpectedSequenceHash = '',
    [string]$ExpectedProductMetadataHash = '',
    [string]$ExpectedRollbackMetadataHash = ''
)
# One normal UAC launch, then an optional upgrade and three fixed operations.
# This script never installs
# until the existing package verifier and lifecycle preflight accept the inputs.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$repoRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$lifecycleScript=Join-Path $PSScriptRoot 'test-msi-lifecycle.ps1'
$verifierScript=Join-Path $PSScriptRoot 'verify-msi.ps1'
$encoding=New-Object Text.UTF8Encoding($false)
function Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
$sequenceHash=Hash $PSCommandPath
$lifecycleHash=Hash $lifecycleScript
$verifierHash=Hash $verifierScript
# This check precedes Read-Build and every invocation of another script. The
# expected values are passed in the original runas arguments before consent.
if ($Elevated) {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'The sequence child requires normal Windows administrator elevation.' }
    $expectedValues=@($ExpectedSequenceHash,$ExpectedLifecycleHash,$ExpectedVerifierHash,$ExpectedMsiHash,$ExpectedRollbackHash,$ExpectedProductMetadataHash,$ExpectedRollbackMetadataHash)
    if ($PreviousMetadata) { $expectedValues+=$ExpectedPreviousHash }
    foreach ($expected in $expectedValues) { if ($expected -notmatch '^[A-Fa-f0-9]{64}$') { throw 'An expected SHA256 value is missing or invalid.' } }
    if ($ExpectedSequenceHash -ne $sequenceHash -or $ExpectedLifecycleHash -ne $lifecycleHash -or $ExpectedVerifierHash -ne $verifierHash) { throw 'Sequence, lifecycle or verifier script changed while waiting for elevation. No child script was executed.' }
} elseif ($SequenceDirectory -or $ExpectedMsiHash -or $ExpectedRollbackHash -or $ExpectedLifecycleHash -or $ExpectedVerifierHash -or $ExpectedPreviousHash -or $ExpectedSequenceHash -or $ExpectedProductMetadataHash -or $ExpectedRollbackMetadataHash) { throw 'Internal sequence arguments are only accepted in the elevated child.' }
function Owned-Path([string]$Path,[string]$Subdirectory) {
    $full=[IO.Path]::GetFullPath($Path)
    $prefix=[IO.Path]::GetFullPath((Join-Path $repoRoot $Subdirectory)).TrimEnd('\')+'\'
    if (-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Sequence paths must remain in the expected worktree artifact directory.' }
    $ancestor=$full
    while ($ancestor) {
        $attributes=$null
        try { $attributes=[IO.File]::GetAttributes($ancestor) }
        catch [IO.FileNotFoundException] { }
        catch [IO.DirectoryNotFoundException] { }
        if ($null -ne $attributes -and ($attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Sequence inputs and reports may not traverse reparse points.' }
        $ancestor=[IO.Path]::GetDirectoryName($ancestor)
    }
    return $full
}
function Read-Build([string]$Path,[bool]$Rollback,[string]$ExpectedMetadataHash) {
    $full=Owned-Path $Path 'artifacts/image-copy-save/msi'
    $metadataPath=Owned-Path (Join-Path ([IO.Path]::GetDirectoryName($full)) 'build-metadata.json') 'artifacts/image-copy-save/msi'
    $metadataHash=Hash $metadataPath
    if ($Elevated -and $metadataHash -ne $ExpectedMetadataHash) { throw 'Build metadata changed while waiting for elevation.' }
    $metadata=Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([bool]$metadata.rollbackTest -ne $Rollback -or (Hash $full) -ne $metadata.msiSha256) { throw 'MSI kind or hash does not match its metadata.' }
    if ($Elevated -and (Hash $verifierScript) -ne $ExpectedVerifierHash) { throw 'Verifier changed before package verification.' }
    $verification=(& $verifierScript -MsiPath $full -AllowRollbackTest:$Rollback) | ConvertFrom-Json
    if ($verification.status -ne 'PASS') { throw 'MSI package verification failed.' }
    if ((Hash $metadataPath) -ne $metadataHash) { throw 'Build metadata changed during package verification.' }
    return [pscustomobject]@{ path=$full; metadata=$metadata; metadataPath=$metadataPath; metadataSha256=$metadataHash; verification=$verification }
}
$productBuild=Read-Build $MsiPath $false $ExpectedProductMetadataHash
$rollbackBuild=Read-Build $RollbackMsiPath $true $ExpectedRollbackMetadataHash
$MsiPath=$productBuild.path; $RollbackMsiPath=$rollbackBuild.path
if ($productBuild.metadata.version -ne '0.1.1') { throw 'This final sequence is scoped to the 0.1.1 candidate.' }
if ($productBuild.metadata.upgradeCode -ne $rollbackBuild.metadata.upgradeCode -or $productBuild.metadata.productCode -eq $rollbackBuild.metadata.productCode) { throw 'Rollback must be a distinct test product in the same upgrade family.' }
$previousHash=''
$operations=@('Remove','Rollback','Install')
if ($PreviousMetadata) {
    $PreviousMetadata=Owned-Path $PreviousMetadata 'artifacts/image-copy-save/msi'
    if ([IO.Path]::GetFileName($PreviousMetadata) -ne 'build-metadata.json') { throw 'Expected an original previous build metadata file.' }
    $previousBuildMetadata=Get-Content -LiteralPath $PreviousMetadata -Raw -Encoding UTF8 | ConvertFrom-Json
    $previousBuild=Read-Build $previousBuildMetadata.msi $false $ExpectedPreviousHash
    if ((Join-Path ([IO.Path]::GetDirectoryName($previousBuild.path)) 'build-metadata.json') -ne $PreviousMetadata -or $previousBuild.metadata.upgradeCode -ne $productBuild.metadata.upgradeCode -or [Version]$previousBuild.metadata.version -ge [Version]$productBuild.metadata.version) { throw 'Previous metadata must describe a lower verified version in the same product family.' }
    $previousHash=Hash $PreviousMetadata
    $operations=@('Upgrade')+$operations
}
if (-not $Elevated) {
    $SequenceDirectory=Owned-Path (Join-Path $repoRoot ('artifacts/image-copy-save/msi-final-sequence/'+[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ')+'-'+[Guid]::NewGuid().ToString('N'))) 'artifacts/image-copy-save/msi-final-sequence'
    [IO.Directory]::CreateDirectory($SequenceDirectory) | Out-Null
    $launchPath=Join-Path $SequenceDirectory 'launch.json'
    $launch=[ordered]@{ status='REQUESTING_UAC'; requestedUtc=[DateTime]::UtcNow.ToString('o'); msi=$MsiPath; rollbackMsi=$RollbackMsiPath; previousMetadata=$PreviousMetadata; processId=$null; exitCode=$null; sequenceSha256=$sequenceHash; lifecycleSha256=$lifecycleHash; verifierSha256=$verifierHash; productMetadataSha256=$productBuild.metadataSha256; rollbackMetadataSha256=$rollbackBuild.metadataSha256; sequence=$operations }
    function Write-Launch { [IO.File]::WriteAllText($launchPath,($launch | ConvertTo-Json -Depth 6),$encoding) }
    Write-Launch
    $arguments=@('-NoLogo','-NoProfile','-NonInteractive','-File',$PSCommandPath,'-MsiPath',$MsiPath,'-RollbackMsiPath',$RollbackMsiPath,'-Elevated','-SequenceDirectory',$SequenceDirectory,'-ExpectedMsiHash',$productBuild.metadata.msiSha256,'-ExpectedRollbackHash',$rollbackBuild.metadata.msiSha256,'-ExpectedLifecycleHash',$lifecycleHash,'-ExpectedVerifierHash',$verifierHash,'-ExpectedSequenceHash',$sequenceHash,'-ExpectedProductMetadataHash',$productBuild.metadataSha256,'-ExpectedRollbackMetadataHash',$rollbackBuild.metadataSha256)
    if ($PreviousMetadata) { $arguments+=@('-PreviousMetadata',$PreviousMetadata,'-ExpectedPreviousHash',$previousHash) }
    $quoted=@($arguments | ForEach-Object { if ($_.Contains('"') -or $_ -match '[\r\n]' -or $_.EndsWith('\')) { throw 'Ambiguous elevation argument.' }; '"'+$_+'"' }) -join ' '
    $child=$null
    try {
        $child=Start-Process -FilePath (Join-Path $env:windir 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $quoted -Verb RunAs -WindowStyle Hidden -PassThru
        $launch.status='RUNNING'; $launch.processId=$child.Id; Write-Launch
        $child.WaitForExit(); $launch.exitCode=$child.ExitCode
        $launch.status=$(if ($child.ExitCode -eq 0) { 'COMPLETED' } else { 'CHILD_FAILED_OR_BLOCKED' })
    } catch { $launch.status='ELEVATION_NOT_STARTED'; $launch.error=$_.Exception.Message; throw }
    finally { $launch.finishedUtc=[DateTime]::UtcNow.ToString('o'); Write-Launch; if ($null -ne $child) { $child.Dispose() }; Write-Output "Sequence launch: $launchPath" }
    return
}
if (-not $SequenceDirectory) { throw 'Missing sequence report directory.' }
$SequenceDirectory=Owned-Path $SequenceDirectory 'artifacts/image-copy-save/msi-final-sequence'
if (-not (Test-Path -LiteralPath $SequenceDirectory -PathType Container)) { throw 'Expected the report directory created before elevation.' }
if ($ExpectedMsiHash -ne $productBuild.metadata.msiSha256 -or $ExpectedRollbackHash -ne $rollbackBuild.metadata.msiSha256 -or $ExpectedLifecycleHash -ne $lifecycleHash -or $ExpectedVerifierHash -ne $verifierHash -or $ExpectedPreviousHash -ne $previousHash) { throw 'MSI, previous metadata or test scripts changed while waiting for elevation.' }
$sequencePath=Join-Path $SequenceDirectory 'sequence.json'
$steps=New-Object 'System.Collections.Generic.List[object]'
$sequence=[ordered]@{ status='RUNNING'; startedUtc=[DateTime]::UtcNow.ToString('o'); elevated=$true; msi=$MsiPath; rollbackMsi=$RollbackMsiPath; previousMetadata=$PreviousMetadata; msiSha256=$ExpectedMsiHash; rollbackMsiSha256=$ExpectedRollbackHash; sequenceSha256=$ExpectedSequenceHash; steps=@(); stoppedAfter=$null; explorerRestarted=$false }
function Write-Sequence { $sequence.steps=@($steps.ToArray()); [IO.File]::WriteAllText($sequencePath,($sequence | ConvertTo-Json -Depth 10),$encoding) }
Write-Sequence
try {
    foreach ($operation in $operations) {
        # Recheck approved scripts before each action. Existing lifecycle code
        # owns MSI preflight, exact installed-state checks, and all operations.
        if ((Hash $PSCommandPath) -ne $ExpectedSequenceHash -or (Hash $lifecycleScript) -ne $ExpectedLifecycleHash -or (Hash $verifierScript) -ne $ExpectedVerifierHash) { throw 'Sequence or test scripts changed during the sequence.' }
        if ((Hash $productBuild.metadataPath) -ne $ExpectedProductMetadataHash -or (Hash $rollbackBuild.metadataPath) -ne $ExpectedRollbackMetadataHash) { throw 'Product or rollback metadata changed during the sequence.' }
        $inputMsi=$(if ($operation -eq 'Rollback') { $RollbackMsiPath } else { $MsiPath })
        $expectedBuild=$(if ($operation -eq 'Rollback') { $rollbackBuild } else { $productBuild })
        if ((Hash $inputMsi) -ne $expectedBuild.metadata.msiSha256) { throw 'An MSI changed during the sequence.' }
        $captured=New-Object 'System.Collections.Generic.List[string]'
        $operationError=$null
        $started=[DateTime]::UtcNow
        $operationArguments=@{ MsiPath=$inputMsi; Action=$operation }
        if ($operation -eq 'Upgrade') {
            if ((Hash $PreviousMetadata) -ne $ExpectedPreviousHash) { throw 'Previous metadata changed during the sequence.' }
            $operationArguments.PreviousMetadata=$PreviousMetadata
        }
        try {
            & $lifecycleScript @operationArguments 2>&1 | ForEach-Object { $captured.Add([string]$_) }
        } catch { $operationError=$_.Exception.Message; $captured.Add($operationError) }
        $stepLog=Join-Path $SequenceDirectory ($operation.ToLowerInvariant()+'.log')
        [IO.File]::WriteAllLines($stepLog,$captured,$encoding)
        $resultLines=@($captured | Where-Object { $_.StartsWith('Lifecycle result: ') })
        if ($resultLines.Count -ne 1) { throw "$operation did not produce exactly one lifecycle result. See $stepLog. $operationError" }
        $resultPath=Owned-Path $resultLines[0].Substring('Lifecycle result: '.Length) 'artifacts/image-copy-save/msi-lifecycle'
        # Registry default values have the JSON key "". Windows PowerShell 5.1
        # ConvertFrom-Json cannot represent that key on a PSCustomObject.
        Add-Type -AssemblyName System.Web.Extensions
        $jsonReader=New-Object System.Web.Script.Serialization.JavaScriptSerializer
        $result=$jsonReader.DeserializeObject([IO.File]::ReadAllText($resultPath,[Text.Encoding]::UTF8))
        $steps.Add([ordered]@{ action=$operation; status=$result.status; resultPath=$resultPath; log=$stepLog; exitCode=$result.exitCode; rebootRequired=$result.rebootRequired; installedAfter=$result.installedAfter })
        $sequence.stoppedAfter=$operation; Write-Sequence
        if ($operationError -or $result.status -ne 'PASS' -or $result.rebootRequired) { throw "$operation was not a complete PASS. Remaining operations were not run. $operationError" }
        if ($result.action -ne $operation -or $result.productCode -ne $expectedBuild.metadata.productCode -or $result.msiSha256 -ne $expectedBuild.metadata.msiSha256 -or ([DateTimeOffset]::Parse($result.startedUtc)).UtcDateTime -lt $started.AddSeconds(-1)) { throw 'Lifecycle result does not match this operation.' }
        $expectedInstalled=$operation -in @('Install','Upgrade')
        if ([bool]$result.installedAfter -ne $expectedInstalled) { throw 'Lifecycle result reports an unexpected final MSI state.' }
        if (($operation -eq 'Rollback' -and $result.exitCode -ne 1603) -or ($operation -ne 'Rollback' -and $result.exitCode -ne 0)) { throw 'Unexpected MSI result code; sequence stopped.' }
    }
    $sequence.status='PASS'; $sequence.finalState='ImageCopySave 0.1.1 installed for Explorer verification'
} catch { $sequence.status='STOPPED'; $sequence.error=$_.Exception.Message; throw }
finally { $sequence.finishedUtc=[DateTime]::UtcNow.ToString('o'); Write-Sequence; Write-Output "Sequence result: $sequencePath" }
