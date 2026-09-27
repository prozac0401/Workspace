[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MsiPath,
    [ValidateSet('Inspect','Install','Repair','Remove','Rollback','Upgrade')][string]$Action = 'Inspect',
    [string]$PreviousMetadata = '',
    [switch]$DamageOwnedFile
)
# Each call performs exactly one explicitly selected MSI operation. It does not
# restart Explorer, recursively delete install folders, or touch user pictures.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$MsiPath = (Resolve-Path -LiteralPath $MsiPath).Path
if (-not $MsiPath.StartsWith(($root + '\artifacts\image-copy-save\msi\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Lifecycle tests accept only this worktree product MSI artifacts.' }
$current = $MsiPath
while ($current -ne $root) { if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse paths are not accepted.' }; $current = [IO.Path]::GetDirectoryName($current) }
$metadataPath = Join-Path ([IO.Path]::GetDirectoryName($MsiPath)) 'build-metadata.json'
$meta = Get-Content -LiteralPath $metadataPath -Encoding UTF8 -Raw | ConvertFrom-Json
if ($DamageOwnedFile -and $Action -ne 'Repair') { throw 'DamageOwnedFile is accepted only for the owned-file repair test.' }
if ($meta.rollbackTest -ne ($Action -eq 'Rollback')) { throw 'The deliberately failing MSI is only accepted for Rollback.' }
& (Join-Path $PSScriptRoot 'verify-msi.ps1') -MsiPath $MsiPath -AllowRollbackTest:($Action -eq 'Rollback') | Out-Null
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($Action -ne 'Inspect' -and -not $admin) { throw 'Start this test through the normal administrator/UAC launch. This script does not bypass elevation.' }
$output = Join-Path $root ('artifacts/image-copy-save/msi-lifecycle/' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($output) | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
$resultPath = Join-Path $output 'result.json'
$installFolder = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'Workspace/ImageCopySave'
$machine = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
$user = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryView]::Registry64)
$save = '{9C030D44-BBFA-48B7-BD63-53470C112830}'; $copy = '{B481F5D0-A2B3-47D7-A139-B6C2F60B36DE}'
$ownedKeys = @("Software\Classes\CLSID\$save\InprocServer32", "Software\Classes\CLSID\$copy\InprocServer32", 'Software\Classes\Directory\Background\shell\Workspace.ImageCopySave.Save') + @('png','jpg','jpeg','bmp' | ForEach-Object { 'Software\Classes\SystemFileAssociations\.' + $_ + '\shell\Workspace.ImageCopySave.Copy' })
function Assert-PlainPath([string]$Path, [string]$Boundary) {
    $full = [IO.Path]::GetFullPath($Path)
    $allowed = [IO.Path]::GetFullPath($Boundary).TrimEnd('\')
    if ($full -ne $allowed -and -not $full.StartsWith(($allowed + '\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escaped its owned directory.' }
    $ancestor = $full
    while ($ancestor) {
        $attributes = $null
        try { $attributes = [IO.File]::GetAttributes($ancestor) }
        catch [IO.FileNotFoundException] { }
        catch [IO.DirectoryNotFoundException] { }
        if ($null -ne $attributes -and ($attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Reparse point in an installation or recovery path.' }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $full
}
function Restore-RepairFixture([string]$Target, [string]$Backup, [string]$ExpectedHash) {
    $targetPath = Assert-PlainPath $Target $installFolder
    $backupPath = Assert-PlainPath $Backup $output
    if ([IO.File]::Exists($targetPath) -or [IO.Directory]::Exists($targetPath)) { return 'PRESERVED_EXISTING_TARGET' }
    if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Repair backup hash changed; recovery did not use it.' }
    # Recheck ancestors immediately before mutation and never overwrite a file
    # which appeared after the existence check.
    [void](Assert-PlainPath $targetPath $installFolder)
    [IO.File]::Copy($backupPath, $targetPath, $false)
    if ((Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'Restored repair fixture hash differs.' }
    return 'RESTORED_VERIFIED_BACKUP'
}
function Is-Installed([string]$Code) {
    $key = $machine.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\' + $Code)
    if ($null -eq $key) { return $false }
    try { if ($key.GetValue('DisplayName') -ne 'ImageCopySave') { throw 'ProductCode belongs to another product.' }; return $true } finally { $key.Dispose() }
}
function Read-Registrations {
    $rows = @()
    foreach ($path in $ownedKeys) {
        $key = $machine.OpenSubKey($path)
        if ($null -ne $key) { try { $values = @{}; foreach ($name in $key.GetValueNames()) { $values[$name] = $key.GetValue($name) }; $rows += [ordered]@{ key=$path; values=$values } } finally { $key.Dispose() } }
    }
    return ,$rows
}
function Assert-Installed([object]$Expected) {
    if (-not (Is-Installed $Expected.productCode)) { throw 'Expected product is not registered by Windows Installer.' }
    foreach ($entry in $Expected.files) {
        $path = Assert-PlainPath (Join-Path $installFolder $entry.path) $installFolder
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.sha256) { throw "Installed payload differs: $($entry.path)" }
    }
    if ((Read-Registrations).Count -ne 7) { throw 'Expected both COM servers, the save verb, and the four extension-specific copy verbs.' }
}
function Assert-Removed([object]$Expected) {
    if (Is-Installed $Expected.productCode) { throw 'Product is still installed.' }
    if ((Read-Registrations).Count -ne 0) { throw 'Owned COM or verb registry entries remain.' }
    $remaining = @($Expected.files | Where-Object { Test-Path -LiteralPath (Assert-PlainPath (Join-Path $installFolder $_.path) $installFolder) })
    if ($remaining.Count -gt 0) { throw "Installed files remain: $($remaining.Count). A requested reboot must be completed and rechecked before claiming clean removal." }
}
$result = [ordered]@{ status='RUNNING'; action=$Action; startedUtc=[DateTime]::UtcNow.ToString('o'); elevated=$admin; msi=$MsiPath; msiSha256=$meta.msiSha256; productCode=$meta.productCode; installedBefore=(Is-Installed $meta.productCode); registrationsBefore=(Read-Registrations); programFiles=$installFolder; exitCode=$null; rebootRequired=$false; logs=$output; explorerRestarted=$false; userFilesDeleted=$false }
function Write-Result { [IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 10), $utf8) }
Write-Result
$repairTarget = $null; $repairBackup = $null; $repairExpectedHash = $null
try {
    [void](Assert-PlainPath $installFolder $installFolder)
    foreach ($path in $ownedKeys) { $key = $user.OpenSubKey($path); if ($null -ne $key) { $key.Dispose(); throw 'Current-user COM/verb registration would shadow the machine installer.' } }
    if ($Action -eq 'Inspect') { $result.status='PASS'; $result.note='Read-only package and installation inventory.'; return }
    if ($Action -in @('Install','Rollback')) {
        if ($result.installedBefore -or $result.registrationsBefore.Count -gt 0 -or (Test-Path -LiteralPath $installFolder)) { throw 'Existing product registration or install directory found. Test did not adopt it.' }
    } elseif ($Action -in @('Repair','Remove')) { Assert-Installed $meta }
    elseif ($Action -eq 'Upgrade') {
        if (-not $PreviousMetadata) { throw 'Upgrade requires the previous owned build metadata.' }
        $old = Get-Content -LiteralPath $PreviousMetadata -Encoding UTF8 -Raw | ConvertFrom-Json
        if ($old.upgradeCode -ne $meta.upgradeCode -or [Version]$old.version -ge [Version]$meta.version) { throw 'Upgrade metadata does not describe a lower version of the same product.' }
        Assert-Installed $old
    }
    # The preservation fixture is synthetic and deliberately remains after tests.
    $fixture = Join-Path $output 'preserved-user-image.png'
    [IO.File]::WriteAllBytes($fixture, [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='))
    $fixtureHash = (Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash
    if ($DamageOwnedFile) {
        $repairTarget = Assert-PlainPath (Join-Path $installFolder 'ImageCopySave.Engine.dll') $installFolder
        $expectedRepairFile = @($meta.files | Where-Object { $_.path -eq 'ImageCopySave.Engine.dll' })
        if ($expectedRepairFile.Count -ne 1 -or (Get-FileHash -LiteralPath $repairTarget -Algorithm SHA256).Hash -ne $expectedRepairFile[0].sha256) { throw 'Repair target is not the exact file installed by this test.' }
        $repairExpectedHash = $expectedRepairFile[0].sha256
        $repairBackup = Assert-PlainPath (Join-Path $output 'ImageCopySave.Engine.dll.before-repair') $output
        [IO.File]::Copy($repairTarget, $repairBackup, $false)
        if ((Get-FileHash -LiteralPath $repairBackup -Algorithm SHA256).Hash -ne $repairExpectedHash) { throw 'Repair backup verification failed before any removal.' }
        [void](Assert-PlainPath $repairTarget $installFolder)
        Remove-Item -LiteralPath $repairTarget
        $result.repairFixtureRemoved='ImageCopySave.Engine.dll'
        Write-Result
    }
    $switch = $(if ($Action -eq 'Remove') { '/x' } elseif ($Action -eq 'Repair') { '/fa' } else { '/i' })
    $log = Join-Path $output 'msiexec.log'
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = Join-Path $env:windir 'System32/msiexec.exe'; $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.Arguments = $switch + ' "' + $MsiPath + '" /qn /norestart REBOOT=ReallySuppress MSIRESTARTMANAGERCONTROL=Disable /l*v "' + $log + '"'
    $process = [Diagnostics.Process]::Start($info)
    try { $process.WaitForExit(); $result.exitCode=$process.ExitCode } finally { $process.Dispose() }
    $result.rebootRequired = $result.exitCode -eq 3010
    if ((Get-FileHash -LiteralPath $fixture -Algorithm SHA256).Hash -ne $fixtureHash) { throw 'Preservation fixture changed.' }
    $result.preservedFixtureSha256=$fixtureHash
    if ($Action -eq 'Rollback') {
        if ($result.exitCode -ne 1603) { throw 'Rollback test did not report the deliberate installation failure.' }
        Assert-Removed $meta
        $text = Get-Content -LiteralPath $log -Raw
        if ($text -notmatch 'FailRollbackTest' -or $text -notmatch 'Rollback') { throw 'MSI log does not show the expected rollback test.' }
    } else {
        if ($result.exitCode -notin @(0,3010)) { throw "msiexec failed: $($result.exitCode)" }
        if ($Action -eq 'Remove') { Assert-Removed $meta } else { Assert-Installed $meta }
        if ($Action -eq 'Upgrade' -and (Is-Installed $old.productCode)) { throw 'Old product registration remains after upgrade.' }
    }
    $result.status = $(if ($result.rebootRequired) { 'PENDING_REBOOT' } else { 'PASS' })
} catch {
    $originalError = $_
    $result.status='FAIL'; $result.error=$originalError.Exception.Message
    if ($repairTarget -and $repairBackup -and $repairExpectedHash) {
        try { $result.repairRecovery = Restore-RepairFixture $repairTarget $repairBackup $repairExpectedHash }
        catch { $result.repairRecovery='FAILED'; $result.repairRecoveryError=$_.Exception.Message }
    }
    throw $originalError
}
finally {
    $result.installedAfter=Is-Installed $meta.productCode
    $result.registrationsAfter=Read-Registrations
    $result.finishedUtc=[DateTime]::UtcNow.ToString('o')
    Write-Result
    $machine.Dispose(); $user.Dispose()
    Write-Output "Lifecycle result: $resultPath"
}
