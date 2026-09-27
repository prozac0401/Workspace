[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$harness=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../test-msi-preservation.ps1')).Path
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Harness must parse before registry fixture tests.'}
$names=@('Get-RegistrySnapshot','Remove-ExactRegistryValue','Remove-EmptyKey','Invoke-FreshRegistryFixture')
$definitions=$ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)
foreach($name in $names){$match=@($definitions|Where-Object{$_.Name -eq $name});if($match.Count -ne 1){throw 'Expected one fixture helper definition.'};. ([ScriptBlock]::Create($match[0].Extent.Text))}
$realSnapshot=(Get-Item Function:Get-RegistrySnapshot).ScriptBlock
$simulateReadbackFailure=$false;$snapshotCalls=0
function Get-RegistrySnapshot([Microsoft.Win32.RegistryKey]$Base,[string]$Path){
    $script:snapshotCalls++
    if($script:simulateReadbackFailure -and $script:snapshotCalls -eq 2){return '<absent>'}
    return (& $script:realSnapshot $Base $Path)
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$user=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
$fixtureName='Fixture_'+[Guid]::NewGuid().ToString('N')
$fixtureText='Synthetic registry fixture test'
$externalName='External_'+[Guid]::NewGuid().ToString('N')
$externalText='Synthetic external change; preserve'
$parent='Software\Classes\ImageCopySave.PreservationFixtureTests.'+[Guid]::NewGuid().ToString('N')
$paths=@();$tests=New-Object Collections.Generic.List[string]
$result=[ordered]@{}
$journalPhases=New-Object Collections.Generic.List[string]
function Write-Result{if($result.Contains('activeFixture')){$journalPhases.Add($result.activeFixture.phase)}}
function Assert-Absent([string]$Path){$key=$user.OpenSubKey($Path);if($key){$key.Dispose();throw 'Exact synthetic fixture key was not cleaned.'}}
function Test-PathName([string]$Suffix){return $parent+'.'+$Suffix}
try{
    # Fail exactly the diagnostic read-back after the value has been created.
    $path=Test-PathName 'readback';$paths+=$path
    $simulateReadbackFailure=$true;$snapshotCalls=0;$called=$false;$caught=$null
    try{Invoke-FreshRegistryFixture $user 'HKCU' $path {$script:called=$true}}catch{$caught=$_.Exception.Message}
    $simulateReadbackFailure=$false
    if(-not $caught -or $caught -notmatch 'fixture was not created' -or $called){throw 'Read-back failure did not stop before the installer callback.'}
    Assert-Absent $path
    if($journalPhases -notcontains 'CREATED' -or $result.activeFixture.phase -ne 'EXACT_FIXTURE_CLEANED'){throw 'Fixture ownership was not journaled before failing read-back.'}
    $tests.Add('created fixture is journaled and cleaned when diagnostic read-back fails')
    $path=Test-PathName 'callback';$paths+=$path;$caught=$null
    try{Invoke-FreshRegistryFixture $user 'HKCU' $path {throw 'Synthetic MSI callback failure'}}catch{$caught=$_.Exception.Message}
    if($caught -notmatch 'Synthetic MSI callback failure'){throw 'Expected callback failure was not observed.'}
    Assert-Absent $path
    $tests.Add('verified HKCU/Classes fixture is cleaned when the installer callback fails')
    $path=Test-PathName 'other-value';$paths+=$path;$caught=$null
    try{Invoke-FreshRegistryFixture $user 'HKCU' $path {$key=$user.OpenSubKey($path,$true);try{$key.SetValue($externalName,$externalText,[Microsoft.Win32.RegistryValueKind]::String)}finally{$key.Dispose()};throw 'Synthetic external-value failure'}}catch{$caught=$_.Exception.Message}
    if($caught -notmatch 'Synthetic external-value failure'){throw 'Expected external-value test failure was not observed.'}
    $key=$user.OpenSubKey($path)
    try{if($key.GetValueNames() -contains $fixtureName -or $key.GetValue($externalName) -ne $externalText -or $key.ValueCount -ne 1){throw 'Fixture cleanup changed an externally added value.'}}finally{$key.Dispose()}
    $tests.Add('cleanup removes only the owned value and preserves an externally added value')
    $path=Test-PathName 'changed-value';$paths+=$path;$caught=$null
    try{Invoke-FreshRegistryFixture $user 'HKCU' $path {$key=$user.OpenSubKey($path,$true);try{$key.SetValue($fixtureName,$externalText,[Microsoft.Win32.RegistryValueKind]::String)}finally{$key.Dispose()};throw 'Synthetic changed-value failure'}}catch{$caught=$_.Exception.Message}
    $key=$user.OpenSubKey($path)
    try{if(-not $caught -or $key.GetValue($fixtureName) -ne $externalText -or $result.activeFixture.phase -ne 'PRESERVED_FOR_REVIEW'){throw 'Externally changed fixture was not retained for review.'}}finally{$key.Dispose()}
    $tests.Add('externally modified fixture value is preserved and journaled for review')
}finally{
    # All values below were created by this test under unique non-product roots.
    # Even test teardown removes only an exact known value and an empty key.
    foreach($path in $paths){
        $key=$user.OpenSubKey($path)
        if(-not $key){continue}
        try{$values=@($key.GetValueNames());$expected=@{};foreach($name in $values){$value=$key.GetValue($name);if($key.GetValueKind($name) -ne [Microsoft.Win32.RegistryValueKind]::String -or $name -notin @($fixtureName,$externalName) -or $value -notin @($fixtureText,$externalText)){throw 'Unexpected registry change in test teardown; preserved for review.'};$expected[$name]=$value}}finally{$key.Dispose()}
        foreach($name in $expected.Keys){Remove-ExactRegistryValue $user $path $name $expected[$name]}
        Remove-EmptyKey $user $path
    }
    $user.Dispose()
}
[ordered]@{status='PASS';count=$tests.Count;tests=$tests;msiInvoked=$false;productRegistryChanged=$false;syntheticRegistryFixturesCleaned=$true}|ConvertTo-Json -Depth 5
