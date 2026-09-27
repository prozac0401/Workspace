[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Msi, [Parameter(Mandatory = $true)][string]$OutputDirectory, [switch]$Elevated)
$ErrorActionPreference = 'Stop'
$Msi = (Resolve-Path -LiteralPath $Msi).Path
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
foreach ($path in @($Msi, $OutputDirectory)) {
    if (-not $path.StartsWith(($root + '\artifacts\'), [StringComparison]::OrdinalIgnoreCase) -or $path -match '["\r\n]') { throw 'Test inputs must be inside this worktree artifacts.' }
    $current = $path
    while ($current -ne $root) {
        if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse test paths are not accepted.' }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}
$product = '{68BEBBEE-6A90-4B1E-AE54-89B45A381065}'
$installer = New-Object -ComObject WindowsInstaller.Installer
$database = $installer.OpenDatabase($Msi, 0)
$view = $database.OpenView('SELECT `Property`, `Value` FROM `Property`')
try {
    $view.Execute()
    $properties = @{}
    while ($record = $view.Fetch()) { $properties[$record.StringData(1)] = $record.StringData(2) }
    if ($properties.ProductCode -cne $product -or $properties.ProductName -cne 'ImageCopySave MSI Context Probe' -or $properties.ALLUSERS -cne '1') { throw 'This is not the fixed machine-scope diagnostic MSI.' }
} finally {
    $view.Close()
    foreach ($comObject in @($view, $database, $installer)) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($comObject) }
}
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Elevated) {
    $args = @('-NoLogo','-NoProfile','-NonInteractive','-File', ('"' + $PSCommandPath + '"'), '-Msi', ('"' + $Msi + '"'), '-OutputDirectory', ('"' + $OutputDirectory + '"'), '-Elevated')
    $child = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $args -PassThru
    $child.WaitForExit()
    exit $child.ExitCode
}
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator approval required.' }
$uninstallKey = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$product"
if (Test-Path -LiteralPath $uninstallKey) { throw 'An existing MSI context probe must be preserved.' }
if (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Workspace\ImageCopySave.MsiContextProbe')) { throw 'Existing probe directory must be preserved.' }
if (@(Get-AppxPackage -AllUsers -Name 'ImageCopySave*').Count -ne 0) { throw 'Existing ImageCopySave registration must be preserved.' }
foreach ($clsid in @('9C030D44-BBFA-48B7-BD63-53470C112830', 'B481F5D0-A2B3-47D7-A139-B6C2F60B36DE')) {
    foreach ($hive in @('HKCU:', 'HKLM:')) {
        if (Test-Path -LiteralPath "$hive\Software\Classes\CLSID\{$clsid}") { throw 'Existing COM registration must be preserved.' }
    }
}
$result = [ordered]@{ status='RUNNING'; elevated=$true; installExitCode=$null; uninstallExitCode=$null; startedUtc=[DateTime]::UtcNow.ToString('o') }
$resultPath = Join-Path $OutputDirectory 'msi-lifecycle.json'
try {
    $install = Start-Process msiexec.exe -WindowStyle Hidden -PassThru -Wait -ArgumentList @('/i',('"'+$Msi+'"'),'/qn','/norestart','/l*v',('"'+(Join-Path $OutputDirectory 'msi-install.log')+'"'))
    $result.installExitCode = $install.ExitCode
    $result.status = $(if ($install.ExitCode -eq 0) { 'PASS' } else { 'FAIL' })
} finally {
    if (Test-Path -LiteralPath $uninstallKey) {
        $remove = Start-Process msiexec.exe -WindowStyle Hidden -PassThru -Wait -ArgumentList @('/x',$product,'/qn','/norestart','/l*v',('"'+(Join-Path $OutputDirectory 'msi-uninstall.log')+'"'))
        $result.uninstallExitCode = $remove.ExitCode
        if ($remove.ExitCode -ne 0) { $result.status='FAIL' }
    }
    $result.msiRemains = Test-Path -LiteralPath $uninstallKey
    $result.probeDirectoryRemains = Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'Workspace\ImageCopySave.MsiContextProbe')
    $result.packagesRemain = @(Get-AppxPackage -AllUsers -Name 'ImageCopySave*' | Select-Object Name, PackageFullName)
    if ($result.msiRemains -or $result.probeDirectoryRemains -or $result.packagesRemain.Count -ne 0) { $result.status='FAIL' }
    $result.finishedUtc = [DateTime]::UtcNow.ToString('o')
    [IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}
if ($result.status -ne 'PASS') { exit 1 }
