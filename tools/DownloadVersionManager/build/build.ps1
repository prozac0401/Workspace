[CmdletBinding()]
param([string]$Python = 'python', [string]$VCToolsRoot, [string]$WindowsSdkRoot, [string]$Wix, [string]$Node)
$ErrorActionPreference = 'Stop'
$arguments = @((Join-Path $PSScriptRoot 'build.py'))
if ($VCToolsRoot) { $arguments += @('--msvc', $VCToolsRoot) }
if ($WindowsSdkRoot) { $arguments += @('--sdk', $WindowsSdkRoot) }
if ($Wix) { $arguments += @('--wix', $Wix) }
if ($Node) { $arguments += @('--node', $Node) }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw 'DownloadVersionManager release construction failed.' }
