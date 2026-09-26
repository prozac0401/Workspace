[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet('Inspect', 'Install', 'Update', 'Remove')][string]$Action = 'Inspect',
    [string]$PackagePath,
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ExpectedPublisher,
    [string]$SignTool
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'package-common.ps1')
if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Run this script with Windows PowerShell 5.1 (powershell.exe), which provides the local Appx module.' }
if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64' -or [Environment]::OSVersion.Version.Build -lt 22000) { throw 'Windows 11 x64 is required.' }
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($Action -ne 'Inspect' -and $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Use an ordinary non-elevated user session for evaluation installation and removal.' }
$allMatches = @(Get-AppxPackage -Name 'ImageCopySave.Evaluation' | Where-Object { $_.Name -ceq 'ImageCopySave.Evaluation' })
$installed = @($allMatches | Where-Object { $_.Publisher -ceq $ExpectedPublisher })
if ($allMatches.Count -ne $installed.Count -or $installed.Count -gt 1) { throw 'Conflicting evaluation identity exists. Inspect it before taking any action.' }
if ($Action -eq 'Inspect') {
    if ($PackagePath) { & (Join-Path $PSScriptRoot 'verify-package.ps1') -PackagePath $PackagePath -ExpectedPublisher $ExpectedPublisher -SignTool $SignTool }
    if ($installed.Count -eq 0) { Write-Host 'No matching package is installed for the current user.' }
    $installed | Select-Object Name, Publisher, Version, Architecture, PackageFullName, Status
    return
}
if ($Action -eq 'Remove') {
    if ($installed.Count -ne 1) { throw 'Removal requires exactly one current-user package with the expected identity.' }
    if ($PSCmdlet.ShouldProcess($installed[0].PackageFullName, 'Remove only this current-user evaluation package')) {
        Remove-AppxPackage -Package $installed[0].PackageFullName -ErrorAction Stop
        if (@(Get-AppxPackage -Name 'ImageCopySave.Evaluation' | Where-Object { $_.Name -ceq 'ImageCopySave.Evaluation' -and $_.Publisher -ceq $ExpectedPublisher }).Count -ne 0) { throw 'Package is still registered after removal.' }
        Write-Host 'Package registration removed. Check Explorer menu removal manually. User PNG files were not searched or deleted.'
    }
    return
}
if (-not $PackagePath) { throw 'Install and Update require -PackagePath.' }
$package = Get-ImageCopySavePackage $PackagePath $ExpectedPublisher
Assert-ImageCopySaveTrustedSignature $package $SignTool
if ($Action -eq 'Install' -and $installed.Count -ne 0) { throw 'Install requires no existing package. Use an explicitly requested Update or Remove action.' }
if ($Action -eq 'Update' -and ($installed.Count -ne 1 -or [version]$package.Version -le [version]$installed[0].Version)) { throw 'Update requires exactly one installed package and a strictly higher package version.' }
if ($PSCmdlet.ShouldProcess($package.Path, "$Action the verified current-user evaluation package")) {
    # Do not force-close applications, register loose files, or change developer mode/trust.
    if ((Get-FileHash -LiteralPath $package.Path -Algorithm SHA256).Hash -ne $package.Sha256) { throw 'Package changed after verification.' }
    Add-AppxPackage -Path $package.Path -ErrorAction Stop
    $after = @(Get-AppxPackage -Name $package.Name | Where-Object { $_.Name -ceq $package.Name -and $_.Publisher -ceq $package.Publisher })
    if ($after.Count -ne 1 -or [version]$after[0].Version -ne [version]$package.Version) { throw 'The expected package version was not registered.' }
    $after | Select-Object Name, Publisher, Version, Architecture, PackageFullName, Status
    Write-Host 'OS registration completed. Explorer G0, reinstall, upgrade, and removal behavior need separate manual evidence.'
}
