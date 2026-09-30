[CmdletBinding()]
param([string]$Python = 'python', [string]$VCToolsRoot, [string]$WindowsSdkRoot, [string]$Wix, [string]$Node, [string]$Version, [string]$OutputDir, [switch]$LifecyclePackages)
$ErrorActionPreference = 'Stop'
$arguments = @((Join-Path $PSScriptRoot 'build.py'))
if ($VCToolsRoot) { $arguments += @('--msvc', $VCToolsRoot) }
if ($WindowsSdkRoot) { $arguments += @('--sdk', $WindowsSdkRoot) }
if ($Wix) { $arguments += @('--wix', $Wix) }
if ($Node) { $arguments += @('--node', $Node) }
if ($Version) { $arguments += @('--version', $Version) }
if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
if ($LifecyclePackages) { $arguments += '--lifecycle-packages' }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw 'DownloadVersionManager release construction failed.' }
