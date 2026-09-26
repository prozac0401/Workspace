[CmdletBinding()]
param(
    [ValidateSet('Prepare','ResumeFileList','RemoveSelection','RemovePaste','RemoveFileList','Verify')][string]$Action='Prepare',
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [string]$SelectionInstaller,
    [string]$PasteInstaller,
    [string]$FileListInstaller
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=[IO.Path]::GetFullPath($EvidenceDirectory).TrimEnd('\')
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'artifacts'))+'\'
if(-not $root.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence must be inside repository artifacts.'}
if(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use ordinary user.'}
if(@(Get-Process EXCEL,FileListToExcel -ErrorAction SilentlyContinue).Count){throw 'Close Excel and helper normally before lifecycle actions.'}
$local=[Environment]::GetFolderPath('LocalApplicationData')
$products=[ordered]@{
    Selection=@{directory=(Join-Path $local 'Workspace\ExcelSelectionExport');id='Workspace.ExcelSelectionExport'}
    Paste=@{directory=(Join-Path $local 'VisibleCellsPaste');id='Workspace.VisibleCellsPaste'}
    FileList=@{directory=(Join-Path $local 'Programs\FileListToExcel');id='FileListToExcel.ExcelAddIn'}
}
$marker=Join-Path $root 'owned.json'
function Hash([string]$path){(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
function Save($value,[string]$name){$value|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $root $name) -Encoding UTF8}
function Tree($key,[string]$path,$lines){
    $lines.Add('KEY|'+$path)
    foreach($name in @($key.GetValueNames()|Sort-Object)){$lines.Add($path+'|'+$name+'|'+$key.GetValueKind($name)+'|'+(ConvertTo-Json -InputObject $key.GetValue($name,$null,'DoNotExpandEnvironmentNames') -Compress))}
    foreach($name in @($key.GetSubKeyNames()|Sort-Object)){
        if($path -eq 'Addins' -and $name -in @($products.Values|ForEach-Object{$_.id})){continue}
        $child=$key.OpenSubKey($name)
        try {Tree $child ($path+'\'+$name) $lines} finally {$child.Dispose()}
    }
}
function Safety {
    $values=[ordered]@{}
    foreach($hive in @('CurrentUser','LocalMachine')){foreach($view in @('Registry64','Registry32')){
        $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
        try {foreach($path in @('Software\Policies\Microsoft\Office','Software\Microsoft\Office\16.0\Excel\Security','Software\Microsoft\Office\16.0\Common\Security','Software\Microsoft\Office\Excel\Addins','Software\VB and VBA Program Settings\ExcelSmartListCompare')){
            $key=$base.OpenSubKey($path)
            if(-not $key){$values["$hive/$view/$path"]='ABSENT';continue}
            try {
                $lines=New-Object 'System.Collections.Generic.List[string]'
                Tree $key $(if($path.EndsWith('\Addins')){'Addins'}else{$path}) $lines
                $sha=[Security.Cryptography.SHA256]::Create()
                try {$values["$hive/$view/$path"]=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))))} finally {$sha.Dispose()}
            } finally {$key.Dispose()}
        }} finally {$base.Dispose()}
    }}
    foreach($file in @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md','install.json')){
        $path=Join-Path $local ('ExcelSmartListCompare\'+$file)
        $values['Roster/'+$file]=if(Test-Path -LiteralPath $path){Hash $path}else{'ABSENT'}
    }
    return $values
}
function Assert-Safety {
    $before=Get-Content -LiteralPath (Join-Path $root 'baseline.json') -Raw|ConvertFrom-Json
    $after=Safety
    Save $after ($Action+'-safety.json')
    foreach($name in $after.Keys){if($before.$name -cne $after[$name]){throw ('Unrelated state changed: '+$name)}}
}
function Payload([string]$name){
    $directory=$products[$name].directory
    $items=[ordered]@{}
    foreach($file in Get-ChildItem -LiteralPath $directory -File -Recurse -Force){$items[$file.FullName.Substring($directory.Length+1)]=Hash $file.FullName}
    return $items
}
function Run([string]$exe,[string[]]$arguments){
    # msiexec requires its switches as switches, not quoted application arguments.
    $msi=([IO.Path]::GetFileName($exe) -ieq 'msiexec.exe')
    $quoted=@($arguments|ForEach-Object{if($msi -and ($_.StartsWith('/') -or $_.StartsWith('ADDLOCAL='))){$_}else{'"'+$_+'"'}})
    $p=Start-Process -FilePath $exe -ArgumentList $quoted -WindowStyle Hidden -PassThru
    try {if(-not $p.WaitForExit(120000)){throw 'Installer still running; no forced termination.'};if($p.ExitCode -ne 0){throw ('Installer exit '+$p.ExitCode)}} finally {$p.Dispose()}
}
function Assert-Payload($owned,[string]$exclude=''){
    foreach($name in @('Selection','Paste','FileList')){
        if($name -eq $exclude -or -not $owned.$name){continue}
        $expected=Get-Content -LiteralPath (Join-Path $root ($name+'-payload.json')) -Raw|ConvertFrom-Json
        $actual=Payload $name
        if(@($expected.PSObject.Properties).Count -ne $actual.Count){throw 'Remaining payload inventory changed.'}
        foreach($file in $actual.Keys){if($expected.$file -ne $actual[$file]){throw ('Remaining payload changed: '+$name+'/'+$file)}}
        if((Get-ItemPropertyValue ('HKCU:\Software\Microsoft\Office\Excel\Addins\'+$products[$name].id) LoadBehavior) -ne 3){throw ('Remaining add-in autoload changed: '+$name)}
    }
}
function Install-FileList($owned){
    if((Hash $FileListInstaller) -ne '7690bab04bafd6d83bb1fb88c2fbf681204fb8f8a6b1f8993847ccd1a6933364'){throw 'File List package mismatch.'}
    if((Test-Path -LiteralPath $products.FileList.directory) -or (Test-Path ('HKCU:\Software\Microsoft\Office\Excel\Addins\'+$products.FileList.id))){throw 'File List installation exists; inspect before resuming.'}
    Run 'msiexec.exe' @('/i',$FileListInstaller,'ADDLOCAL=Complete,ExcelIntegration','/qn','/norestart','/l*v',(Join-Path $root 'filelist-install.log'))
    $owned.FileList=$true;Save $owned 'owned.json';Save (Payload 'FileList') 'FileList-payload.json';Assert-Safety
}
if($Action -eq 'Prepare'){
    if(Test-Path -LiteralPath $root){throw 'Use a fresh evidence directory.'}
    foreach($product in $products.Values){if((Test-Path -LiteralPath $product.directory) -or (Test-Path ('HKCU:\Software\Microsoft\Office\Excel\Addins\'+$product.id))){throw 'Existing target installation must be preserved.'}}
    if(-not(Test-Path -LiteralPath (Join-Path $local 'ExcelSmartListCompare\ExcelSmartListCompare.xlam'))){throw 'Existing roster add-in is required, not installed by this test.'}
    foreach($pair in @(@($SelectionInstaller,'9171be45330ce9af86ce7b5eb06614211e3620bd47893912b03dd6ff2829114a'),@($PasteInstaller,'bd55f32f3a9d467ed288696c8e80dd7f5e9eb97a280ba12a25fe622a5d26b464'),@($FileListInstaller,'7690bab04bafd6d83bb1fb88c2fbf681204fb8f8a6b1f8993847ccd1a6933364'))){if((Hash $pair[0]) -ne $pair[1]){throw 'Candidate package mismatch.'}}
    New-Item -ItemType Directory -Path $root|Out-Null
    Save (Safety) 'baseline.json'
    $owned=@{Selection=$false;Paste=$false;FileList=$false}
    Save $owned 'owned.json'
    Run $SelectionInstaller @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/LOG='+(Join-Path $root 'selection-install.log')))
    $owned.Selection=$true;Save $owned 'owned.json';Save (Payload 'Selection') 'Selection-payload.json';Assert-Safety
    Run $PasteInstaller @('--silent','--report',(Join-Path $root 'paste-install.log'))
    $owned.Paste=$true;Save $owned 'owned.json';Save (Payload 'Paste') 'Paste-payload.json';Assert-Safety
    Install-FileList $owned
    Assert-Payload ([pscustomobject]$owned)
} else {
    if(-not(Test-Path -LiteralPath $marker)){throw 'No owned installation marker.'}
    $owned=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
    Assert-Safety
    Assert-Payload $owned
    if($Action -eq 'ResumeFileList'){
        if(-not $owned.Selection -or -not $owned.Paste -or $owned.FileList){throw 'Unexpected resume state.'}
        Install-FileList $owned
        Assert-Payload $owned
    } elseif($Action -ne 'Verify'){
        $name=$Action.Substring(6)
        if(-not $owned.$name){throw 'Target was not installed by this fixture.'}
        if($name -eq 'Selection'){Run (Join-Path $products.Selection.directory 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/LOG='+(Join-Path $root 'selection-remove.log')))}
        elseif($name -eq 'Paste'){Run (Join-Path $products.Paste.directory 'launcher\VisibleCellsPaste.Setup.exe') @('--uninstall','--silent','--report',(Join-Path $root 'paste-remove.log'))}
        else {Run 'msiexec.exe' @('/x','{260CF167-E818-46E8-B4E9-14308B35B789}','/qn','/norestart','/l*v',(Join-Path $root 'filelist-remove.log'))}
        $deadline=[DateTime]::UtcNow.AddSeconds(15)
        while((Test-Path -LiteralPath $products[$name].directory) -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 200}
        if((Test-Path -LiteralPath $products[$name].directory) -or (Test-Path ('HKCU:\Software\Microsoft\Office\Excel\Addins\'+$products[$name].id))){throw 'Owned installation removal incomplete.'}
        $owned.$name=$false;Save $owned 'owned.json'
        Assert-Payload $owned;Assert-Safety
    }
}
Save @{status='passed';action=$Action;owned=$owned} ($Action+'-result.json')
