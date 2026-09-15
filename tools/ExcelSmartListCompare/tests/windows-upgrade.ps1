[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
# Real file/registry transactions with synthetic packages in an isolated HKCU branch.
# No Excel process or actual Office registration is used by this harness.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$tool=Split-Path -Parent $PSScriptRoot
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Use a fresh evidence directory.'}
[void](New-Item -ItemType Directory -Path $output)
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $tool 'Setup.ps1'),[ref]$null,[ref]$null)
foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($f.Extent.Text))}
$ProductId='SLC-68A45C44-2026';$Version='0.2.0';$ConfirmProduct=$ProductId
$sandbox='Software\SLC-Upgrade-Tests\'+[Guid]::NewGuid().ToString('N')
$case=0;$checks=New-Object Collections.Generic.List[object]
$write=(Get-Command Write-InstallFile).ScriptBlock
$remove=(Get-Command Remove-PreviousVersion).ScriptBlock
$enable=(Get-Command Enable-TrustedLocation).ScriptBlock
function Excel-UserPath([string]$OfficeVersion){return $RegistrySandbox}
function Excel-RegistrationVersion{return '16.0'}
function Check([string]$Name,[bool]$Pass){$checks.Add([pscustomobject]@{name=$Name;status=$(if($Pass){'PASS'}else{'FAIL'})});if(-not $Pass){throw ('Failed: '+$Name)}}
function Set-Package([string]$Release){
    $script:InstallerVersion=$Release
    $script:Root=Join-Path $output ('package-'+$Release)
    if(-not(Test-Path -LiteralPath $Root)){
        [void](New-Item -ItemType Directory -Path $Root)
        foreach($name in @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md')){[IO.File]::WriteAllText((Join-Path $Root $name),('Synthetic '+$Release+' '+$name))}
    }
}
function New-Case {
    $script:case++
    $script:RegistrySandbox=$sandbox+'\Case'+$case+'\Excel'
    $script:InstallDir=Join-Path $output ('설치 경로 '+$case)
    $script:Target=Join-Path $InstallDir 'ExcelSmartListCompare.xlam'
    $script:Manifest=Join-Path $InstallDir 'install.json'
    Set-Package '0.2.0-rc.5'
    Install-Addin
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(($RegistrySandbox+'\Options'),$true)
    try{$key.SetValue('OPEN99',('"'+$Target+'"'));$key.SetValue('OPEN100','C:\SyntheticOther\Other.xlam')}finally{$key.Close()}
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(($RegistrySandbox+'\Add-in Manager'))
    try{$key.SetValue($Target,'');$key.SetValue('C:\SyntheticOther\Other.xlam','Other',[Microsoft.Win32.RegistryValueKind]::String)}finally{$key.Close()}
    [IO.File]::WriteAllText((Join-Path $InstallDir 'user-note.txt'),'Synthetic preserved extra')
    Set-Package '0.2.0-rc.6'
}
function Registry-Digest([string]$Path){
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path)
    if($null -eq $key){return '<absent>'}
    try {
        $values=@($key.GetValueNames()|Sort-Object|ForEach-Object {$_+'|'+$key.GetValueKind($_)+'|'+$key.GetValue($_,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)})
        foreach($child in @($key.GetSubKeyNames()|Sort-Object)){$values+=($child+'{'+(Registry-Digest ($Path+'\'+$child))+'}')}
        return ($values -join "`n")
    }finally{$key.Close()}
}
function Snapshot {
    $files=[ordered]@{}
    foreach($name in @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md','install.json','user-note.txt')){
        $file=Join-Path $InstallDir $name
        $files[$name]=$(if(Test-Path -LiteralPath $file){File-Sha256 $file}else{'<absent>'})
    }
    return ([ordered]@{files=$files;registry=(Registry-Digest $RegistrySandbox)}|ConvertTo-Json -Depth 8 -Compress)
}
function Expect-UnchangedFailure([string]$Name){
    $before=Snapshot;$failed=$false
    try{Install-Addin}catch{$failed=$true}
    Check $Name ($failed -and (Snapshot) -ceq $before -and @(Get-ChildItem -LiteralPath $InstallDir -Filter 'slc-install-*').Count -eq 0)
}
try {
    New-Case
    $old=Read-OwnManifest
    $script:observedRemoval=$false
    function Write-InstallFile([string]$Path,[byte[]]$Bytes,[string]$ExpectedHash){
        if(-not $script:observedRemoval){
            $remaining=@('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md')|Where-Object {Test-Path -LiteralPath (Join-Path $InstallDir $_)}
            $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(($RegistrySandbox+'\Options'))
            try{$openCount=(Own-OpenEntries $key).Count}finally{$key.Close()}
            $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(($RegistrySandbox+'\Add-in Manager'))
            try{$managerRemoved=$key.GetValueNames() -notcontains $Target}finally{$key.Close()}
            Check 'Old payload and product registrations removed before first new file write' (@($remaining).Count -eq 0 -and $openCount -eq 0 -and $managerRemoved)
            Check 'Ownership marker retained until replacement' ((Read-OwnManifest).installerVersion -eq '0.2.0-rc.5')
            $script:observedRemoval=$true
        }
        & $write $Path $Bytes $ExpectedHash
    }
    try{Install-Addin}finally{Set-Item Function:Write-InstallFile -Value $write}
    $next=Read-OwnManifest
    Check 'Upgrade commits new version and exact new payload' ($observedRemoval -and $next.installerVersion -eq '0.2.0-rc.6' -and (File-Sha256 $Target) -eq (File-Sha256 (Join-Path $Root 'ExcelSmartListCompare.xlam')))
    Check 'Upgrade reuses product trust identity' ($next.trustedLocation.token -ceq $old.trustedLocation.token)
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(($RegistrySandbox+'\Options'))
    try{Check 'Upgrade registers exactly one loader and preserves other add-in' ((Own-OpenEntries $key).Count -eq 1 -and $key.GetValue('OPEN100') -ceq 'C:\SyntheticOther\Other.xlam')}finally{$key.Close()}
    Check 'Upgrade preserves additional file' ([IO.File]::ReadAllText((Join-Path $InstallDir 'user-note.txt')) -ceq 'Synthetic preserved extra')
    function Remove-PreviousVersion{throw 'Repair must not remove a previous version.'}
    try{Install-Addin;Check 'Same version repair succeeds without upgrade removal' ((Read-OwnManifest).installerVersion -eq '0.2.0-rc.6')}finally{Set-Item Function:Remove-PreviousVersion -Value $remove}
    Uninstall-Addin
    Check 'Uninstall after upgrade removes owned files and preserves extra' (-not(Test-Path -LiteralPath $Manifest) -and -not(Test-Path -LiteralPath $Target) -and (Test-Path -LiteralPath (Join-Path $InstallDir 'user-note.txt')))

    foreach($stage in @('BeforePayload','MidPayload','AfterManifest')){
        New-Case;$script:writes=0
        function Write-InstallFile([string]$Path,[byte[]]$Bytes,[string]$ExpectedHash){
            $script:writes++
            if(($stage -eq 'BeforePayload' -and $writes -eq 1) -or ($stage -eq 'MidPayload' -and $writes -eq 3)){throw ('Injected '+$stage)}
            & $write $Path $Bytes $ExpectedHash
        }
        function Enable-TrustedLocation([string]$OfficeVersion,$Plan){& $enable $OfficeVersion $Plan;if($stage -eq 'AfterManifest'){throw 'Injected after manifest commit'}}
        try{Expect-UnchangedFailure ('Upgrade rollback restores exact files and registry at '+$stage)}finally{Set-Item Function:Write-InstallFile -Value $write;Set-Item Function:Enable-TrustedLocation -Value $enable}
    }
    foreach($file in @('ExcelSmartListCompare.xlam','install.json')){
        New-Case
        $stream=[IO.File]::Open((Join-Path $InstallDir $file),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try{Expect-UnchangedFailure ('Locked '+$file+' preserves previous installation')}finally{$stream.Dispose()}
    }
    New-Case
    $Root=Join-Path $output 'incomplete-package';[void](New-Item -ItemType Directory -Path $Root)
    [IO.File]::WriteAllText((Join-Path $Root 'ExcelSmartListCompare.xlam'),'Incomplete synthetic package')
    Expect-UnchangedFailure 'Incomplete package rejected before removal'

    foreach($versionText in @('0.2.0-rc.10','0.2.0','0.3.0-rc.1','future-format')){
        New-Case;$owner=Read-OwnManifest;$owner.installerVersion=$versionText
        [IO.File]::WriteAllText($Manifest,($owner|ConvertTo-Json -Depth 8))
        Expect-UnchangedFailure ('Newer or unknown '+$versionText+' preserved')
    }
    New-Case;$owner=Read-OwnManifest
    Remove-OwnedTrustedLocation '16.0' $owner.trustedLocation
    $owner.PSObject.Properties.Remove('trustedLocation');$owner.PSObject.Properties.Remove('installerVersion')
    [IO.File]::WriteAllText($Manifest,($owner|ConvertTo-Json -Depth 8))
    Remove-Item -LiteralPath (Join-Path $InstallDir 'user-note.txt')
    Install-Addin
    Check 'Legacy RC1 marker upgrades and creates owned trust' ((Read-OwnManifest).installerVersion -eq '0.2.0-rc.6' -and (Read-OwnManifest).trustedLocation.owned)

    New-Case
    function Write-InstallFile([string]$Path,[byte[]]$Bytes,[string]$ExpectedHash){[IO.File]::WriteAllText((Join-Path $InstallDir 'README.md'),'Concurrent external change');throw 'Injected external file'}
    try{$failed=$false;try{Install-Addin}catch{$failed=$true};Check 'Rollback preserves concurrent external file' ($failed -and [IO.File]::ReadAllText((Join-Path $InstallDir 'README.md')) -ceq 'Concurrent external change' -and (Read-OwnManifest).installerVersion -eq '0.2.0-rc.5')}finally{Set-Item Function:Write-InstallFile -Value $write}

    New-Case;$owner=Read-OwnManifest
    function Enable-TrustedLocation([string]$OfficeVersion,$Plan){
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(($RegistrySandbox+'\Options'),$true)
        try{$key.SetValue($owner.openValueName,'C:\Concurrent\External.xlam')}finally{$key.Close()}
        throw 'Injected concurrent OPEN value'
    }
    try{
        $failed=$false;try{Install-Addin}catch{$failed=$true}
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(($RegistrySandbox+'\Options'))
        try{Check 'Rollback preserves concurrent external registration' ($failed -and $key.GetValue($owner.openValueName) -ceq 'C:\Concurrent\External.xlam' -and (Read-OwnManifest).installerVersion -eq '0.2.0-rc.5')}finally{$key.Close()}
    }finally{Set-Item Function:Enable-TrustedLocation -Value $enable}

    foreach($partial in @(0,2)){
        New-Case;$backup=@{}
        foreach($name in @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md','install.json')){$backup[$name]=[IO.File]::ReadAllBytes((Join-Path $InstallDir $name))}
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(($RegistrySandbox+'\Options'),$true)
        try{Remove-PreviousVersion $key (Own-OpenEntries $key) $null $null $backup}finally{$key.Close()}
        if($partial -eq 2){foreach($name in @('ExcelSmartListCompare.xlam','Setup.ps1')){[IO.File]::WriteAllBytes((Join-Path $InstallDir $name),[IO.File]::ReadAllBytes((Join-Path $Root $name)))}}
        Install-Addin
        Check ('Restart from interrupted upgrade fixture with '+$partial+' new files') ((Read-OwnManifest).installerVersion -eq '0.2.0-rc.6' -and (File-Sha256 $Target) -eq (File-Sha256 (Join-Path $Root 'ExcelSmartListCompare.xlam')))
    }
}finally{
    $checks|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $output 'checks.json') -Encoding UTF8
    if($sandbox -notmatch '^Software\\SLC-Upgrade-Tests\\[a-f0-9]{32}$'){throw 'Unsafe registry cleanup path'}
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($sandbox,$false)
}
$checks|Format-Table name,status -AutoSize
