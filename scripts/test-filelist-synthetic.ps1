[CmdletBinding()]
param(
    [ValidateSet('Prepare','Remove')][string]$Action='Prepare',
    [Parameter(Mandatory=$true)][string]$MsiPath,
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=[IO.Path]::GetFullPath($EvidenceDirectory).TrimEnd('\')
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'artifacts'))+'\'
if(-not $root.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence must be under repository artifacts.'}
$msi=(Resolve-Path -LiteralPath $MsiPath).Path
if((Get-FileHash -LiteralPath $msi).Hash -ne '7690bab04bafd6d83bb1fb88c2fbf681204fb8f8a6b1f8993847ccd1a6933364'){throw 'Expected exact public File List 1.2.0 MSI.'}
if(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use an ordinary user.'}
if(@(Get-Process EXCEL,FileListToExcel -ErrorAction SilentlyContinue).Count){throw 'Close existing Excel/helper processes normally before testing.'}
$install=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs/FileListToExcel'
$key='HKCU:\Software\FileListToExcel'
$addin='HKCU:\Software\Microsoft\Office\Excel\Addins\FileListToExcel.ExcelAddIn'
$marker=Join-Path $root 'owned-install.json'
function Products {
    $api=New-Object -ComObject WindowsInstaller.Installer
    try { foreach($code in $api.RelatedProducts('{138C25B0-CA8D-47D7-AE96-8B5F7B2D69A1}')){[pscustomobject]@{code=$code;version=$api.ProductInfo($code,'VersionString')}} }
    finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($api)}
}
function Run-Msi([string]$stage,[string[]]$arguments){
    $p=Start-Process msiexec.exe -ArgumentList ($arguments+@('/qn','/norestart','/l*v',('"'+(Join-Path $root ($stage+'.log'))+'"'))) -WindowStyle Hidden -PassThru -Wait
    if($p.ExitCode -ne 0){throw "$stage exited $($p.ExitCode)"}
}
if($Action -eq 'Prepare'){
    if((Test-Path $root) -or (Test-Path $install) -or (Test-Path $key) -or (Test-Path $addin) -or @(Products).Count){throw 'Evidence or product already exists; stop before changes.'}
    foreach($view in @([Microsoft.Win32.RegistryView]::Registry32,[Microsoft.Win32.RegistryView]::Registry64)){
        $user=[Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser',$view)
        try { foreach($id in @('{AF7A7218-8B84-4A11-9790-EB24A43EC39E}','{0B1E297C-42CC-48A4-A973-3AA8EAF26795}')){
            $entry=$user.OpenSubKey('Software\Classes\CLSID\'+$id)
            if($entry){$entry.Dispose();throw 'Existing product COM registration.'}
        }} finally {$user.Dispose()}
    }
    New-Item -ItemType Directory -Path $root | Out-Null
    Run-Msi 'install' @('/i',('"'+$msi+'"'),'ADDLOCAL=Complete,ExcelIntegration')
    $products=@(Products)
    if($products.Count -ne 1 -or $products[0].version -ne '1.2.0'){throw 'Expected one installed 1.2.0 product.'}
    @{productCode=$products[0].code;install=$install;msiSha256=(Get-FileHash -LiteralPath $msi).Hash}|ConvertTo-Json|Set-Content -LiteralPath $marker -Encoding UTF8
    if((Get-ItemPropertyValue $addin 'LoadBehavior') -ne 3){throw 'Optional Excel component not configured for normal startup.'}
    $fixtureInput=Join-Path $root 'input'
    $output=Join-Path $root 'output'
    foreach($folder in @($fixtureInput,$output,(Join-Path $root 'copied'),(Join-Path $fixtureInput 'A 폴더'),(Join-Path $fixtureInput 'B 폴더'),(Join-Path $fixtureInput '빈 폴더'))){New-Item -ItemType Directory -Path $folder | Out-Null}
    $contents=[ordered]@{
        '보고서 한글.txt'='Synthetic Korean file.'
        '빈 파일.txt'=''
        '확장자없음'='No extension.'
        '=1+1.txt'='Literal formula-shaped file name.'
        '같은내용 원본.txt'='Identical synthetic content.'
        '숨김 항목.txt'='Hidden synthetic file.'
        '읽기전용.txt'='Read-only synthetic file.'
        'A 폴더/중복 이름.txt'='Collision A.'
        'B 폴더/중복 이름.txt'='Collision B.'
        'A 폴더/이름 다른 복제.bin'='Identical synthetic content.'
    }
    foreach($relative in $contents.Keys){[IO.File]::WriteAllText((Join-Path $fixtureInput $relative),$contents[$relative],[Text.UTF8Encoding]::new($false))}
    [IO.File]::SetAttributes((Join-Path $fixtureInput '숨김 항목.txt'),[IO.FileAttributes]::Hidden)
    [IO.File]::SetAttributes((Join-Path $fixtureInput '읽기전용.txt'),[IO.FileAttributes]::ReadOnly)
    $manifest=foreach($entry in Get-ChildItem -LiteralPath $fixtureInput -Recurse -Force){
        $entry.Refresh()
        [pscustomobject]@{path=$entry.FullName;relative=$entry.FullName.Substring($fixtureInput.Length+1);directory=$entry.PSIsContainer;bytes=if($entry.PSIsContainer){$null}else{$entry.Length};sha256=if($entry.PSIsContainer){$null}else{(Get-FileHash -LiteralPath $entry.FullName).Hash};attributes=[string]$entry.Attributes;modifiedUtcTicks=[string]$entry.LastWriteTimeUtc.Ticks}
    }
    $manifest|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $root 'source-manifest.json') -Encoding UTF8
    $helper=Join-Path $install 'FileListToExcel.exe'
    $cases=@(
        @{name='direct';arguments=@('--folder',$fixtureInput)},
        @{name='recursive';arguments=@('--recursive',$fixtureInput)},
        @{name='selected';arguments=@('--files',(Join-Path $fixtureInput '보고서 한글.txt'),(Join-Path $fixtureInput '=1+1.txt'))},
        @{name='empty';arguments=@('--folder',(Join-Path $fixtureInput '빈 폴더'))},
        @{name='duplicates';arguments=@('--duplicates',$fixtureInput,'--no-cache')},
        @{name='matches';arguments=@('--matches',(Join-Path $fixtureInput '같은내용 원본.txt'),'--no-cache')}
    )
    $results=@()
    foreach($case in $cases){
        $xlsx=Join-Path $output ($case.name+'.xlsx')
        $arguments=@($case.arguments)+@('--no-open','--output',$xlsx)
        $quoted=@($arguments|ForEach-Object{'"'+$_+'"'})
        $p=Start-Process -FilePath $helper -ArgumentList $quoted -WindowStyle Hidden -PassThru -Wait
        if($p.ExitCode -ne 0 -or -not(Test-Path -LiteralPath $xlsx)){throw ('Fixture generation failed: '+$case.name)}
        $results+=@{case=$case.name;exitCode=$p.ExitCode;output=$xlsx;sha256=(Get-FileHash -LiteralPath $xlsx).Hash}
    }
    $results|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $root 'generation.json') -Encoding UTF8
    Write-Output $root
} else {
    if(-not(Test-Path -LiteralPath $marker)){throw 'No owned installation marker.'}
    $owned=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
    $products=@(Products)
    if($owned.install -ne $install -or $products.Count -ne 1 -or $products[0].code -ne $owned.productCode){throw 'Installed product no longer matches owned fixture.'}
    Run-Msi 'remove' @('/x',$owned.productCode)
    if(@(Products).Count -or (Test-Path $install) -or (Test-Path $key) -or (Test-Path $addin)){throw 'Product removal left installation state.'}
    @{removed=$true;retainedFixtures=$true}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'removal.json') -Encoding UTF8
}
