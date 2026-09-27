[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$checks = 0
foreach ($name in @('probe-unsigned-identity.ps1', 'invoke-admin-probe.ps1', 'test-msi-context.ps1', 'build-msi-context-probe.ps1')) {
    $path = Join-Path $PSScriptRoot $name
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw ($errors | Out-String) }
    Write-Output "PASS syntax: $name"; $checks++
}
$probe = Join-Path $PSScriptRoot 'probe-unsigned-identity.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($probe, [ref]$tokens, [ref]$errors)
# Extract only the read-only registration/provisioning selector functions.
# Do not source the probe or invoke Appx, DISM, UAC, or clipboard operations.
foreach ($name in @('Get-ImageRegistrations', 'Get-ImageProvisioning')) {
    $node = $ast.Find({ param($item) $item -is [Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -eq $name }.GetNewClosure(), $true)
    if ($null -eq $node) { throw "Missing function: $name" }
    . ([scriptblock]::Create($node.Extent.Text))
}
$script:appxAllUsers = $false; $script:provisionCalls = 0
function Get-AppxPackage { param([switch]$AllUsers, [string]$Name, [string]$ErrorAction) $script:appxAllUsers = [bool]$AllUsers; [pscustomobject]@{ Name = 'ImageCopySave.Test' } }
function Get-ImageProvisioningInventory { $script:provisionCalls++; @([pscustomobject]@{ DisplayName = 'Unrelated.App' }, [pscustomobject]@{ DisplayName = 'ImageCopySave.Test' }) }
$RegistrationContext = 'OrdinaryUser'
$null = Get-ImageRegistrations
if ($script:appxAllUsers) { throw 'OrdinaryUser widened registration query.' }
Write-Output 'PASS ordinary query remains current-user'; $checks++
if (@(Get-ImageProvisioning).Count -ne 0 -or $script:provisionCalls -ne 0) { throw 'OrdinaryUser queried machine provisioning.' }
Write-Output 'PASS ordinary mode never calls provisioning'; $checks++
$RegistrationContext = 'Administrator'
$null = Get-ImageRegistrations
if (-not $script:appxAllUsers) { throw 'Admin omitted all-user registration query.' }
Write-Output 'PASS admin query includes all users'; $checks++
$entries = @(Get-ImageProvisioning)
if ($entries.Count -ne 1 -or $entries[0].DisplayName -ne 'ImageCopySave.Test' -or $script:provisionCalls -ne 1) { throw 'Admin provisioning filter failed.' }
Write-Output 'PASS admin provisioning selects only ImageCopySave'; $checks++
Write-Output "$checks checks passed; no OS registration/elevation invoked."
