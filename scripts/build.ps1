[CmdletBinding()]
param([string]$Version = '0.1.3', [switch]$SkipTests)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must contain three numeric components.' }
$parts = $Version.Split('.') | ForEach-Object { [int]$_ }
if ($parts[0] -gt 255 -or $parts[1] -gt 255 -or $parts[2] -gt 65535) { throw 'Version exceeds MSI limits.' }
function Invoke-Dotnet([string[]]$Arguments) {
    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) { throw "dotnet failed with exit code $LASTEXITCODE" }
}
if (-not $SkipTests) {
    Invoke-Dotnet @('run','--project','tests/FolderState.Tests','-c','Release')
    Invoke-Dotnet @('build','tests/FolderState.UiSmoke','-c','Release')
    Invoke-Dotnet @('tests/FolderState.UiSmoke/bin/Release/net10.0-windows/FolderState.UiSmoke.dll','artifacts/ui-preview.png','900','780','verify')
}
$publish = Join-Path $repoRoot 'artifacts/publish'
$release = Join-Path $repoRoot 'artifacts/release'
if (Test-Path -LiteralPath $publish) {
    $resolved = [IO.Path]::GetFullPath($publish)
    if ($resolved -ne [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts/publish'))) { throw 'Unexpected publish directory.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
New-Item -ItemType Directory -Path $publish,$release -Force | Out-Null
foreach ($project in @('FolderState.App','FolderState.Cli')) {
    Invoke-Dotnet @('publish',"src/$project",'-c','Release','-r','win-x64','--self-contained','true','-o',$publish,"-p:Version=$Version",'-p:DebugType=none','-p:DebugSymbols=false')
}
Copy-Item -LiteralPath (Join-Path $repoRoot 'docs/assets/help.html') -Destination (Join-Path $publish 'help.html')
Copy-Item -LiteralPath (Join-Path $repoRoot 'THIRD-PARTY-NOTICES.md') -Destination $publish
$assets = Get-Content -LiteralPath (Join-Path $repoRoot 'src/FolderState.App/obj/project.assets.json') -Raw | ConvertFrom-Json
$packageRoot = @($assets.packageFolders.PSObject.Properties)[0].Name
$licenseDirectory = Join-Path $publish 'licenses'
New-Item -ItemType Directory -Path $licenseDirectory -Force | Out-Null
$runtimeConfig = Get-Content -LiteralPath (Join-Path $publish 'FolderState.runtimeconfig.json') -Raw | ConvertFrom-Json
foreach ($framework in $runtimeConfig.runtimeOptions.includedFrameworks) {
    $packageId = $framework.name.ToLowerInvariant() + '.runtime.win-x64'
    $relativePackage = $packageId + '/' + $framework.version
    $source = $null
    foreach ($folder in $assets.packageFolders.PSObject.Properties) {
        $candidate = Join-Path $folder.Name $relativePackage
        if (Test-Path -LiteralPath $candidate) { $source = $candidate; break }
    }
    if (-not $source) { throw "Runtime package not found: $relativePackage" }
    foreach ($notice in @('LICENSE','LICENSE.TXT','THIRD-PARTY-NOTICES.TXT')) {
        $noticePath = Join-Path $source $notice
        if (Test-Path -LiteralPath $noticePath) {
            $targetName = $framework.name + '-' + $framework.version + '-' + $notice
            Copy-Item -LiteralPath $noticePath -Destination (Join-Path $licenseDirectory $targetName)
        }
    }
}
if (@(Get-ChildItem -LiteralPath $licenseDirectory -File).Count -lt 3) { throw 'Runtime license notices are missing.' }
Invoke-Dotnet @('tool','restore')
# Generate deterministic IDs for the fixed application payload. Never enumerate business folders.
$wixNamespace = 'http://wixtoolset.org/schemas/v4/wxs'
$xml = [xml]"<Wix xmlns='$wixNamespace'><Fragment><DirectoryRef Id='INSTALLFOLDER'/><ComponentGroup Id='ApplicationFiles'/><ComponentGroup Id='StatusMenuCommands'/></Fragment></Wix>"
$dirNodes = @{ '' = $xml.Wix.Fragment.DirectoryRef }
$directories = Get-ChildItem -LiteralPath $publish -Directory -Recurse | Sort-Object FullName
$sha = [Security.Cryptography.SHA256]::Create()
function Id-For([string]$text) { return 'I' + ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','').Substring(0,30)) }
function Guid-For([string]$text) { $hex = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','').Substring(0,32); return ([guid]::ParseExact($hex,'N')).ToString('B') }
function Element([string]$name, [hashtable]$attributes) {
    $element = $xml.CreateElement($name,$wixNamespace)
    foreach ($key in $attributes.Keys) { $element.SetAttribute($key,[string]$attributes[$key]) }
    return ,$element
}
foreach ($dir in $directories) {
    $relative = $dir.FullName.Substring($publish.Length + 1)
    $parent = [IO.Path]::GetDirectoryName($relative)
    if ($null -eq $parent) { $parent = '' }
    $node = Element 'Directory' @{Id=(Id-For "dir/$relative");Name=$dir.Name}
    [void]$dirNodes[$parent].AppendChild($node); $dirNodes[$relative] = $node
}
foreach ($file in (Get-ChildItem -LiteralPath $publish -File -Recurse | Sort-Object FullName)) {
    $relative = $file.FullName.Substring($publish.Length + 1)
    $parent = [IO.Path]::GetDirectoryName($relative)
    if ($null -eq $parent) { $parent = '' }
    $id = Id-For "file/$relative"
    $component = Element 'Component' @{Id=$id;Guid=(Guid-For "file/$relative")}
    [void]$component.AppendChild((Element 'File' @{Id="F$id";Source=$file.FullName;Name=$file.Name}))
    [void]$component.AppendChild((Element 'RegistryValue' @{Root='HKCU';Key='Software\Workspace\FolderState\Components';Name=$id;Type='integer';Value='1';KeyPath='yes'}))
    if ($parent -ne '') { [void]$component.AppendChild((Element 'RemoveFolder' @{Id="R$id";On='uninstall'})) }
    [void]$dirNodes[$parent].AppendChild($component)
    [void]$xml.Wix.Fragment.ComponentGroup[0].AppendChild((Element 'ComponentRef' @{Id=$id}))
}
$menu = @(@('01Todo','시작 전','set todo','todo'),@('02Doing','진행 중','set doing','doing'),@('03Done','완료','set done','done'),@('04Issue','확인 필요','set issue','issue'),@('05Reset','상태 표시 지우기','reset','app'),@('06Repair','아이콘 다시 표시','repair','app'))
foreach ($item in $menu) {
    $component = Element 'Component' @{Id="Menu$($item[0])";Guid='*';Directory='INSTALLFOLDER'}
    $key = "Software\Classes\Directory\shell\Workspace.FolderState\shell\$($item[0])"
    [void]$component.AppendChild((Element 'RegistryValue' @{Root='HKCU';Key=$key;Name='MUIVerb';Value=$item[1];Type='string';KeyPath='yes'}))
    [void]$component.AppendChild((Element 'RegistryValue' @{Root='HKCU';Key=$key;Name='Icon';Value="[INSTALLFOLDER]icons\$($item[3]).ico";Type='string'}))
    [void]$component.AppendChild((Element 'RegistryValue' @{Root='HKCU';Key=$key;Name='MultiSelectModel';Value='Single';Type='string'}))
    [void]$component.AppendChild((Element 'RegistryValue' @{Root='HKCU';Key="$key\command";Value=('"[INSTALLFOLDER]FolderState.exe" ' + $item[2] + ' "%1"');Type='string'}))
    [void]$xml.Wix.Fragment.ComponentGroup[1].AppendChild($component)
}
$payload = Join-Path $repoRoot 'artifacts/Files.wxs'
$xml.Save($payload)
$msi = Join-Path $release "FolderState-$Version-win-x64.msi"
Invoke-Dotnet @('tool','run','wix','--','build','installer/Package.wxs',$payload,'-arch','x64','-d',"Version=$Version",'-d',"SourceRoot=$repoRoot",'-cabcache','artifacts/cabcache','-pdbtype','none','-o',$msi)
$hash = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$msi.sha256", "$hash  $([IO.Path]::GetFileName($msi))`n", [Text.UTF8Encoding]::new($false))
Write-Host "MSI created: $msi"
