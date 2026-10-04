[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$MsiPath, [string]$RollbackMsi, [string]$SmokeExe, [string]$Output, [string]$Python = 'python', [switch]$SkipRepair)
$ErrorActionPreference = 'Stop'
$arguments = @((Join-Path $PSScriptRoot 'test-watcher-installer.py'), 'run', '--msi', (Resolve-Path -LiteralPath $MsiPath).Path)
if ($RollbackMsi) { $arguments += @('--rollback-msi', (Resolve-Path -LiteralPath $RollbackMsi).Path) }
if ($SmokeExe) { $arguments += @('--smoke-exe', (Resolve-Path -LiteralPath $SmokeExe).Path) }
if ($Output) { $arguments += @('--output', $Output) }
if ($SkipRepair) { $arguments += '--skip-repair' }
& $Python @arguments
if ($LASTEXITCODE -ne 0) { throw 'Watcher installer verification did not pass; preserve and inspect the local result before retrying.' }
