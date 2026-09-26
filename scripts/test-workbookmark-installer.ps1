[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MsiPath,
    [Parameter(Mandatory=$true)][string]$PreviousMsiPath,
    [ValidateSet('Fresh','Upgrade','All')][string]$Mode='All'
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=[IO.Path]::GetFullPath((Join-Path $repo ('artifacts/bookmark-lifecycle-'+[guid]::NewGuid().ToString('N'))))
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'artifacts'))+[IO.Path]::DirectorySeparatorChar
if(-not $root.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence path outside artifacts.'}
$local=[Environment]::GetFolderPath('LocalApplicationData')
$programs=[Environment]::GetFolderPath('Programs')
$startup=Join-Path ([Environment]::GetFolderPath('Startup')) 'WorkBookmark.lnk'
$menu=Join-Path $programs 'WorkBookmark'
$installerKey='HKCU:\Software\WorkBookmark\Installer'
$preferenceKey='HKCU:\Software\WorkBookmark\Preferences'
$uninstall='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
function Registered-Products {
    # Installer.RelatedProducts is the supported product inventory API. A single
    # Uninstall registry view is not a complete per-user MSI inventory.
    $api=New-Object -ComObject WindowsInstaller.Installer
    try {
        foreach($code in $api.RelatedProducts('{BB5C5CA8-5BA0-4B01-875E-9E295690C711}')) {
            [pscustomobject]@{productCode=$code;version=$api.ProductInfo($code,'VersionString');state=$api.ProductState($code)}
        }
    } finally {[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($api)}
}
$existing=@(Registered-Products)
if(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use an ordinary user.'}
if($existing.Count -or (Test-Path $installerKey) -or (Test-Path $startup) -or (Test-Path $menu) -or (Test-Path (Join-Path $local 'Programs/WorkBookmark')) -or @(Get-Process WorkBookmark -ErrorAction SilentlyContinue).Count){throw 'Existing installation, shortcut or process: use an isolated account.'}
$msi=(Resolve-Path -LiteralPath $MsiPath).Path
$previous=(Resolve-Path -LiteralPath $PreviousMsiPath).Path
if((Get-FileHash $msi -Algorithm SHA256).Hash -ne '3424a44367e7e7c1e1483d359c595dd568d2368cea48b61e83e6b63c65eca714'){throw 'Expected exact public 0.2.3 MSI.'}
if((Get-FileHash $previous -Algorithm SHA256).Hash -ne '0f4aab1d57018767d5046d2b51a7189aa27da944aa4b6b96146f94a9264a3f6d'){throw 'Expected verified local 0.2.2 MSI.'}
New-Item -ItemType Directory -Path $root | Out-Null
# The public MSI exposes a fixed default install location. Test that supported
# path after the no-existing-installation preflight; keep evidence under artifacts.
$install=Join-Path $local 'Programs/WorkBookmark'
$checks=[Collections.Generic.List[object]]::new()
$installed=$null
function Snapshot-Data {
    $snapshot=@{}
    foreach($name in @('bookmarks.db','bookmarks.db-wal','bookmarks.db-shm','settings.json','stickers.json','sticker-layout.json')){
        $path=Join-Path (Join-Path $local 'WorkBookmark') $name
        if(Test-Path -LiteralPath $path -PathType Leaf){$snapshot[$name]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
    }
    return $snapshot
}
function Preference {
    if(-not(Test-Path $preferenceKey)){return ''}
    return ((Get-ItemProperty -LiteralPath $preferenceKey | Select-Object * -ExcludeProperty PSPath,PSParentPath,PSChildName,PSDrive,PSProvider)|ConvertTo-Json -Compress)
}
function Check([string]$name,[bool]$ok){$checks.Add(@{name=$name;passed=$ok});if(-not $ok){throw $name}}
function Msi([string]$name,[string[]]$arguments){
    $p=Start-Process msiexec.exe -ArgumentList ($arguments+@('/qn','/norestart','/l*v',('"'+(Join-Path $root ($name+'.log'))+'"'))) -WindowStyle Hidden -PassThru -Wait
    $checks.Add(@{name=$name;exitCode=$p.ExitCode;passed=($p.ExitCode -eq 0)})
    if($p.ExitCode -ne 0){throw "$name failed: $($p.ExitCode)"}
}
function Data-Unchanged([string]$stage){
    $after=Snapshot-Data
    Check ($stage+' data file inventory preserved') (($before.Keys | Sort-Object | ConvertTo-Json -Compress) -eq ($after.Keys | Sort-Object | ConvertTo-Json -Compress))
    foreach($name in $before.Keys){Check ($stage+' data preserved: '+$name) ($before[$name] -eq $after[$name])}
    Check ($stage+' startup preference preserved') ((Preference) -eq $preferenceBefore)
    Check ($stage+' no automatic app launch') (@(Get-Process WorkBookmark -ErrorAction SilentlyContinue).Count -eq 0)
}
$before=Snapshot-Data
$preferenceBefore=Preference
$status='running'
$failure=$null
try {
    if($Mode -ne 'Upgrade') {
        Msi 'fresh-install-023' @('/i',('"'+$msi+'"'))
        $installed=$msi
        Check 'fresh 0.2.3 executable installed' ((Get-Item (Join-Path $install 'WorkBookmark.exe')).VersionInfo.ProductVersion -like '0.2.3*')
        Check 'fresh start menu created' (Test-Path -LiteralPath (Join-Path $menu 'WorkBookmark.lnk'))
        Data-Unchanged 'fresh install'
        Msi 'fresh-uninstall-023' @('/x',('"'+$msi+'"'))
        $installed=$null
        Check 'fresh executable removed' (-not(Test-Path -LiteralPath (Join-Path $install 'WorkBookmark.exe')))
        Check 'fresh startup removed' (-not(Test-Path -LiteralPath $startup))
        Check 'fresh registration removed' (@(Registered-Products).Count -eq 0)
        Data-Unchanged 'fresh uninstall'
    }
    if($Mode -ne 'Fresh') {
    Msi 'install-022' @('/i',('"'+$previous+'"'),('INSTALLFOLDER="'+$install+'"'))
    $installed=$previous
    Check '0.2.2 executable installed' ((Get-Item (Join-Path $install 'WorkBookmark.exe')).VersionInfo.ProductVersion -like '0.2.2*')
    $startupBefore=Test-Path -LiteralPath $startup
    Check 'start menu created' (Test-Path -LiteralPath (Join-Path $menu 'WorkBookmark.lnk'))
    Data-Unchanged 'install'
    Msi 'upgrade-023' @('/i',('"'+$msi+'"'),('INSTALLFOLDER="'+$install+'"'))
    $installed=$msi
    Check '0.2.3 executable installed' ((Get-Item (Join-Path $install 'WorkBookmark.exe')).VersionInfo.ProductVersion -like '0.2.3*')
    $registered=@(Registered-Products)
    $registered | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'registered-products.json') -Encoding UTF8
    Check 'exactly one installed 0.2.3 registration' ($registered.Count -eq 1 -and $registered[0].version -eq '0.2.3' -and $registered[0].state -eq 5)
    Check 'startup selection preserved across upgrade' ((Test-Path -LiteralPath $startup) -eq $startupBefore)
    Data-Unchanged 'upgrade'
    Msi 'repair-023' @('/fa',('"'+$msi+'"'))
    Data-Unchanged 'repair'
    Msi 'uninstall-023' @('/x',('"'+$msi+'"'))
    $installed=$null
    Check 'executable removed' (-not(Test-Path -LiteralPath (Join-Path $install 'WorkBookmark.exe')))
    Check 'startup shortcut removed' (-not(Test-Path -LiteralPath $startup))
    Check 'start menu shortcut removed' (-not(Test-Path -LiteralPath (Join-Path $menu 'WorkBookmark.lnk')))
    Check 'uninstall registration removed' (@(Registered-Products).Count -eq 0)
    Data-Unchanged 'uninstall'
    }
    $status='passed'
} catch {$status='failed';$failure=$_.Exception.Message;throw}
finally {
    if($installed){Msi 'cleanup-uninstall' @('/x',('"'+$installed+'"'));Data-Unchanged 'cleanup'}
    @{status=$status;error=$failure;checks=$checks.ToArray();uiAndIme='NOT_RUN';dataContentsLogged=$false;msiSha256=(Get-FileHash $msi -Algorithm SHA256).Hash;os=[Environment]::OSVersion.VersionString}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath (Join-Path $root 'results.json') -Encoding UTF8
    Write-Output $root
}
