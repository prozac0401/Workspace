[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?$')][string]$Version = '0.2.0-rc.1',
    [ValidateSet('x86','x64','both')][string]$Architecture = 'both',
    [string]$PackageDirectory,
    [string]$WixPath,
    [string]$VCToolsRoot,
    [string]$WindowsSdkRoot,
    [switch]$RollbackTest
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$product = Join-Path $root 'tools/VisibleCellsPaste'
if (!$PackageDirectory) { $PackageDirectory = Join-Path $root "artifacts/visible-cells-paste/$Version/package" }
$package = (Resolve-Path -LiteralPath $PackageDirectory).Path
if (!$WixPath) { $WixPath = Join-Path $root '.tools/wix/wix.exe' }
if (!$VCToolsRoot) { $VCToolsRoot = Join-Path $root '.tools/image-copy-save-native/msvc' }
if (!$WindowsSdkRoot) { $WindowsSdkRoot = Join-Path $root '.tools/image-copy-save-native/sdk' }
foreach ($required in @($WixPath,(Join-Path $VCToolsRoot 'include/vector'),(Join-Path $package 'build-manifest.json'))) { if (!(Test-Path -LiteralPath $required -PathType Leaf)) { throw "Build prerequisite missing: $required" } }
$manifest = Get-Content -Encoding UTF8 -LiteralPath (Join-Path $package 'build-manifest.json') -Raw | ConvertFrom-Json
if ($manifest.product -ne 'VisibleCellsPaste' -or $manifest.version -ne $Version) { throw 'Payload product/version mismatch.' }
$checksums=Get-Content -Encoding UTF8 -LiteralPath (Join-Path $package 'SHA256SUMS.txt')
foreach($line in $checksums){
    if($line -notmatch '^(?<hash>[0-9a-fA-F]{64})  (?<path>.+)$'){throw 'Malformed full-build payload checksum inventory.'}
    $relative=$Matches.path;$expectedHash=$Matches.hash;$payloadPath=[IO.Path]::GetFullPath((Join-Path $package $relative))
    if(!$payloadPath.StartsWith($package.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $payloadPath -PathType Leaf)){throw 'Invalid full-build payload inventory path.'}
    if((Get-FileHash -LiteralPath $payloadPath -Algorithm SHA256).Hash -ne $expectedHash){throw "Full-build payload changed: $relative"}
}
foreach($required in @('x86/VisibleCellsPaste.AddIn.dll','x64/VisibleCellsPaste.AddIn.dll','README.md','CHANGELOG.md','build-manifest.json')){
    if(@($checksums|Where-Object{$_.Substring(66) -eq $required}).Count -ne 1){throw "Required payload not covered by full-build hash inventory: $required"}
}
# Reject stale source payloads before packaging, even when the DLL has the expected name.
foreach ($source in $manifest.sources) {
    $path = Join-Path $root $source.path
    if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $source.sha256) { throw "Payload source changed since full build: $($source.path)" }
}
$sdkVersion = @(Get-ChildItem -LiteralPath (Join-Path $WindowsSdkRoot 'Include') -Directory | Where-Object Name -Match '^10\.0\.\d+\.0$' | Sort-Object { [version]$_.Name } -Descending)[0].Name
$productVersion = $Version.Split('-')[0]
$run = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
if ($RollbackTest) { $run += '-rollback-test' }
$output = Join-Path $root "artifacts/visible-cells-paste/$Version/msi/$run"
[IO.Directory]::CreateDirectory($output) | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
function Write-Utf8([string]$Path,[string]$Content) { [IO.File]::WriteAllText($Path,$Content,$utf8) }
function Xml([string]$Value) { [Security.SecurityElement]::Escape($Value) }
function ConvertTo-CppString([string]$Value) { 'L"'+$Value.Replace('\','\\').Replace('"','\"')+'"' }
function Get-StableGuid([string]$Identity){
    $hasher=[Security.Cryptography.SHA256]::Create()
    try{$bytes=$hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes('Workspace.VisibleCellsPaste.MSI|'+$Identity))}finally{$hasher.Dispose()}
    $guidBytes=New-Object byte[] 16;[Array]::Copy($bytes,$guidBytes,16);$guidBytes[7]=($guidBytes[7]-band 15)-bor 80;$guidBytes[8]=($guidBytes[8]-band 63)-bor 128
    return '{'+(New-Object Guid (,$guidBytes)).ToString().ToUpperInvariant()+'}'
}
function Run([string]$Executable,[string[]]$Arguments,[string]$Log,[string]$WorkingDirectory) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName=$Executable; $start.WorkingDirectory=$WorkingDirectory; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $start.Arguments=(@($Arguments | ForEach-Object { if ($_.Contains('"') -or $_.EndsWith('\')) { throw 'Unsafe build command argument.' }; '"'+$_+'"' }) -join ' ')
    $process=$null
    for($attempt=1;$attempt -le 3;$attempt++) {
        try { $process=[Diagnostics.Process]::Start($start);break }
        catch {
            $errorCode=$null;$cause=$_.Exception
            while($null -ne $cause){if($cause -is [ComponentModel.Win32Exception]){$errorCode=$cause.NativeErrorCode;break};$cause=$cause.InnerException}
            Add-Content -LiteralPath ($Log+'.launch.jsonl') -Encoding UTF8 -Value (([ordered]@{attempt=$attempt;nativeError=$errorCode;executable=$Executable})|ConvertTo-Json -Compress)
            if(($errorCode -eq 5 -or $errorCode -eq 32) -and $attempt -lt 3){Start-Sleep -Seconds 2;continue};throw
        }
    }
    try {
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync(); $process.WaitForExit()
        $result=$stdout.Result+$stderr.Result; Write-Utf8 $Log $result
        if ($process.ExitCode -ne 0) { throw "Build step failed ($($process.ExitCode)): $Log`n$result" }
        return $result
    } finally { $process.Dispose() }
}
$architectures=if($Architecture -eq 'both'){@('x86','x64')}else{@($Architecture)}
$results=@()
foreach ($arch in $architectures) {
    $out=Join-Path $output $arch; [IO.Directory]::CreateDirectory($out) | Out-Null
    # Stable identity for the same release/architecture; failure-test packages have their own identity.
    $productCode=Get-StableGuid "$Version|$arch|$([bool]$RollbackTest)"
    $upgradeCode=if($arch -eq 'x64'){'{3489A60C-88FB-441D-A7AC-B80B7DB4084C}'}else{'{E4A1C33D-5D65-4931-963B-6E3CF87E38FB}'}
    $bitness=if($arch -eq 'x64'){'always64'}else{'always32'}
    $machine=if($arch -eq 'x64'){'0x8664'}else{'0x14c'}
    $files=@([pscustomobject]@{Name='VisibleCellsPaste.AddIn.dll';Source=(Join-Path $package "$arch/VisibleCellsPaste.AddIn.dll")})
    foreach($name in @('README.md','CHANGELOG.md','docs/architecture.md','docs/clipboard-compatibility.md','docs/undo-safety.md','docs/install-security.md','docs/test-report.md','docs/release-checklist.md','docs/native-format-research.md')) { $files += [pscustomobject]@{Name=$name.Replace('/','\');Source=(Join-Path $package $name)} }
    foreach($file in $files) {
        if(!(Test-Path -LiteralPath $file.Source -PathType Leaf)){throw "Missing payload: $($file.Source)"}
        $relative=$file.Source.Substring($package.Length+1).Replace('\','/')
        if(@($checksums|Where-Object{$_.Substring(66) -eq $relative}).Count -ne 1){throw "Payload not covered by full-build inventory: $relative"}
        $file | Add-Member NoteProperty Sha256 (Get-FileHash -LiteralPath $file.Source -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $assembly=[Reflection.AssemblyName]::GetAssemblyName($files[0].Source)
    if($assembly.Version.ToString() -ne $manifest.assemblyVersion){throw 'Payload assembly version differs from full build manifest.'}
    if($assembly.ProcessorArchitecture.ToString() -ne $(if($arch -eq 'x86'){'X86'}else{'Amd64'})){throw 'Payload PE/assembly architecture differs from requested MSI.'}
    $header="#pragma once`nconstexpr wchar_t VcpProductCode[] = $(ConvertTo-CppString $productCode);`nconstexpr wchar_t VcpAssemblyVersion[] = $(ConvertTo-CppString $assembly.Version.ToString());`nconstexpr wchar_t VcpAssemblyIdentity[] = $(ConvertTo-CppString $assembly.FullName);`nconstexpr wchar_t VcpArchitecture[] = $(ConvertTo-CppString $arch);`nconstexpr unsigned short VcpMachine = $machine;`nstruct VcpFile { const wchar_t* name; const wchar_t* sha256; };`nconst VcpFile VcpFiles[] = {`n"
    foreach($file in $files){$header+='    {'+(ConvertTo-CppString $file.Name)+','+(ConvertTo-CppString $file.Sha256)+"},`n"};$header+="};`n"
    Write-Utf8 (Join-Path $out 'MsiIdentity.h') $header
    $exports=if($arch -eq 'x86'){"EXPORTS`nVcpPreflight=_VcpPreflight@4`nVcpDeferred=_VcpDeferred@4`n"}else{"EXPORTS`nVcpPreflight`nVcpDeferred`n"}
    Write-Utf8 (Join-Path $out 'MsiGuard.def') $exports
    $compiler=Join-Path $VCToolsRoot "bin/Hostx64/$arch/cl.exe"
    foreach($required in @($compiler,(Join-Path $VCToolsRoot "lib/$arch/libcmt.lib"),(Join-Path $WindowsSdkRoot "Lib/$sdkVersion/um/$arch/msi.lib"),(Join-Path $WindowsSdkRoot "Lib/$sdkVersion/ucrt/$arch/libucrt.lib"))) { if(!(Test-Path -LiteralPath $required -PathType Leaf)){throw "Native build prerequisite missing: $required"} }
    $oldPath=$env:PATH; $oldInclude=$env:INCLUDE; $oldLib=$env:LIB
    try {
        $env:PATH=(Join-Path $VCToolsRoot "bin/Hostx64/$arch")+';'+$env:PATH
        $env:INCLUDE=@((Join-Path $VCToolsRoot 'include'),(Join-Path $WindowsSdkRoot "Include/$sdkVersion/ucrt"),(Join-Path $WindowsSdkRoot "Include/$sdkVersion/shared"),(Join-Path $WindowsSdkRoot "Include/$sdkVersion/um"),$out)-join ';'
        $env:LIB=@((Join-Path $VCToolsRoot "lib/$arch"),(Join-Path $WindowsSdkRoot "Lib/$sdkVersion/ucrt/$arch"),(Join-Path $WindowsSdkRoot "Lib/$sdkVersion/um/$arch"))-join ';'
        $dll=Join-Path $out 'VisibleCellsPaste.MsiGuard.dll'; $test=Join-Path $out 'MsiGuardTests.exe'
        $common=@('/nologo','/std:c++17','/EHsc','/MT','/O2','/W4','/WX','/utf-8','/guard:cf','/DUNICODE','/D_UNICODE','/D_WIN32_WINNT=0x0601')
        $link=@('/link','/DYNAMICBASE','/NXCOMPAT','/GUARD:CF','/WX',"/MACHINE:$($arch.ToUpperInvariant())",'msi.lib','bcrypt.lib','advapi32.lib')
        Run $compiler ($common+@('/LD',(Join-Path $product 'installer/MsiGuard.cpp'),('/Fo'+(Join-Path $out 'guard.obj')),('/Fe'+$dll))+$link+('/DEF:'+(Join-Path $out 'MsiGuard.def'))) (Join-Path $out 'guard-build.log') $out | Out-Null
        Run $compiler ($common+@((Join-Path $product 'installer/MsiGuardTests.cpp'),('/Fo'+(Join-Path $out 'guard-tests.obj')),('/Fe'+$test))+$link) (Join-Path $out 'guard-tests-build.log') $out | Out-Null
        $testOutput=Run $test @((Join-Path $out 'synthetic-fixtures')) (Join-Path $out 'guard-tests.log') $out
        $tests=($testOutput -split '[\r\n]+' | Where-Object { $_.StartsWith('{') } | Select-Object -Last 1) | ConvertFrom-Json
        if($tests.failed -ne 0 -or $tests.passed -ne 14){throw 'Guard regression tests incomplete.'}
    } finally { $env:PATH=$oldPath; $env:INCLUDE=$oldInclude; $env:LIB=$oldLib }
    $registrations=@()
    function Add-Reg([string]$Key,[string]$Name,[string]$Value,[string]$Type='string') { $script:registrations += [pscustomobject]@{Key=$Key;Name=$Name;Value=$Value;Type=$Type} }
    $cls='Software\Classes\CLSID\{856B2219-6225-42ED-8FF1-2D06E5913AC8}';$prog='Software\Classes\Workspace.VisibleCellsPaste';$addin='Software\Microsoft\Office\Excel\Addins\Workspace.VisibleCellsPaste'
    Add-Reg $cls '' 'VisibleCellsPaste.AddIn';Add-Reg ($cls+'\ProgId') '' 'Workspace.VisibleCellsPaste';Add-Reg $prog '' 'VisibleCellsPaste.AddIn';Add-Reg ($prog+'\CLSID') '' '{856B2219-6225-42ED-8FF1-2D06E5913AC8}'
    foreach($sub in @(($cls+'\InprocServer32'),($cls+'\InprocServer32\'+$assembly.Version.ToString()))) { Add-Reg $sub 'Class' 'VisibleCellsPaste.AddIn';Add-Reg $sub 'Assembly' $assembly.FullName;Add-Reg $sub 'RuntimeVersion' 'v4.0.30319';Add-Reg $sub 'CodeBase' '[VCPCODEBASE]' }
    Add-Reg ($cls+'\InprocServer32') '' 'mscoree.dll';Add-Reg ($cls+'\InprocServer32') 'ThreadingModel' 'Both'
    Add-Reg $addin 'FriendlyName' '보이는 칸 붙여넣기';Add-Reg $addin 'Description' '선택 범위 안의 보이는 칸에 복사한 값만 순서대로 입력합니다.';Add-Reg $addin 'LoadBehavior' '3' 'integer'
    Add-Reg 'Software\Workspace\VisibleCellsPasteMsi' 'ProductCode' $productCode;Add-Reg 'Software\Workspace\VisibleCellsPasteMsi' 'InstallFolder' '[INSTALLFOLDER]';Add-Reg 'Software\Workspace\VisibleCellsPasteMsi' 'Architecture' $arch
    $xml='<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"><Fragment><DirectoryRef Id="INSTALLFOLDER"><Directory Id="DOCFOLDER" Name="docs" /><Component Id="AddInProduct" Guid="*" Bitness="'+$bitness+'">'
    $index=0
    foreach($reg in $registrations) { $xml+='<RegistryValue Id="R'+$index+'" Root="HKCU" Key="'+(Xml $reg.Key)+'"'+$(if($reg.Name){' Name="'+(Xml $reg.Name)+'"'}else{''})+' Type="'+$reg.Type+'" Value="'+(Xml $reg.Value)+'"'+$(if($reg.Name -eq 'ProductCode'){' KeyPath="yes"'}else{''})+' />';$index++ }
    $xml+='<RemoveFolder Id="RemoveInstallFolder" On="uninstall" /></Component></DirectoryRef><ComponentGroup Id="ApplicationFiles">'
    $index=0
    foreach($file in $files) {
        $directory=if($file.Name.StartsWith('docs\')){'DOCFOLDER'}else{'INSTALLFOLDER'}
        $componentGuid=Get-StableGuid "file|$arch|$($file.Name)"
        $xml+='<Component Id="F'+$index+'" Directory="'+$directory+'" Guid="'+$componentGuid+'" Bitness="'+$bitness+'"><File Id="Payload'+$index+'" Source="'+(Xml $file.Source)+'" Name="'+(Xml ([IO.Path]::GetFileName($file.Name)))+'" /><RegistryValue Root="HKCU" Key="Software\Workspace\VisibleCellsPasteMsi\Files" Name="'+(Xml $file.Name)+'" Value="'+$file.Sha256+'" Type="string" KeyPath="yes" />'
        if($index -eq 3){$xml+='<RemoveFolder Id="RemoveDocsFolder" On="uninstall" />'}
        $xml+='</Component>';$index++
    }
    $xml+='</ComponentGroup></Fragment></Wix>';Write-Utf8 (Join-Path $out 'Payload.wxs') $xml
    $suffix=if($RollbackTest){'-rollback-test'}else{''};$msi=Join-Path $output "VisibleCellsPaste-$Version-$arch$suffix.msi"
    $wixArgs=@('build',(Join-Path $product 'installer/Product.wxs'),(Join-Path $out 'Payload.wxs'),'-arch',$arch,'-o',$msi,'-pdbtype','none','-d',"ProductVersion=$productVersion",'-d',"DisplayVersion=$Version",'-d',"ProductCode=$productCode",'-d',"UpgradeCode=$upgradeCode",'-d',"Architecture=$arch",'-d',"Bitness=$bitness",'-d',"GuardDll=$dll",'-d',"RollbackTest=$([int][bool]$RollbackTest)")
    Run $WixPath $wixArgs (Join-Path $out 'wix-build.log') $out | Out-Null
    $metadata=[ordered]@{schema=1;product='VisibleCellsPaste';version=$Version;productVersion=$productVersion;assemblyVersion=$assembly.Version.ToString();assemblyIdentity=$assembly.FullName;architecture=$arch;productCode=$productCode;upgradeCode=$upgradeCode;msi=$msi;sha256=(Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash.ToLowerInvariant();signed=$false;classification='unsigned release candidate';rollbackTest=[bool]$RollbackTest;files=$files;registrations=$registrations;guardSha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant();guardTests=$tests;installed=$false}
    Write-Utf8 ($msi+'.json') ($metadata|ConvertTo-Json -Depth 6)
    & (Join-Path $PSScriptRoot 'verify-msi.ps1') -MsiPath $msi
    $results+=$metadata
}
Write-Utf8 (Join-Path $output 'SHA256SUMS.txt') ((@($results|ForEach-Object{$_.sha256+'  '+[IO.Path]::GetFileName($_.msi)})-join "`n")+"`n")
Write-Utf8 (Join-Path $output 'build-results.json') ($results|ConvertTo-Json -Depth 6)
Write-Output "MSI output: $output"

