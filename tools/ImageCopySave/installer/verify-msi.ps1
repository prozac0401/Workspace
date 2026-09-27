[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$MsiPath, [string]$MetadataPath = '', [switch]$AllowRollbackTest, [switch]$AllowRecoveryUpdate)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$MsiPath = (Resolve-Path -LiteralPath $MsiPath).Path
if (-not $MetadataPath) { $MetadataPath = Join-Path ([IO.Path]::GetDirectoryName($MsiPath)) 'build-metadata.json' }
$metadata = Get-Content -LiteralPath $MetadataPath -Encoding UTF8 -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $MsiPath -Algorithm SHA256).Hash -ne $metadata.msiSha256) { throw 'MSI does not match its build metadata.' }
if ($metadata.rollbackTest -and -not $AllowRollbackTest) { throw 'This is an intentionally failing local test MSI, not the product installer.' }
if ($metadata.recoveryUpdate -and -not $AllowRecoveryUpdate) { throw 'This local servicing package is not a public release installer.' }
if ((Get-AuthenticodeSignature -LiteralPath $MsiPath).Status -ne 'NotSigned') { throw 'MSI must be unsigned.' }
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase($MsiPath, 0)
function Query([string]$Sql, [int]$Columns) {
    $view = $database.OpenView($Sql)
    try {
        [void]$view.Execute(); $rows = @()
        while ($record = $view.Fetch()) { $row = @(); for ($i=1; $i -le $Columns; $i++) { $row += $record.StringData($i) }; $rows += ,$row }
        return ,$rows
    } finally { [void]$view.Close() }
}
$properties = @{}
foreach ($row in (Query 'SELECT `Property`, `Value` FROM `Property`' 2)) { $properties[$row[0]] = $row[1] }
if ($properties.ProductName -ne 'ImageCopySave' -or $properties.ProductCode -ne $metadata.productCode -or $properties.ProductVersion -ne $metadata.version) { throw 'Unexpected MSI product identity.' }
if ($properties.ALLUSERS -ne '1') { throw 'MSI must use per-machine installation.' }
if ($properties.MSIRESTARTMANAGERCONTROL -ne 'Disable' -or $properties.REBOOT -ne 'ReallySuppress') { throw 'MSI must not automatically close Explorer or restart Windows.' }
$registry = Query 'SELECT `Root`, `Key`, `Name`, `Value` FROM `Registry`' 4
$saveClsid = '{9C030D44-BBFA-48B7-BD63-53470C112830}'
$copyClsid = '{B481F5D0-A2B3-47D7-A139-B6C2F60B36DE}'
foreach ($row in $registry) {
    if ($row[0] -ne '2') { throw 'Only HKLM registry resources are expected.' }
    $allowed = $row[1] -in @("Software\Classes\CLSID\$saveClsid\InprocServer32", "Software\Classes\CLSID\$copyClsid\InprocServer32", 'Software\Classes\Directory\Background\shell\Workspace.ImageCopySave.Save') -or $row[1] -match '^Software\\Classes\\SystemFileAssociations\\\.(png|jpg|jpeg|bmp)\\shell\\Workspace\.ImageCopySave\.Copy$'
    if (-not $allowed) { throw "Unexpected registry resource: $($row[1])" }
    if ($row[1] -like '*\Approved' -and $row[2] -notin @($saveClsid, $copyClsid)) { throw 'MSI touches another Shell extension.' }
}
$commands = @($registry | Where-Object { $_[2] -eq 'ExplorerCommandHandler' })
if ($commands.Count -ne 5 -or @($commands | Where-Object { $_[3] -eq $saveClsid }).Count -ne 1 -or @($commands | Where-Object { $_[3] -eq $copyClsid }).Count -ne 4) { throw 'Expected the save verb and copy verb for exactly four image extensions.' }
if (@($registry | Where-Object { $_[2] -eq 'NeverDefault' -and $_[3] -eq '' }).Count -ne 5) { throw 'All image commands must remain non-default verbs.' }
$servers = @($registry | Where-Object { $_[1] -like '*\InprocServer32' -and $_[2] -eq '' })
if ($servers.Count -ne 2 -or @($servers | Where-Object { $_[3] -ne '[INSTALLFOLDER]ImageCopySave.Shell.dll' }).Count -ne 0) { throw 'COM server paths must use the installed DLL.' }
$files = Query 'SELECT `FileName`, `FileSize` FROM `File`' 2
if ($files.Count -ne $metadata.files.Count) { throw 'MSI file count differs from the complete payload.' }
$expectedFiles = @{}
foreach ($entry in $metadata.files) { $name = [IO.Path]::GetFileName($entry.path); $key = $name + ':' + $entry.bytes; if (-not $expectedFiles.ContainsKey($key)) { $expectedFiles[$key] = 0 }; $expectedFiles[$key]++ }
foreach ($row in $files) {
    $name = ($row[0] -split '\|')[-1]; $key = $name + ':' + $row[1]
    if (-not $expectedFiles.ContainsKey($key) -or $expectedFiles[$key] -lt 1) { throw "Unexpected packaged file: $name" }
    $expectedFiles[$key]--
    if ($name -eq 'AppxManifest.xml' -or $name -match '\.(msix|appx|ps1)$') { throw 'Classic MSI should not carry Appx registration or PowerShell installers.' }
}
$media = Query 'SELECT `Cabinet` FROM `Media`' 1
if ($media.Count -eq 0 -or @($media | Where-Object { -not $_[0].StartsWith('#') }).Count -ne 0) { throw 'Every cabinet must be embedded in the MSI.' }
$tableNames = @((Query 'SELECT `Name` FROM `_Tables`' 1) | ForEach-Object { $_[0] })
$custom = $(if ($tableNames -contains 'CustomAction') { Query 'SELECT `Action`, `Type`, `Source`, `Target` FROM `CustomAction`' 4 } else { @() })
$guardActions = @($custom | Where-Object { $_[0] -in @('ImageGuardPreflight','ImageGuardDeferred') })
if ($guardActions.Count -ne 2) { throw 'Both preservation checks are mandatory.' }
foreach ($row in $custom) {
    if ($row[0] -eq 'FailRollbackTest' -and $metadata.rollbackTest -and [int]$row[1] -eq 19) { continue }
    if ($row[0] -eq 'ImageGuardPreflight' -and [int]$row[1] -eq 1 -and $row[2] -eq 'ImageGuard' -and $row[3] -eq 'ImageGuardPreflight') { continue }
    if ($row[0] -eq 'ImageGuardDeferred' -and [int]$row[1] -eq 11265 -and $row[2] -eq 'ImageGuard' -and $row[3] -eq 'ImageGuardDeferred') { continue }
    if (([int]$row[1] -band 63) -notin @(19, 51)) { throw "Unexpected executable custom action: $($row[0])" }
}
if ($properties.ImageGuardSchema -ne '2' -or $metadata.guardSchema -ne 2) { throw 'Missing supported guard schema.' }
$sequence = @{}
foreach ($row in (Query 'SELECT `Action`, `Condition`, `Sequence` FROM `InstallExecuteSequence`' 3)) { $sequence[$row[0]] = @{condition=$row[1]; number=[int]$row[2]} }
if ($sequence.ImageGuardPreflight.condition -or $sequence.ImageGuardDeferred.condition) { throw 'Guard actions cannot be conditionally bypassed.' }
if ($sequence.ImageGuardPreflight.number -le $sequence.CostFinalize.number -or $sequence.ImageGuardPreflight.number -ge $sequence.InstallInitialize.number) { throw 'Preflight must run after costing but before transaction/removal.' }
if ($sequence.RemoveExistingProducts.number -le $sequence.InstallInitialize.number -or $sequence.ImageGuardDeferred.number -le $sequence.RemoveExistingProducts.number) { throw 'Upgrade removal and guard ordering is unsafe.' }
foreach ($action in @('ProcessComponents','RemoveRegistryValues','RemoveFiles','InstallFiles','WriteRegistryValues')) {
    if ($sequence.ContainsKey($action) -and $sequence.ImageGuardDeferred.number -ge $sequence[$action].number) { throw "Deferred guard is too late: $action" }
}
$guardFiles = Query 'SELECT `Path`, `Sha256` FROM `ImageGuardFile`' 2
if ($guardFiles.Count -ne $metadata.files.Count) { throw 'Guard inventory does not cover every payload file.' }
$guardExpected = @{}
foreach ($entry in $metadata.files) { $guardExpected[$entry.path] = $entry.sha256 }
foreach ($row in $guardFiles) {
    if (-not $guardExpected.ContainsKey($row[0]) -or $guardExpected[$row[0]] -ne $row[1]) { throw 'Guard path/hash differs from packaged payload.' }
    $guardExpected.Remove($row[0])
}
if ($guardExpected.Count -ne 0) { throw 'Duplicate or missing guard paths.' }
$legacyExpected = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'baselines/0.1.1.json') -Encoding UTF8 -Raw | ConvertFrom-Json
$priorRows = Query 'SELECT `Id`, `ProductCode`, `PackageCode`, `AllowSameProduct`, `FileCount`, `RegistryCount` FROM `ImageGuardPrior`' 6
$priorFiles = Query 'SELECT `PriorId`, `Path`, `Sha256`, `ComponentId` FROM `ImageGuardPriorFile`' 4
$priorRegistry = Query 'SELECT `PriorId`, `Root`, `Key`, `Name`, `Value` FROM `ImageGuardPriorRegistry`' 5
$priorMap = @{}
foreach ($prior in $metadata.priorPackages) {
    if ($priorMap.ContainsKey($prior.id)) { throw 'Duplicate prior baseline metadata.' }
    $priorMap[$prior.id] = $prior
}
if ($priorRows.Count -ne $priorMap.Count) { throw 'Prior baseline count mismatch.' }
$legacyPins = 0; $servicingPins = 0; $expectedPriorFileCount = 0; $expectedPriorRegistryCount = 0
foreach ($row in $priorRows) {
    if (-not $priorMap.ContainsKey($row[0])) { throw 'Unexpected prior package baseline.' }
    $prior = $priorMap[$row[0]]; $priorMap.Remove($row[0])
    if ($row[1] -ne $prior.productCode -or $row[2] -ne $prior.packageCode -or [int]$row[3] -ne $prior.allowSameProduct -or [int]$row[4] -ne $prior.files.Count -or [int]$row[5] -ne $prior.registry.Count) { throw 'Prior package identity or resource counts differ from audited baseline.' }
    if ($prior.productCode -eq $legacyExpected.productCode) {
        if ($prior.packageCode -ne $legacyExpected.packageCode -or $prior.msiSha256 -ne $legacyExpected.msiSha256 -or $prior.baselineSha256 -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'baselines/0.1.1.json') -Algorithm SHA256).Hash) { throw 'Legacy package pin differs from audited source.' }
        $legacyPins++
    }
    if ($prior.allowSameProduct -eq 1) {
        if (-not $metadata.recoveryUpdate -or $prior.productCode -ne $metadata.productCode -or $prior.packageCode -ne '{E02D0EEC-5EF4-4BF1-85EF-20074416A568}' -or $prior.msiSha256 -ne 'DE666CC6115E0A459EFD1F75EBE6760EA58DA09E10E02CC669470E69AD41B092') { throw 'Unexpected same-product servicing authority.' }
        $servicingPins++
    } elseif ($prior.allowSameProduct -ne 0 -or $prior.productCode -eq $metadata.productCode) { throw 'Invalid servicing authority.' }
    $fileMap = @{}; foreach ($entry in $prior.files) { if ($fileMap.ContainsKey($entry.path)) { throw 'Duplicate predecessor file.' }; $fileMap[$entry.path] = $entry }
    foreach ($fileRow in @($priorFiles | Where-Object { $_[0] -eq $prior.id })) {
        if (-not $fileMap.ContainsKey($fileRow[1])) { throw 'Unexpected predecessor file.' }
        $entry = $fileMap[$fileRow[1]]; $fileMap.Remove($fileRow[1])
        if ($entry.sha256 -ne $fileRow[2] -or $entry.componentId -ne $fileRow[3]) { throw 'Predecessor file hash/component differs from audit.' }
    }
    if ($fileMap.Count -ne 0) { throw 'Incomplete predecessor file ownership.' }
    $regMap = @{}; foreach ($entry in $prior.registry) { $slot = $entry.key + '|' + $entry.name; if ($regMap.ContainsKey($slot)) { throw 'Duplicate predecessor registry value.' }; $regMap[$slot] = $entry }
    foreach ($regRow in @($priorRegistry | Where-Object { $_[0] -eq $prior.id })) {
        $slot = $regRow[2] + '|' + $regRow[3]
        if (-not $regMap.ContainsKey($slot)) { throw 'Unexpected predecessor registry value.' }
        $entry = $regMap[$slot]; $regMap.Remove($slot)
        if ([int]$regRow[1] -ne 2 -or [int]$entry.root -ne 2 -or $entry.value -cne $regRow[4]) { throw 'Predecessor registry value differs from audit.' }
    }
    if ($regMap.Count -ne 0) { throw 'Incomplete predecessor registry ownership.' }
    $expectedPriorFileCount += $prior.files.Count; $expectedPriorRegistryCount += $prior.registry.Count
}
if ($priorMap.Count -ne 0 -or $legacyPins -ne 1 -or $servicingPins -ne [int][bool]$metadata.recoveryUpdate -or $priorFiles.Count -ne $expectedPriorFileCount -or $priorRegistry.Count -ne $expectedPriorRegistryCount) { throw 'Incomplete or orphaned predecessor ownership tables.' }
$binaryView = $database.OpenView('SELECT `Data` FROM `Binary` WHERE `Name` = ''ImageGuard''')
try {
    [void]$binaryView.Execute(); $binaryRecord = $binaryView.Fetch()
    if ($null -eq $binaryRecord) { throw 'Preservation guard is not embedded.' }
    $guardData = $binaryRecord.ReadStream(1, $binaryRecord.DataSize(1), 1)
    $guardBytes = New-Object byte[] $guardData.Length
    for ($i=0; $i -lt $guardData.Length; $i++) { $guardBytes[$i] = [byte][char]$guardData[$i] }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $binaryHash = [BitConverter]::ToString($sha.ComputeHash($guardBytes)).Replace('-','') } finally { $sha.Dispose() }
    if ($binaryHash -ne $metadata.guardDllSha256) { throw 'Embedded guard binary differs from the compiled DLL.' }
} finally { [void]$binaryView.Close() }
foreach ($row in $registry) { if ($row[2] -in @('*','-','+')) { throw 'Whole-key registry removal is forbidden.' } }
if ($tableNames -contains 'RemoveFile' -and (Query 'SELECT `FileKey` FROM `RemoveFile`' 1).Count -gt 0) { throw 'Wildcard/extra removal rows are forbidden.' }
if ($tableNames -contains 'RemoveRegistry' -and (Query 'SELECT `RemoveRegistry` FROM `RemoveRegistry`' 1).Count -gt 0) { throw 'Extra registry removal rows are forbidden.' }
$components = Query 'SELECT `Attributes` FROM `Component`' 1
if (@($components | Where-Object { ([int]$_[0] -band 256) -eq 0 }).Count -gt 0) { throw 'All components must use the x64 registry/filesystem view.' }
[ordered]@{ status='PASS'; product=$properties.ProductName; version=$properties.ProductVersion; productCode=$properties.ProductCode; signature='NotSigned'; perMachine=$true; selfContainedFiles=$files.Count; embeddedCabinets=$media.Count; comVerbs=$commands.Count; executableCustomActions=2; preservationGuard='SHA256 files, exact registry values, immediate plus deferred'; guardSchema=2; priorPackages=$priorRows.Count; guardSha256=$binaryHash; rollbackTest=[bool]$metadata.rollbackTest; recoveryUpdate=[bool]$metadata.recoveryUpdate; explorerRestart='disabled'; sourceMsiSha256=$metadata.msiSha256; installLifecycle='NOT RUN by this verifier'; explorerUi='NOT RUN by this verifier' } | ConvertTo-Json
