[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [string]$ExpectedPublisher,
    [switch]$RequireTrustedSignature,
    [string]$SignTool
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'package-common.ps1')
$package = Get-ImageCopySavePackage $PackagePath $ExpectedPublisher
if ($RequireTrustedSignature) { Assert-ImageCopySaveTrustedSignature $package $SignTool }
$package | Add-Member -NotePropertyName SignatureVerification -NotePropertyValue $(if ($RequireTrustedSignature) { 'PASS' } else { 'NOT RUN' })
$package | Add-Member -NotePropertyName Installation -NotePropertyValue 'NOT RUN'
$package | Add-Member -NotePropertyName ExplorerG0 -NotePropertyValue 'NOT RUN'
$package
