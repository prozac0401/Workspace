[CmdletBinding()]
param(
    [string]$DotNet,
    [string]$VCToolsRoot,
    [string]$WindowsSdkRoot,
    [string]$WindowsSdkVersion,
    [string]$MakeAppx,
    [string]$Publisher = 'CN=ImageCopySave.Evaluation',
    [string]$Version = '0.1.1.0'
)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
if (-not $DotNet) {
    $localDotNet = Join-Path $repoRoot '.tools/dotnet/dotnet.exe'
    $DotNet = if (Test-Path -LiteralPath $localDotNet) { $localDotNet } else { 'dotnet' }
}
if ($WindowsSdkRoot -and $WindowsSdkVersion -and -not $MakeAppx) { $MakeAppx = Join-Path $WindowsSdkRoot ('bin/' + $WindowsSdkVersion + '/x64/MakeAppx.exe') }
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Use powershell.exe -NoProfile -STA -File build-local.ps1.' }
& (Join-Path $PSScriptRoot 'build.ps1') -DotNet $DotNet
& (Join-Path $PSScriptRoot 'build-shell.ps1') -VCToolsRoot $VCToolsRoot -WindowsSdkRoot $WindowsSdkRoot -WindowsSdkVersion $WindowsSdkVersion
& (Join-Path $PSScriptRoot 'build-package.ps1') -DotNet $DotNet -MakeAppx $MakeAppx -Publisher $Publisher -Version $Version
Write-Host 'Local build and unsigned package inspection completed. No Git, remote CI, installation, signing, or trust changes were performed.'
