[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
# Actual HKCU operations in an isolated test branch, not Excel's settings.
# Import function ASTs only; never execute Setup's action dispatch in this harness.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tool=Split-Path -Parent $PSScriptRoot
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Use a fresh evidence directory.'}
[void](New-Item -ItemType Directory -Path $output)
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'Setup.ps1'),[ref]$null,[ref]$null)
foreach($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) { . ([scriptblock]::Create($function.Extent.Text)) }
$ProductId='SLC-68A45C44-2026';$Version='0.2.0';$InstallerVersion='0.2.0-rc.2';$ConfirmProduct=$ProductId
$Root=Join-Path $tool 'Release'
$sandbox='Software\SLC-Installer-Tests\'+[Guid]::NewGuid().ToString('N')
$RegistrySandbox=$sandbox+'\Excel'
function Excel-UserPath([string]$OfficeVersion){return $RegistrySandbox}
function Excel-RegistrationVersion{return '16.0'}
$checks=New-Object Collections.Generic.List[object]
$case=0
function Check([string]$Name,[bool]$Pass){$checks.Add([pscustomobject]@{name=$Name;status=if($Pass){'PASS'}else{'FAIL'}});if(-not $Pass){throw ('Failed: '+$Name)}}
function New-Case {
    $script:case++
    $script:RegistrySandbox=$sandbox+'\Case'+$case+'\Excel'
    $script:InstallDir=Join-Path $output ('case-'+$case)
    $script:Target=Join-Path $InstallDir 'ExcelSmartListCompare.xlam'
    $script:Manifest=Join-Path $InstallDir 'install.json'
}
function Read-Key([string]$Name){return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(((Trust-RootPath '16.0')+'\'+$Name),$true)}
function Key-Digest($Key){return (@($Key.GetValueNames() | Sort-Object | ForEach-Object {$_+'|'+$Key.GetValueKind($_)+'|'+$Key.GetValue($_)}) -join "`n")}
try {
    $policy=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(($sandbox+'\Policy'))
    try {
        Check 'Unconfigured trust policy allows registration' (-not(Test-TrustPolicyBlocked $policy))
        $policy.SetValue('alllocationsdisabled',1,[Microsoft.Win32.RegistryValueKind]::DWord)
        Check 'Disable-all policy detected' (Test-TrustPolicyBlocked $policy)
        $policy.DeleteValue('alllocationsdisabled')
        $policy.SetValue('allow user locations',0,[Microsoft.Win32.RegistryValueKind]::DWord)
        Check 'Policy-only locations detected using official ADMX value name' (Test-TrustPolicyBlocked $policy)
        $policy.SetValue('allow user locations',1,[Microsoft.Win32.RegistryValueKind]::DWord)
        Check 'Explicit allow policy recognized' (-not(Test-TrustPolicyBlocked $policy))
    } finally {$policy.Close()}
    New-Case
    Install-Addin
    $first=Read-OwnManifest
    $key=Read-Key $first.trustedLocation.keyName
    try{Check 'Fresh install trusts exact directory without subfolders' ((Test-OwnTrustKey $key $first.trustedLocation) -and $key.GetValue('AllowSubfolders') -eq 0)}finally{$key.Close()}
    Check 'Manifest separates product and Office versions' ($first.version -eq '0.2.0' -and $first.excelVersion -eq '16.0')
    Install-Addin
    $again=Read-OwnManifest
    Check 'Reinstall reuses same ownership token and key' ($again.trustedLocation.token -ceq $first.trustedLocation.token -and $again.trustedLocation.keyName -ceq $first.trustedLocation.keyName)
    Uninstall-Addin
    Check 'Remove prunes only newly created empty trust parents' ($null -eq [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(($RegistrySandbox+'\Security')) -and -not(Test-Path -LiteralPath $InstallDir))

    New-Case
    $parent=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey((Trust-RootPath '16.0'))
    $foreign=$parent.CreateSubKey('Location0');$foreign.SetValue('Path',($InstallDir+'\'));$foreign.SetValue('Description','Pre-existing user value');$foreign.SetValue('Extra',42)
    $before=Key-Digest $foreign
    Install-Addin
    $owner=Read-OwnManifest
    Check 'Pre-existing exact location is borrowed, never claimed' (-not $owner.trustedLocation.owned)
    Install-Addin
    Uninstall-Addin
    Check 'Pre-existing location and unknown metadata survive lifecycle' ((Key-Digest $foreign) -ceq $before -and $parent.SubKeyCount -eq 1)
    $foreign.Close();$parent.Close()

    foreach($change in @('Description','UnknownValue','ChildKey')) {
        New-Case;Install-Addin;$owner=Read-OwnManifest;$key=Read-Key $owner.trustedLocation.keyName
        switch($change){'Description'{$key.SetValue('Description','External edit')};'UnknownValue'{$key.SetValue('External',42)};'ChildKey'{$child=$key.CreateSubKey('External');$child.Close()}}
        $before=Key-Digest $key;$key.Close()
        $rejected=$false;try{Install-Addin}catch{$rejected=$true}
        Check ('Reinstall preserves externally changed '+$change) $rejected
        Uninstall-Addin;$key=Read-Key $owner.trustedLocation.keyName
        try{Check ('Removal preserves externally changed '+$change) ($null -ne $key -and (Key-Digest $key) -ceq $before)}finally{if($key){$key.Close()}}
    }

    New-Case
    $plan=Plan-TrustedLocation '16.0' $null
    $parent=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey((Trust-RootPath '16.0'))
    $foreign=$parent.CreateSubKey($plan.record.keyName);$foreign.SetValue('External',42);$before=Key-Digest $foreign
    $rejected=$false;try{Enable-TrustedLocation '16.0' $plan}catch{$rejected=$true}
    Check 'Concurrent key creation never overwrites or claims external key' ($rejected -and (Key-Digest $foreign) -ceq $before)
    $foreign.Close();$parent.Close()

    foreach($stage in @('Identity','BeforePath','Active')) {
        New-Case;$plan=Plan-TrustedLocation '16.0' $null
        $parent=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey((Trust-RootPath '16.0'))
        $key=New-ExclusiveRegistryKey $parent $plan.record.keyName
        $key.SetValue('SLCOwnerToken',$plan.record.token)
        if($stage -ne 'Identity') {foreach($name in (Trust-Values $plan.record).Keys){if($name -eq 'Path' -and $stage -eq 'BeforePath'){continue};$kind=if($name -eq 'AllowSubfolders'){'DWord'}else{'String'};$key.SetValue($name,(Trust-Values $plan.record)[$name],[Microsoft.Win32.RegistryValueKind]$kind)}}
        $key.Close();$parent.Close()
        Remove-OwnedTrustedLocation '16.0' $plan.record
        Check ('Interrupted activation removable at '+$stage) ($null -eq (Read-Key $plan.record.keyName))
    }

    New-Case
    $enable=(Get-Command Enable-TrustedLocation).ScriptBlock
    function Enable-TrustedLocation([string]$OfficeVersion,$Plan){& $enable $OfficeVersion $Plan;throw 'Synthetic failure after activation, before OPEN write.'}
    $rejected=$false;try{Install-Addin}catch{$rejected=$true}
    Check 'Failure after trust activation rolls back files and trust' ($rejected -and @(Get-ChildItem -LiteralPath $InstallDir -Force).Count -eq 0 -and $null -eq [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey((Trust-RootPath '16.0')))
    Set-Item -LiteralPath Function:Enable-TrustedLocation -Value $enable

    New-Case;Install-Addin;$owner=Read-OwnManifest
    Remove-OwnedTrustedLocation '16.0' $owner.trustedLocation
    $owner.PSObject.Properties.Remove('trustedLocation');$owner.PSObject.Properties.Remove('installerVersion')
    $owner | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Manifest -Encoding UTF8
    Install-Addin;$upgraded=Read-OwnManifest
    Check 'RC1 ownership record upgrades to RC2 trust' ($upgraded.trustedLocation.owned -and $upgraded.installerVersion -eq '0.2.0-rc.2')
    Uninstall-Addin

    New-Case;[void](New-Item -ItemType Directory -Path $InstallDir)
    Set-Content -LiteralPath (Join-Path $InstallDir 'business-sentinel.txt') -Value 'Synthetic only'
    $rejected=$false;try{Install-Addin}catch{$rejected=$true}
    Check 'New trust rejects unrelated files without reading their contents' ($rejected -and -not(Test-Path -LiteralPath $Manifest) -and $null -eq [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey((Trust-RootPath '16.0')))
} finally {
    $checks | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'checks.json') -Encoding UTF8
    # This unique branch was created by this harness. No actual Office keys live here.
    if($sandbox -notmatch '^Software\\SLC-Installer-Tests\\[a-f0-9]{32}$'){throw 'Unsafe test cleanup path'}
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($sandbox,$false)
}
$checks | Format-Table name,status -AutoSize
