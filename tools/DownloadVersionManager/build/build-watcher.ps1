[CmdletBinding()]
param([string]$Python = 'python', [string]$VCToolsRoot, [string]$WindowsSdkRoot, [string]$Wix, [string]$OutputDir, [switch]$Tests, [ValidateSet('engine','watcher','review')][string]$TestOnly, [switch]$RollbackTest)
$ErrorActionPreference = 'Stop'
$arguments = @((Join-Path $PSScriptRoot 'build-watcher.py'))
if ($VCToolsRoot) { $arguments += @('--msvc', $VCToolsRoot) }
if ($WindowsSdkRoot) { $arguments += @('--sdk', $WindowsSdkRoot) }
if ($Wix) { $arguments += @('--wix', $Wix) }
if ($OutputDir) { $arguments += @('--output-dir', $OutputDir) }
if ($Tests) { $arguments += '--tests' }
if ($TestOnly) { $arguments += @('--test-only', $TestOnly) }
if ($RollbackTest) { $arguments += '--rollback-test' }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw 'DownloadVersionManager watcher build failed.' }
