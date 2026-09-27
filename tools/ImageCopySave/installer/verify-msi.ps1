[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$MsiPath, [string]$MetadataPath = '', [switch]$AllowRollbackTest)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$MsiPath = (Resolve-Path -LiteralPath $MsiPath).Path
if (-not $MetadataPath) { $MetadataPath = Join-Path ([IO.Path]::GetDirectoryName($MsiPath)) 'build-metadata.json' }
$metadata = Get-Content -LiteralPath $MetadataPath -Encoding UTF8 -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $MsiPath -Algorithm SHA256).Hash -ne $metadata.msiSha256) { throw 'MSI does not match its build metadata.' }
if ($metadata.rollbackTest -and -not $AllowRollbackTest) { throw 'This is an intentionally failing local test MSI, not the product installer.' }
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
foreach ($row in $custom) {
    if ($row[0] -eq 'FailRollbackTest' -and $metadata.rollbackTest -and [int]$row[1] -eq 19) { continue }
    if (([int]$row[1] -band 63) -notin @(19, 51)) { throw "Unexpected executable custom action: $($row[0])" }
}
$components = Query 'SELECT `Attributes` FROM `Component`' 1
if (@($components | Where-Object { ([int]$_[0] -band 256) -eq 0 }).Count -gt 0) { throw 'All components must use the x64 registry/filesystem view.' }
[ordered]@{ status='PASS'; product=$properties.ProductName; version=$properties.ProductVersion; productCode=$properties.ProductCode; signature='NotSigned'; perMachine=$true; selfContainedFiles=$files.Count; embeddedCabinets=$media.Count; comVerbs=$commands.Count; executableCustomActions=0; rollbackTest=[bool]$metadata.rollbackTest; explorerRestart='disabled'; sourceMsiSha256=$metadata.msiSha256; installLifecycle='NOT RUN by this verifier'; explorerUi='NOT RUN by this verifier' } | ConvertTo-Json
