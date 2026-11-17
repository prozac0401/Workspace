#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '3.0.0',
    [string]$Wix,
    [switch]$SkipTests
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if([version]$Version -lt [version]'3.0.0') { throw 'This source requires package version 3.0.0 or later. Use the preserved earlier source for an earlier version.' }
$displayVersion=([version]$Version).Major.ToString()
$toolRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = [IO.Path]::GetFullPath((Join-Path $toolRoot '..\..'))
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$compiler = Join-Path $framework 'csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The Windows .NET Framework 4.8 x64 compiler is required.' }
if (-not $Wix) { $Wix = Join-Path $repoRoot '.tools\wix\wix.exe' }
$Wix = (Resolve-Path -LiteralPath $Wix).Path
$runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$outRoot = Join-Path $repoRoot ('artifacts\excel-password-safe\build-' + $Version + '-' + $runId)
$stage = Join-Path $outRoot 'package'
$runtime = Join-Path $stage 'runtime'
$icon = Join-Path $toolRoot 'assets\ExcelPasswordSafe.ico'
if(-not (Test-Path -LiteralPath $icon)) { throw 'The application padlock icon is missing.' }
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$record = [ordered]@{version=$Version;displayVersion=$displayVersion;timestamp=[DateTimeOffset]::Now.ToString('O');status='Failed';productionRelease=$false;signing='Unsigned';tests='NotRun';msi=$null;sha256=$null;installerLifecycle='NotRun';explorerClick='NotRun'}
$utf8 = New-Object Text.UTF8Encoding($true)
function Xml([string]$s) { [Security.SecurityElement]::Escape($s) }
function Component-Guid([string]$RelativePath) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $bytes=$sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('ExcelPasswordSafe.Payload.v1/'+$RelativePath.ToLowerInvariant())) }
    finally { $sha.Dispose() }
    [byte[]]$guidBytes=$bytes[0..15]
    return ([guid]::new($guidBytes)).ToString('D')
}
function Source-Stamp {
    $inputs=@(Get-ChildItem -LiteralPath (Join-Path $toolRoot 'app'),(Join-Path $toolRoot 'runtime'),(Join-Path $toolRoot 'build'),(Join-Path $toolRoot 'installer'),(Join-Path $toolRoot 'tests'),(Join-Path $toolRoot 'assets') -Recurse -File)
    $inputs += Get-Item -LiteralPath (Join-Path $toolRoot 'README.md')
    return (@($inputs | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($toolRoot.Length+1)+' '+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "`n")
}
function Invoke-Checked([string]$File,[string[]]$Arguments,[string]$Log) {
    if(-not (Test-Path -LiteralPath $File)) { throw ('Executable not found: '+$File) }
    $savedPreference=$ErrorActionPreference
    try {
        # Windows PowerShell exposes native stderr as ErrorRecord objects. Capture
        # those in the log, then use the native exit code as the failure signal.
        $ErrorActionPreference='Continue'
        $lines = & $File @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference=$savedPreference }
    $lines | Out-File -LiteralPath $Log -Encoding utf8
    if ($code -ne 0) { throw "Command failed ($code): $File. See $Log" }
}
try {
    $sourceBefore=Source-Stamp
    $sources = @(Get-ChildItem -LiteralPath (Join-Path $toolRoot 'app') -Filter '*.cs' -File | Sort-Object Name)
    if (-not $sources.Count) { throw 'No app/*.cs source files were found.' }
    $references = @('System.dll','System.Core.dll','System.Security.dll','System.Web.Extensions.dll','System.Xaml.dll','System.Xml.dll','System.Drawing.dll','System.Windows.Forms.dll') | ForEach-Object { '/reference:' + (Join-Path $framework $_) }
    $references += @('PresentationFramework.dll','PresentationCore.dll','WindowsBase.dll') | ForEach-Object { '/reference:' + (Join-Path $framework ('WPF\' + $_)) }
    $exe = Join-Path $stage 'ExcelPasswordSafe.exe'
    $assemblyInfo=Join-Path $outRoot 'AssemblyInfo.cs'
    [IO.File]::WriteAllText($assemblyInfo, ('using System.Reflection; [assembly: AssemblyTitle("ExcelPasswordSafe '+$displayVersion+'")] [assembly: AssemblyProduct("ExcelPasswordSafe '+$displayVersion+'")] [assembly: AssemblyCompany("Workspace")] [assembly: AssemblyVersion("'+$Version+'.0")] [assembly: AssemblyFileVersion("'+$Version+'.0")] [assembly: AssemblyInformationalVersion("'+$displayVersion+'")]'), $utf8)
    [xml]$manifest=Get-Content -LiteralPath (Join-Path $toolRoot 'installer\app.manifest') -Raw -Encoding UTF8
    $manifest.assembly.assemblyIdentity.SetAttribute('version',($Version+'.0'))
    $buildManifest=Join-Path $outRoot 'app.manifest'
    $manifest.Save($buildManifest)
    $compileArgs = @('/nologo','/target:winexe','/platform:anycpu','/optimize+','/warnaserror+','/utf8output',('/out:'+$exe),('/win32manifest:'+$buildManifest),('/win32icon:'+$icon),('/resource:'+$icon+',ExcelPasswordSafe.AppIcon.ico')) + $references + @($sources.FullName) + @($assemblyInfo)
    Invoke-Checked $compiler $compileArgs (Join-Path $outRoot 'compile.log')
    [IO.File]::WriteAllText((Join-Path $stage 'ExcelPasswordSafe.exe.config'), '<?xml version="1.0" encoding="utf-8"?><configuration><startup useLegacyV2RuntimeActivationPolicy="true"><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8"/></startup></configuration>', $utf8)
    foreach ($name in @('Common.ps1','Engine.ps1','ExcelPassword.Worker.ps1','BatchEngine.ps1')) {
        Copy-Item -LiteralPath (Join-Path $toolRoot ('runtime\'+$name)) -Destination (Join-Path $runtime $name)
    }
    Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md') -Destination (Join-Path $stage 'README.md')
    if (-not $SkipTests) {
        $ps = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Invoke-Checked $ps @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $toolRoot 'tests\Test-Core.ps1'),'-EvidenceDirectory',(Join-Path $outRoot 'core-tests')) (Join-Path $outRoot 'core-tests.log')
        Invoke-Checked $ps @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $toolRoot 'tests\Test-ControllerFailures.ps1'),'-EvidenceDirectory',(Join-Path $outRoot 'controller-faults')) (Join-Path $outRoot 'controller-faults.log')
        Invoke-Checked $ps @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $toolRoot 'tests\Test-Signature.ps1'),'-EvidenceDirectory',(Join-Path $outRoot 'signature-tests')) (Join-Path $outRoot 'signature-tests.log')
        Invoke-Checked $ps @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $toolRoot 'tests\Test-SessionController.ps1'),'-EvidenceDirectory',(Join-Path $outRoot 'session-tests')) (Join-Path $outRoot 'session-tests.log')
        Invoke-Checked $ps @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $toolRoot 'tests\Test-WorkerSession.ps1'),'-EvidenceDirectory',(Join-Path $outRoot 'worker-session-tests')) (Join-Path $outRoot 'worker-session-tests.log')
        Invoke-Checked $ps @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $toolRoot 'tests\Test-Batch.ps1'),'-EvidenceDirectory',(Join-Path $outRoot 'batch-tests')) (Join-Path $outRoot 'batch-tests.log')
        Invoke-Checked $ps @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $toolRoot 'tests\Test-App.ps1'),'-AppPath',$exe,'-OutputDirectory',(Join-Path $outRoot 'app-tests')) (Join-Path $outRoot 'app-tests.log')
        Invoke-Checked $ps @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $toolRoot 'tests\Test-Wizard.ps1'),'-AppPath',$exe,'-OutputDirectory',(Join-Path $outRoot 'wizard-tests')) (Join-Path $outRoot 'wizard-tests.log')
        $smoke = Join-Path $outRoot 'ui-smoke'
        $process = Start-Process -FilePath $exe -ArgumentList ('--smoke "'+$smoke+'"') -PassThru -WindowStyle Hidden
        if (-not $process.WaitForExit(60000)) { throw 'UI smoke did not finish in 60 seconds. Inspect the test process manually.' }
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $smoke 'smoke-result.json'))) { throw 'UI smoke failed or produced no result.' }
        $record.tests = 'Core/controller faults/signature/session/worker session/batch/App/Wizard/UI smoke passed'
    }
    $files = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName)
    $fragment = New-Object Text.StringBuilder
    [void]$fragment.AppendLine('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"><Fragment><ComponentGroup Id="ApplicationFiles">')
    for ($i=0; $i -lt $files.Count; $i++) {
        $relative = $files[$i].FullName.Substring($stage.Length+1)
        $directory = if ($relative.StartsWith('runtime\')) { 'RUNTIMEDIR' } else { 'INSTALLFOLDER' }
        $id = 'Payload' + $i
        [void]$fragment.AppendLine(('<Component Id="{0}" Directory="{1}" Guid="{5}"><File Id="{0}File" Source="{2}"/><RegistryValue Root="HKCU" Key="Software\Workspace\ExcelPasswordSafe\Files" Name="{3}" Value="{4}" Type="string" KeyPath="yes"/></Component>' -f $id,$directory,(Xml $files[$i].FullName),(Xml $relative),(Xml $Version),(Component-Guid $relative)))
    }
    [void]$fragment.AppendLine('</ComponentGroup></Fragment><Fragment><ComponentGroup Id="ExplorerCommands">')
    $folderVerbs=@(
        @{id='01Encrypt';mode='Encrypt';label='&#xC554;&#xD638; &#xC124;&#xC815;'},
        @{id='02Decrypt';mode='Decrypt';label='&#xC554;&#xD638; &#xD574;&#xC81C;'},
        @{id='03ChangePassword';mode='ChangePassword';label='&#xC554;&#xD638; &#xBCC0;&#xACBD;'}
    )
    foreach ($extension in @('xls','xlsx','xlsm','xlsb')) {
        $key = 'Software\Classes\SystemFileAssociations\.' + $extension + '\shell\Workspace.ExcelPasswordSafe'
        [void]$fragment.AppendLine(('<Component Id="Menu_{0}" Directory="INSTALLFOLDER" Guid="*">' -f $extension))
        [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="MUIVerb" Value="Excel &#xC554;&#xD638; &#xAD00;&#xB9AC;" Type="string" KeyPath="yes"/>' -f $key))
        [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="SubCommands" Value="" Type="string"/>' -f $key))
        [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="MultiSelectModel" Value="Single" Type="string"/>' -f $key))
        [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="Icon" Value="&quot;[INSTALLFOLDER]ExcelPasswordSafe.exe&quot;,0" Type="string"/>' -f $key))
        foreach($verb in $folderVerbs) {
            $verbKey=$key+'\shell\'+$verb.id
            [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="MUIVerb" Value="{1}" Type="string"/>' -f $verbKey,$verb.label))
            [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="MultiSelectModel" Value="Single" Type="string"/>' -f $verbKey))
            [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}\command" Value="&quot;[INSTALLFOLDER]ExcelPasswordSafe.exe&quot; --file &quot;%1&quot; --mode {1}" Type="string"/>' -f $verbKey,$verb.mode))
        }
        [void]$fragment.AppendLine('</Component>')
    }
    $folderMenus=@(
        @{component='FolderMenu';key='Software\Classes\Directory\shell\Workspace.ExcelPasswordSafe';argument='%1'},
        @{component='BackgroundMenu';key='Software\Classes\Directory\Background\shell\Workspace.ExcelPasswordSafe';argument='%V\.'}
    )
    foreach($menu in $folderMenus) {
    $folderKey=$menu.key
    [void]$fragment.AppendLine(('<Component Id="{0}" Directory="INSTALLFOLDER" Guid="*">' -f $menu.component))
    [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="MUIVerb" Value="Excel &#xC554;&#xD638; &#xAD00;&#xB9AC;" Type="string" KeyPath="yes"/>' -f $folderKey))
    [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="SubCommands" Value="" Type="string"/>' -f $folderKey))
    [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="MultiSelectModel" Value="Single" Type="string"/>' -f $folderKey))
    [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="Icon" Value="&quot;[INSTALLFOLDER]ExcelPasswordSafe.exe&quot;,0" Type="string"/>' -f $folderKey))
    foreach($verb in $folderVerbs) {
        $key=$folderKey+'\shell\'+$verb.id
        [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="MUIVerb" Value="{1}" Type="string"/>' -f $key,$verb.label))
        [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}" Name="MultiSelectModel" Value="Single" Type="string"/>' -f $key))
        [void]$fragment.AppendLine(('<RegistryValue Root="HKCU" Key="{0}\command" Value="&quot;[INSTALLFOLDER]ExcelPasswordSafe.exe&quot; --folder &quot;{2}&quot; --mode {1}" Type="string"/>' -f $key,$verb.mode,$menu.argument))
    }
    [void]$fragment.AppendLine('</Component>')
    }
    [void]$fragment.AppendLine('</ComponentGroup></Fragment></Wix>')
    $payloadWxs = Join-Path $outRoot 'Payload.wxs'
    [IO.File]::WriteAllText($payloadWxs,$fragment.ToString(),$utf8)
    $msi = Join-Path $outRoot ('ExcelPasswordSafe-'+$displayVersion+'-win-x64.msi')
    Invoke-Checked $Wix @('build','-arch','x64','-d',('Version='+$Version),'-d',('DisplayVersion='+$displayVersion),'-d',('IconPath='+$icon),'-out',$msi,(Join-Path $toolRoot 'installer\Package.wxs'),$payloadWxs) (Join-Path $outRoot 'wix-build.log')
    $verify = & (Join-Path $toolRoot 'installer\verify-msi.ps1') -MsiPath $msi
    $verify | Set-Content -LiteralPath (Join-Path $outRoot 'msi-verification.json') -Encoding UTF8
    $extracted=Join-Path $outRoot 'extracted'
    Invoke-Checked $Wix @('msi','decompile',$msi,'-x',$extracted,'-o',(Join-Path $outRoot 'decompiled.wxs')) (Join-Path $outRoot 'msi-extraction.log')
    for($i=0; $i -lt $files.Count; $i++) {
        $extractedFile=Join-Path $extracted ('File\Payload'+$i+'File')
        if((Get-FileHash -LiteralPath $extractedFile -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $files[$i].FullName -Algorithm SHA256).Hash) { throw ('MSI embedded payload mismatch: '+$files[$i].Name) }
    }
    if((Source-Stamp) -cne $sourceBefore) { throw 'Sources changed during the build. Rebuild from the completed source state.' }
    [IO.File]::WriteAllText((Join-Path $outRoot 'source-sha256.txt'),$sourceBefore,$utf8)
    $record.embeddedPayload=('All '+$files.Count+' extracted file hashes match staging')
    $record.msi = $msi
    $record.sha256 = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
    ($record.sha256+'  '+[IO.Path]::GetFileName($msi)) | Set-Content -LiteralPath ($msi+'.sha256') -Encoding ASCII
    $record.status = 'Pass'
    $record.payload = @($files | ForEach-Object { @{path=$_.FullName.Substring($stage.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })
} catch {
    $record.failure=$_.Exception.Message
    throw
} finally {
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outRoot 'build-result.json') -Encoding UTF8
}
Write-Output ('MSI: '+$record.msi)
Write-Output ('Evidence: '+$outRoot)
