[CmdletBinding()]
param([string]$Path = '')
$ErrorActionPreference = 'Stop'
if (-not $Path) { $Path = Join-Path $PSScriptRoot '../test-msi-preservation.ps1' }
$tokens=$null; $errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $Path).Path,[ref]$tokens,[ref]$errors)
if ($errors.Count -gt 0) { $errors | ForEach-Object { Write-Output ($_.Extent.StartLineNumber.ToString() + ': ' + $_.Message) }; exit 1 }
Write-Output 'PASS: PowerShell parsed without executing the preservation harness.'
