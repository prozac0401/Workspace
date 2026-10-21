[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$MsiPath,
    [ValidateSet('Inspect','Suite')][string]$Action='Inspect',
    [string]$RollbackMsi,
    [string]$WrongArchitectureMsi,
    [string]$InstalledProbe
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$msi=(Resolve-Path -LiteralPath $MsiPath).Path
$metadata=Get-Content -Encoding UTF8 -LiteralPath ($msi+'.json') -Raw|ConvertFrom-Json
& (Join-Path $PSScriptRoot '../build/verify-msi.ps1') -MsiPath $msi
$identity=[Security.Principal.WindowsIdentity]::GetCurrent();$principal=New-Object Security.Principal.WindowsPrincipal($identity)
$elevated=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$existing=@()
foreach($registryView in @([Microsoft.Win32.RegistryView]::Registry32,[Microsoft.Win32.RegistryView]::Registry64)){
    $hive=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,$registryView)
    try{foreach($keyName in @('Software\VisibleCellsPaste','Software\Workspace\VisibleCellsPasteMsi','Software\Classes\CLSID\{856B2219-6225-42ED-8FF1-2D06E5913AC8}','Software\Microsoft\Office\Excel\Addins\Workspace.VisibleCellsPaste','Software\Microsoft\Windows\CurrentVersion\Uninstall\Workspace.VisibleCellsPaste')){
        $key=$hive.OpenSubKey($keyName);if($key){try{if($key.ValueCount -or $key.SubKeyCount){$existing+="$registryView/$keyName"}}finally{$key.Dispose()}}
    }}finally{$hive.Dispose()}
}
$excel=@(Get-Process -Name EXCEL -ErrorAction SilentlyContinue)
$related=@();$windowsInstaller=New-Object -ComObject WindowsInstaller.Installer
try{foreach($upgrade in @('{3489A60C-88FB-441D-A7AC-B80B7DB4084C}','{E4A1C33D-5D65-4931-963B-6E3CF87E38FB}')){
    foreach($code in $windowsInstaller.RelatedProducts($upgrade)){$related += [pscustomobject]@{productCode=$code;state=$windowsInstaller.ProductState($code)}}
}}finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($windowsInstaller)}
[pscustomobject]@{action=$Action;elevated=$elevated;existingRegistration=$existing;relatedMsiProducts=$related;excelProcesses=$excel.Count;msi=$msi;productCode=$metadata.productCode}|ConvertTo-Json -Depth 4
if($Action -eq 'Inspect'){return}
if($elevated -or $existing.Count -or $related.Count -or $excel.Count){throw 'Installer suite requires ordinary user, no existing product/MSI registration and no running Excel. No product state changed.'}
if($metadata.rollbackTest){throw 'Primary package must be a production candidate, not a rollback fixture.'}
$run=Join-Path $repo ('artifacts/visible-cells-paste/msi-tests/'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$installed=Join-Path $run "installed 한글 space's"
if(!$installed.StartsWith((Join-Path $repo 'artifacts/visible-cells-paste/msi-tests')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Test path escaped intended output.'}
[IO.Directory]::CreateDirectory($installed)|Out-Null
$fixture=Join-Path $installed 'business-fixture.txt';[IO.File]::WriteAllText($fixture,'Synthetic user file: retain after uninstall.');$fixtureHash=(Get-FileHash -LiteralPath $fixture).Hash
$records=New-Object 'System.Collections.Generic.List[object]'
function Save-Results { $records|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $run 'results.json') -Encoding UTF8 }
function Pass([string]$Name){$records.Add([ordered]@{test=$Name;status='PASS'});Save-Results;Write-Output "PASS $Name"}
function Check([bool]$Condition,[string]$Name){if(!$Condition){$records.Add([ordered]@{test=$Name;status='FAIL'});Save-Results;throw $Name};Pass $Name}
function Invoke-Msi([string]$Name,[string[]]$Arguments,[int]$Expected=0){
    $log=Join-Path $run ($Name+'.log');$argumentsAll=$Arguments+@('/qn','/norestart','/L*V',$log)
    $start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=Join-Path $env:WINDIR 'System32/msiexec.exe';$start.UseShellExecute=$false;$start.CreateNoWindow=$true
    $start.Arguments=(@($argumentsAll|ForEach-Object{
        if($_.Contains('"') -or $_.EndsWith('\')){throw 'Ambiguous installer test argument.'}
        if($_ -match '^/[A-Za-z*]+$' -or $_ -match '^\{[A-Fa-f0-9-]{36}\}$'){$_}
        elseif($_ -match '^(?<property>[A-Z][A-Z0-9_]*)=(?<value>.*)$'){$Matches.property+'="'+$Matches.value+'"'}
        else{'"'+$_+'"'}
    })-join ' ')
    $process=[Diagnostics.Process]::Start($start)
    try{
        if(!$process.WaitForExit(120000)){
            $records.Add([ordered]@{test=$Name;status='TIMEOUT';processId=$process.Id;log=[IO.Path]::GetFileName($log)});Save-Results
            throw "Installer step $Name exceeded 120 seconds. Process $($process.Id) was not terminated; inspect before continuing."
        }
        $code=$process.ExitCode
    }finally{$process.Dispose()}
    $records.Add([ordered]@{test=$Name;status=$(if($code -eq $Expected){'PASS'}else{'FAIL'});exit=$code;expectedExit=$Expected;log=[IO.Path]::GetFileName($log)});Save-Results
    if($code -ne $Expected){throw "Installer step $Name returned $code; expected $Expected. Stop and inspect $run without automatic cleanup."}
    Write-Output "PASS $Name (msiexec $code)"
}
function Assert-NoPayload([string]$Name){Check (@($metadata.files|Where-Object{Test-Path -LiteralPath (Join-Path $installed $_.Name)}).Count -eq 0) $Name}
function Assert-Payload([string]$Name){
    $bad=@($metadata.files|Where-Object{$file=Join-Path $installed $_.Name;!(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-FileHash -LiteralPath $file).Hash -ne $_.Sha256})
    Check ($bad.Count -eq 0) $Name
}
function Assert-Registration([string]$Name){
    $mismatches=@()
    $expectedValues=@($metadata.registrations)
    foreach($file in $metadata.files){$expectedValues += [pscustomobject]@{Key='Software\Workspace\VisibleCellsPasteMsi\Files';Name=$file.Name;Value=$file.Sha256;Type='string'}}
    foreach($expected in $expectedValues){
        $key=$hive.OpenSubKey($expected.Key)
        try{
            $wanted=([string]$expected.Value).Replace('[INSTALLFOLDER]',$installed+'\').Replace('[VCPCODEBASE]',('file:///'+($installed+'\VisibleCellsPaste.AddIn.dll').Replace('\','/')))
            $kind=if($expected.Type -eq 'integer'){[Microsoft.Win32.RegistryValueKind]::DWord}else{[Microsoft.Win32.RegistryValueKind]::String}
            if(!$key -or $key.GetValueNames() -notcontains $expected.Name -or $key.GetValueKind($expected.Name) -ne $kind -or [string]$key.GetValue($expected.Name) -cne $wanted){$mismatches += $expected.Key+'/'+$expected.Name}
        }finally{if($key){$key.Dispose()}}
    }
    if($mismatches.Count){$records.Add([ordered]@{test=$Name;status='FAIL';mismatchedOwnedValues=$mismatches});Save-Results;throw "Installed registration verification failed: $Name"}
    Pass $Name
}
$view=if($metadata.architecture -eq 'x64'){[Microsoft.Win32.RegistryView]::Registry64}else{[Microsoft.Win32.RegistryView]::Registry32}
$hive=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,$view)
try{
    if($WrongArchitectureMsi){
        & (Join-Path $PSScriptRoot '../build/verify-msi.ps1') -MsiPath $WrongArchitectureMsi
        Invoke-Msi 'wrong-excel-bitness-refused' @('/i',(Resolve-Path -LiteralPath $WrongArchitectureMsi).Path,('INSTALLFOLDER='+$installed)) 1603
        Assert-NoPayload 'wrong-bitness-no-files'
    }
    if($RollbackMsi){
        $rollback=(Resolve-Path -LiteralPath $RollbackMsi).Path;$rollbackMeta=Get-Content -Encoding UTF8 -LiteralPath ($rollback+'.json') -Raw|ConvertFrom-Json
        if(!$rollbackMeta.rollbackTest -or $rollbackMeta.architecture -ne $metadata.architecture){throw 'Rollback candidate metadata mismatch.'}
        & (Join-Path $PSScriptRoot '../build/verify-msi.ps1') -MsiPath $rollback
        Invoke-Msi 'rollback-after-standard-actions' @('/i',$rollback,('INSTALLFOLDER='+$installed)) 1603
        $windowsInstaller=New-Object -ComObject WindowsInstaller.Installer
        try{$rollbackState=$windowsInstaller.ProductState($rollbackMeta.productCode)}finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($windowsInstaller)}
        Check ($rollbackState -eq -1) ('rollback-no-installer-product-registration (actual state '+$rollbackState+')')
        $rollbackLog=[IO.File]::ReadAllText((Join-Path $run 'rollback-after-standard-actions.log'))
        Check (!$rollbackLog.Contains('Error in rollback skipped')) 'rollback-no-internal-engine-errors'
        Assert-NoPayload 'rollback-no-owned-files'
        $key=$hive.OpenSubKey('Software\Workspace\VisibleCellsPasteMsi');try{Check (!$key -or !$key.GetValue('ProductCode')) 'rollback-no-product-owner'}finally{if($key){$key.Dispose()}}
    }
    Invoke-Msi 'clean-install' @('/i',$msi,('INSTALLFOLDER='+$installed))
    Assert-Payload 'installed-payload-hashes'
    Assert-Registration 'installed-registration-values'
    Check ((Get-FileHash -LiteralPath $fixture).Hash -eq $fixtureHash) 'existing-unknown-file-preserved'
    if($InstalledProbe){
        $probe=(Resolve-Path -LiteralPath $InstalledProbe).Path;$start=New-Object Diagnostics.ProcessStartInfo;$start.FileName=$probe;$start.WorkingDirectory=$run;$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $process=[Diagnostics.Process]::Start($start)
        try{$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$process.WaitForExit();[IO.File]::WriteAllText((Join-Path $run 'installed-excel-probe.log'),$stdout.Result+$stderr.Result);$exit=$process.ExitCode}finally{$process.Dispose()}
        Check ($exit -eq 0) 'normal-installed-excel-autoload'
        if(@(Get-Process -Name EXCEL -ErrorAction SilentlyContinue).Count){throw 'Excel probe left Excel running. Stop without forced close.'}
    }
    $dll=Join-Path $installed 'VisibleCellsPaste.AddIn.dll';$backup=Join-Path $run 'owned-dll.backup';Copy-Item -LiteralPath $dll -Destination $backup
    # The sole deletion is a verified owned synthetic installation file inside artifacts.
    if(!(Get-Item -LiteralPath $dll).FullName.StartsWith($installed+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $dll).Hash -ne $metadata.files[0].Sha256){throw 'Owned-file precondition failed.'}
    Remove-Item -LiteralPath $dll
    Invoke-Msi 'missing-file-repair' @('/famus',$msi)
    Assert-Payload 'repair-restored-original-payload'
    Assert-Registration 'repair-restored-registration-values'
    $key=$hive.OpenSubKey('Software\Workspace\VisibleCellsPasteMsi',$true)
    try{if($key.GetValue('ProductCode') -ne $metadata.productCode){throw 'Unexpected ownership marker; no test mutation.'};$key.DeleteValue('ProductCode',$false)}finally{$key.Dispose()}
    Invoke-Msi 'missing-marker-repair' @('/famus',$msi)
    $key=$hive.OpenSubKey('Software\Workspace\VisibleCellsPasteMsi')
    try{Check ($key.GetValue('ProductCode') -eq $metadata.productCode) 'repair-restored-missing-owner-marker'}finally{$key.Dispose()}
    [IO.File]::AppendAllText($dll,'Synthetic external edit');$changedHash=(Get-FileHash -LiteralPath $dll).Hash
    Invoke-Msi 'changed-file-repair-refused' @('/famus',$msi) 1603
    Invoke-Msi 'changed-file-removal-refused' @('/x',$metadata.productCode) 1603
    Check ((Get-FileHash -LiteralPath $dll).Hash -eq $changedHash) 'changed-file-preserved'
    Copy-Item -LiteralPath $backup -Destination $dll -Force
    $addinKey='Software\Microsoft\Office\Excel\Addins\Workspace.VisibleCellsPaste'
    $key=$hive.OpenSubKey($addinKey,$true)
    try{if($key.GetValue('LoadBehavior') -ne 3){throw 'Unexpected LoadBehavior; no test mutation.'};$key.SetValue('LoadBehavior',2,[Microsoft.Win32.RegistryValueKind]::DWord)}finally{$key.Dispose()}
    Invoke-Msi 'disabled-load-repair-refused' @('/famus',$msi) 1603
    Invoke-Msi 'disabled-load-removal-refused' @('/x',$metadata.productCode) 1603
    $key=$hive.OpenSubKey($addinKey,$true)
    try{Check ($key.GetValue('LoadBehavior') -eq 2) 'disabled-load-preserved';$key.SetValue('LoadBehavior',3,[Microsoft.Win32.RegistryValueKind]::DWord)}finally{$key.Dispose()}
    $ownerKey='Software\Workspace\VisibleCellsPasteMsi';$key=$hive.OpenSubKey($ownerKey,$true)
    $redirect=Join-Path $run 'redirected';[IO.Directory]::CreateDirectory($redirect)|Out-Null
    try{$originalRoot=[string]$key.GetValue('InstallFolder');$key.SetValue('InstallFolder',$redirect+'\',[Microsoft.Win32.RegistryValueKind]::String)}finally{$key.Dispose()}
    Invoke-Msi 'redirected-maintenance-refused' @('/famus',$msi) 1603
    $key=$hive.OpenSubKey($ownerKey,$true)
    try{Check ($key.GetValue('InstallFolder') -eq ($redirect+'\')) 'redirected-registration-preserved';$key.SetValue('InstallFolder',$originalRoot,[Microsoft.Win32.RegistryValueKind]::String)}finally{$key.Dispose()}
    $unknownName='VcpMsiSynthetic_'+[Guid]::NewGuid().ToString('N');$key=$hive.OpenSubKey($addinKey,$true)
    try{$key.SetValue($unknownName,'synthetic-keep',[Microsoft.Win32.RegistryValueKind]::String)}finally{$key.Dispose()}
    $key=$hive.OpenSubKey($ownerKey,$true)
    try{if($key.GetValue('ProductCode') -ne $metadata.productCode){throw 'Unexpected ownership marker before interrupted-state removal test.'};$key.DeleteValue('ProductCode',$false)}finally{$key.Dispose()}
    Invoke-Msi 'normal-uninstall' @('/x',$metadata.productCode)
    Assert-NoPayload 'uninstall-removed-owned-files'
    Check ((Get-FileHash -LiteralPath $fixture).Hash -eq $fixtureHash) 'uninstall-preserved-unknown-file'
    $key=$hive.OpenSubKey($addinKey,$true)
    try{Check ($null -ne $key -and $key.GetValue($unknownName) -eq 'synthetic-keep') 'uninstall-preserved-unknown-registry-value';$key.DeleteValue($unknownName,$false)}finally{if($key){$key.Dispose()}}
    Invoke-Msi 'already-removed-product-no-change' @('/x',$metadata.productCode) 1605
    Write-Output "Installer suite completed: $run. Business-file fixture retained."
}catch{Save-Results;throw}finally{$hive.Dispose()}
