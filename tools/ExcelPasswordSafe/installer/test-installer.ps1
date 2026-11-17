#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$MsiPath,[string]$UpgradeMsiPath,[ValidateSet('None','DeferredBeforePublish','LateAfterPublish')][string]$RollbackMode='None')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$package=(Resolve-Path -LiteralPath $MsiPath).Path
$details=(& (Join-Path $PSScriptRoot 'verify-msi.ps1') -MsiPath $package) | ConvertFrom-Json
$menuVersion=[version]$details.version
$upgrade=$null
if($UpgradeMsiPath) {
    $upgrade=(Resolve-Path -LiteralPath $UpgradeMsiPath).Path
    $upgradeDetails=(& (Join-Path $PSScriptRoot 'verify-msi.ps1') -MsiPath $upgrade) | ConvertFrom-Json
    if([version]$upgradeDetails.version -le [version]$details.version) { throw 'The upgrade package must have a greater version.' }
}
$menuKeys=@('.xls','.xlsx','.xlsm','.xlsb') | ForEach-Object { 'HKCU:\Software\Classes\SystemFileAssociations\'+$_+'\shell\Workspace.ExcelPasswordSafe' }
$folderMenuKey='HKCU:\Software\Classes\Directory\shell\Workspace.ExcelPasswordSafe'
$backgroundMenuKey='HKCU:\Software\Classes\Directory\Background\shell\Workspace.ExcelPasswordSafe'
$stateKey='HKCU:\Software\Workspace\ExcelPasswordSafe'
$defaultInstall=Join-Path $env:LOCALAPPDATA 'Programs\ExcelPasswordSafe'
$shortcutFolder=Join-Path ([Environment]::GetFolderPath('Programs')) 'ExcelPasswordSafe'
foreach($path in (@($menuKeys)+@($folderMenuKey,$backgroundMenuKey,$stateKey,$defaultInstall,$shortcutFolder))) {
    if(Test-Path -LiteralPath $path) { throw ('Preflight refused: existing product data/menu/installation at '+$path) }
}
foreach($policyPath in @('HKCU:\Software\Policies\Microsoft\Windows\Installer','HKLM:\Software\Policies\Microsoft\Windows\Installer')) {
    if((Test-Path -LiteralPath $policyPath) -and (Get-Item -LiteralPath $policyPath).GetValue('DisableRollback',0) -eq 1) { throw 'Preflight refused: Windows Installer rollback is disabled by policy.' }
}
$installer=New-Object -ComObject WindowsInstaller.Installer
try {
    $related=@($installer.RelatedProducts('{0E60B57C-21DA-41A5-8FAC-6CCDF41EB62C}'))
    if($related.Count) { throw 'Preflight refused: a related ExcelPasswordSafe MSI product is installed.' }
} finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer) }
$testRoot=Join-Path $repoRoot ('artifacts\excel-password-safe\installer-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
$allowed=[IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\excel-password-safe'))+[IO.Path]::DirectorySeparatorChar
$resolved=[IO.Path]::GetFullPath($testRoot)
if(-not $resolved.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Installer test output is outside the intended artifacts directory.' }
$install=Join-Path $testRoot '사용자 지정 경로'
$redirectedInstall=Join-Path $testRoot 'must-not-relocate'
$fixtures=Join-Path $testRoot 'preserved-files'
New-Item -ItemType Directory -Path $fixtures -Force | Out-Null
$business=Join-Path $fixtures 'keep.xlsx'
[IO.File]::WriteAllText($business,'Synthetic sentinel. Not an Excel document. Must survive installation.')
$businessHash=(Get-FileHash -LiteralPath $business -Algorithm SHA256).Hash
$preservedBackup=Join-Path $fixtures 'original.xlsx'
[IO.File]::WriteAllText($preservedBackup,'Synthetic backup sentinel. Must survive uninstallation.')
$backupHash=(Get-FileHash -LiteralPath $preservedBackup -Algorithm SHA256).Hash
$results=New-Object 'Collections.Generic.List[object]'
$activePackage=$null
$rollbackProductCode=$null
$status='Failed'
$isElevated=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
function Check([string]$Name,[bool]$Pass) { $results.Add(@{name=$Name;passed=$Pass}); if(-not $Pass) { throw ('Check failed: '+$Name) } }
function Invoke-Msi([string]$Name,[string[]]$Arguments,[int[]]$Expected=@(0,3010)) {
    $log=Join-Path $testRoot ($Name+'.log')
    $args=$Arguments+@('/qn','/norestart','REBOOT=ReallySuppress','MSIRESTARTMANAGERCONTROL=Disable','/l*v',('"'+$log+'"'))
    $process=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\msiexec.exe') -ArgumentList $args -PassThru -WindowStyle Hidden
    if(-not $process.WaitForExit(120000)) { throw ('Installer still running; inspect manually without terminating it. Log: '+$log) }
    Check ($Name+' exit '+$process.ExitCode) ($Expected -contains $process.ExitCode)
}
function Check-Menus([bool]$Present) {
    foreach($key in $menuKeys) {
        Check ('menu '+$key+' present='+$Present) ((Test-Path -LiteralPath $key) -eq $Present)
        if($Present) {
            Check ('single selection '+$key) ((Get-ItemProperty -LiteralPath $key).MultiSelectModel -ceq 'Single')
            if($menuVersion -lt [version]'2.0.0') {
                $command=(Get-Item -LiteralPath ($key+'\command')).GetValue('')
                Check ('quoted legacy file command '+$key) ($command -ceq ('"'+$install+'\ExcelPasswordSafe.exe" --file "%1"'))
            } else {
                Check ('legacy root command removed '+$key) (-not (Test-Path -LiteralPath ($key+'\command')))
            }
        }
    }
    $cascades=@(@{key=$folderMenuKey;minimum=[version]'1.4.0';argument='%1';name='folder';kind='folder'},@{key=$backgroundMenuKey;minimum=[version]'2.0.0';argument='%V\.';name='background';kind='folder'})
    if($menuVersion -ge [version]'2.0.0') { foreach($key in $menuKeys) { $cascades+=@{key=$key;minimum=[version]'2.0.0';argument='%1';name=('file '+$key);kind='file'} } }
    foreach($cascade in $cascades) {
    $folderPresent=$Present -and $menuVersion -ge $cascade.minimum
    Check ($cascade.name+' cascade present='+$folderPresent) ((Test-Path -LiteralPath $cascade.key) -eq $folderPresent)
    if($folderPresent) {
        $folder=(Get-Item -LiteralPath $cascade.key)
        Check 'folder cascade label' ($folder.GetValue('MUIVerb') -ceq 'Excel 암호 관리')
        Check 'folder cascade single selection' ($folder.GetValue('MultiSelectModel') -ceq 'Single')
        Check 'folder cascade uses local subcommands' ($folder.GetValue('SubCommands',$null) -ceq '')
        $verbs=@(@{id='01Encrypt';mode='Encrypt';label='암호 설정'},@{id='02Decrypt';mode='Decrypt';label='암호 해제'},@{id='03ChangePassword';mode='ChangePassword';label='암호 변경'})
        foreach($verb in $verbs) {
            $key=$cascade.key+'\shell\'+$verb.id
            Check ('folder action '+$verb.mode) (Test-Path -LiteralPath $key)
            if(Test-Path -LiteralPath $key) {
                $properties=Get-Item -LiteralPath $key
                Check ('folder label '+$verb.mode) ($properties.GetValue('MUIVerb') -ceq $verb.label)
                Check ('folder single selection '+$verb.mode) ($properties.GetValue('MultiSelectModel') -ceq 'Single')
                $command=(Get-Item -LiteralPath ($key+'\command')).GetValue('')
                Check ('quoted folder command '+$verb.mode) ($command -ceq ('"'+$install+'\ExcelPasswordSafe.exe" --'+$cascade.kind+' "'+$cascade.argument+'" --mode '+$verb.mode))
            }
        }
        Check ($cascade.name+' icon points to application') ($folder.GetValue('Icon') -ceq ('"'+$install+'\ExcelPasswordSafe.exe",0'))
        Check 'installed batch engine present' (Test-Path -LiteralPath (Join-Path $install 'runtime\BatchEngine.ps1'))
    }
    }
    if($Present) {
        Check 'remembered custom installation path' ((Get-Item -LiteralPath $stateKey).GetValue('InstallFolder').TrimEnd('\') -ieq $install.TrimEnd('\'))
        if($menuVersion -ge [version]'4.0.0') {
            Check 'installed direct crypto DLL present' (Test-Path -LiteralPath (Join-Path $install 'runtime\ExcelPasswordSafe.Crypto.dll'))
            Check 'installed third-party notices present' (Test-Path -LiteralPath (Join-Path $install 'THIRD-PARTY-NOTICES.txt'))
            Check 'installed direct crypto assembly version matches product' ([Reflection.AssemblyName]::GetAssemblyName((Join-Path $install 'runtime\ExcelPasswordSafe.Crypto.dll')).Version.ToString() -ceq ($menuVersion.ToString()+'.0'))
        }
    }
}
function Check-Preserved {
    Check 'business sentinel preserved' ((Get-FileHash -LiteralPath $business -Algorithm SHA256).Hash -eq $businessHash)
    Check 'backup sentinel preserved' ((Get-FileHash -LiteralPath $preservedBackup -Algorithm SHA256).Hash -eq $backupHash)
}
function Default-Associations {
    $snapshot=@()
    foreach($ext in @('.xls','.xlsx','.xlsm','.xlsb','Directory','Directory\Background')) {
        foreach($base in @('Registry::HKEY_CLASSES_ROOT\','HKCU:\Software\Classes\')) {
            $path=$base+$ext
            $value=if(Test-Path -LiteralPath $path) { (Get-Item -LiteralPath $path).GetValue('') } else { $null }
            $snapshot += @{path=$path;default=$value}
        }
    }
    return ($snapshot | ConvertTo-Json -Compress)
}
$beforeAssociations=Default-Associations
try {
    if($RollbackMode -ne 'None') {
    # Explicit fault testing uses a distinct product/package identity. Normal
    # installation lifecycle never runs an intentionally modified MSI.
    $rollbackMsi=Join-Path $testRoot 'TEST-ONLY-forced-rollback.msi'
    Copy-Item -LiteralPath $package -Destination $rollbackMsi
    $wi=New-Object -ComObject WindowsInstaller.Installer
    $db=$wi.OpenDatabase($rollbackMsi,1)
    try {
        $rollbackProductCode='{'+[guid]::NewGuid().ToString().ToUpperInvariant()+'}'
        $sqls=@("UPDATE ``Property`` SET ``Value``='$rollbackProductCode' WHERE ``Property``='ProductCode'")
        if($RollbackMode -eq 'LateAfterPublish') {
            $sqls+=@("INSERT INTO ``CustomAction`` (``Action``, ``Type``, ``Target``) VALUES ('TestForcedRollback', 19, 'Synthetic installer rollback test')", "INSERT INTO ``InstallExecuteSequence`` (``Action``, ``Condition``, ``Sequence``) VALUES ('InstallExecute', 'NOT Installed', 6500)", "INSERT INTO ``InstallExecuteSequence`` (``Action``, ``Condition``, ``Sequence``) VALUES ('TestForcedRollback', 'NOT Installed', 6501)")
        } else {
            # Type 34 + 1024: deferred command, runs during the normal install
            # script after WriteRegistryValues, before product registration.
            # It performs no file operation: cmd.exe exits with failure only.
            $failureCommand='"'+(Join-Path $env:WINDIR 'System32\cmd.exe')+'" /d /c exit 1'
            $sqls+=@("INSERT INTO ``CustomAction`` (``Action``, ``Type``, ``Source``, ``Target``) VALUES ('TestForcedRollback', 1058, 'INSTALLFOLDER', '$failureCommand')", "INSERT INTO ``InstallExecuteSequence`` (``Action``, ``Condition``, ``Sequence``) VALUES ('TestForcedRollback', 'NOT Installed', 5100)")
        }
        foreach($sql in $sqls) {
            $view=$db.OpenView($sql); [void]$view.Execute(); [void]$view.Close(); [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view)
        }
        $summary=$db.SummaryInformation(20)
        try {
            $newPackageCode='{'+[guid]::NewGuid().ToString().ToUpperInvariant()+'}'
            [void]$summary.GetType().InvokeMember('Property',[Reflection.BindingFlags]::SetProperty,$null,$summary,@(9,$newPackageCode))
            [void]$summary.Persist()
        } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($summary) }
        [void]$db.Commit()
    } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($db); [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($wi) }
    Invoke-Msi 'forced-rollback' @('/i',('"'+$rollbackMsi+'"'),('INSTALLFOLDER="'+$install+'"')) @(1603)
    $rollbackLog=Get-Content -LiteralPath (Join-Path $testRoot 'forced-rollback.log') -Raw
    Check 'failure occurred at the injected rollback action' ($rollbackLog -match 'Synthetic installer rollback test|CustomAction TestForcedRollback returned actual error code 1')
    Check 'rollback followed actual file writes' ($rollbackLog -match 'Executing op: FileCopy\(')
    Check 'rollback followed actual registry writes' ($rollbackLog -match 'Executing op: RegAddValue\(')
    Check-Menus $false
    Check 'rollback removed installed executable' (-not (Test-Path -LiteralPath (Join-Path $install 'ExcelPasswordSafe.exe')))
    Check-Preserved
    $wi=New-Object -ComObject WindowsInstaller.Installer
    try { $productState=[int]$wi.ProductState($rollbackProductCode) } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($wi) }
    if($productState -ne -1) { $activePackage=$rollbackMsi }
    Check ('rollback removed MSI registration; ProductState='+$productState) ($productState -eq -1)
    }
    Invoke-Msi 'install' @('/i',('"'+$package+'"'),('INSTALLFOLDER="'+$install+'"'))
    $activePackage=$package
    Check-Menus $true
    $exe=Join-Path $install 'ExcelPasswordSafe.exe'
    Check 'installed app present' (Test-Path -LiteralPath $exe)
    Check 'installed engine present' (Test-Path -LiteralPath (Join-Path $install 'runtime\Engine.ps1'))
    Check 'default file associations unchanged' ((Default-Associations) -ceq $beforeAssociations)
    $installedSmoke=Join-Path $testRoot 'installed-ui-smoke'
    $smoke=Start-Process -FilePath $exe -ArgumentList ('--smoke "'+$installedSmoke+'"') -PassThru -WindowStyle Hidden
    if(-not $smoke.WaitForExit(60000)) { throw 'Installed UI smoke did not finish; inspect the test process manually.' }
    Check 'installed UI smoke succeeded' ($smoke.ExitCode -eq 0 -and (Test-Path -LiteralPath (Join-Path $installedSmoke 'smoke-result.json')))
    # Delete only the installed, test-owned executable under this unique fixture.
    $exeResolved=[IO.Path]::GetFullPath($exe)
    if(-not $exeResolved.StartsWith(([IO.Path]::GetFullPath($install)+'\'),[StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing a repair-test deletion outside the installation fixture.' }
    Remove-Item -LiteralPath $exeResolved -Force
    $repairArgs=@('/fa',('"'+$package+'"'))
    if($menuVersion -ge [version]'2.0.0') { $repairArgs+=('INSTALLFOLDER="'+$redirectedInstall+'"') }
    Invoke-Msi 'repair' $repairArgs
    Check 'repair did not relocate installation' (-not (Test-Path -LiteralPath $redirectedInstall))
    Check 'repair restored executable' (Test-Path -LiteralPath $exe)
    Check-Menus $true
    if($upgrade) {
        $upgradeArgs=@('/i',('"'+$upgrade+'"'))
        if([version]$upgradeDetails.version -ge [version]'2.0.0') { $upgradeArgs+=('INSTALLFOLDER="'+$redirectedInstall+'"') }
        Invoke-Msi 'upgrade' $upgradeArgs
        Check 'upgrade ignored a different requested install location' (-not (Test-Path -LiteralPath $redirectedInstall))
        $activePackage=$upgrade
        $menuVersion=[version]$upgradeDetails.version
        Check 'upgrade remembered install directory' (Test-Path -LiteralPath $exe)
        Check-Menus $true
        Invoke-Msi 'downgrade-blocked' @('/i',('"'+$package+'"')) @(1638,1603)
        $downgradeLog=Get-Content -LiteralPath (Join-Path $testRoot 'downgrade-blocked.log') -Raw
        Check 'downgrade blocked by version gate' ($downgradeLog -match 'WIX_DOWNGRADE_DETECTED|FindRelatedProducts')
    }
    Check-Preserved
    Invoke-Msi 'uninstall' @('/x',('"'+$activePackage+'"'))
    $activePackage=$null
    Check-Menus $false
    Check 'uninstall removed program' (-not (Test-Path -LiteralPath $exe))
    Check 'uninstall removed shortcut directory' (-not (Test-Path -LiteralPath $shortcutFolder))
    Check 'default associations survived uninstall' ((Default-Associations) -ceq $beforeAssociations)
    Check-Preserved
    Invoke-Msi 'reinstall' @('/i',('"'+$package+'"'),('INSTALLFOLDER="'+$install+'"'))
    $activePackage=$package
    $menuVersion=[version]$details.version
    Check-Menus $true
    Invoke-Msi 'remove-reinstall' @('/x',('"'+$activePackage+'"'))
    $activePackage=$null
    Check-Menus $false
    Check-Preserved
    $status='Pass'
} finally {
    if($activePackage) {
        try { Invoke-Msi 'cleanup-uninstall' @('/x',('"'+$activePackage+'"')) } catch { $results.Add(@{name='cleanup-uninstall';passed=$false;message=$_.Exception.Message}) }
    }
    [ordered]@{status=$status;timestamp=[DateTimeOffset]::Now.ToString('O');os=[Environment]::OSVersion.VersionString;elevated=$isElevated;msi=$package;sha256=$details.sha256;upgrade=$upgrade;rollbackMode=$RollbackMode;rollbackProductCode=$rollbackProductCode;fixture=$testRoot;customInstallPath=$install;pathValidationUi='NotRun';results=$results.ToArray();explorerClick='NotRun';productionRelease=$false} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $testRoot 'installer-results.json') -Encoding UTF8
}
Write-Output ('Installer lifecycle passed. Evidence: '+$testRoot)
