[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ExternalLocation,
    [string]$MakeAppx = ''
)
# This is a short-lived registration feasibility probe, not a product installer.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'package-common.ps1')
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$artifactRoot = Join-Path $repoRoot 'artifacts'
$probeName = 'ImageCopySave.UnsignedSparseProbe'
$probePublisher = 'CN=ImageCopySave.UnsignedSparseProbe, OID.2.25.311729368913984317654407730594956997722=1'
$probeVersion = '0.1.1.0'
$saveClsid = '9C030D44-BBFA-48B7-BD63-53470C112830'
$copyClsid = 'B481F5D0-A2B3-47D7-A139-B6C2F60B36DE'
$utf8 = New-Object Text.UTF8Encoding($false)
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N')

function Assert-PlainArtifactPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $artifactRoot.TrimEnd('\') + '\'
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Probe paths must be below this worktree artifacts directory.' }
    $current = $full
    while ($true) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Reparse point is not accepted: $current" }
        if ($current -eq $repoRoot) { break }
        $current = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrEmpty($current)) { throw 'Repository boundary was not reached.' }
    }
    return $full
}
function Get-ImageRegistrations {
    # Deliberately includes older and probe identities to prevent duplicate COM CLSIDs.
    @(Get-AppxPackage -Name 'ImageCopySave*' -ErrorAction Stop)
}
function Assert-NoImageRegistration {
    $existing = @(Get-ImageRegistrations)
    if ($existing.Count -ne 0) { throw 'An ImageCopySave registration already exists for this user. No registration or removal was attempted.' }
    foreach ($clsid in @($saveClsid, $copyClsid)) {
        foreach ($hive in @('HKCU:', 'HKLM:')) {
            if (Test-Path -LiteralPath "$hive\Software\Classes\CLSID\{$clsid}") { throw "An existing COM registration owns CLSID $clsid. No registration was attempted." }
        }
    }
}
function Get-ErrorEvidence($Record) {
    $chain = New-Object Collections.ArrayList
    $exception = $Record.Exception
    while ($null -ne $exception) {
        $native = $null
        if ($null -ne $exception.PSObject.Properties['NativeErrorCode']) { $native = $exception.NativeErrorCode }
        [void]$chain.Add([ordered]@{ type = $exception.GetType().FullName; message = $exception.Message; hresult = ('0x{0:X8}' -f $exception.HResult); nativeErrorCode = $native })
        $exception = $exception.InnerException
    }
    $details = $Record | Out-String
    $codes = @([regex]::Matches($details, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value.ToUpperInvariant() } | Select-Object -Unique)
    [ordered]@{ fullyQualifiedErrorId = $Record.FullyQualifiedErrorId; message = $details.Trim(); reportedHResults = $codes; exceptionChain = @($chain.ToArray()) }
}
function Write-ProbeResult {
    [IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 12), $utf8)
}

$runDirectory = Assert-PlainArtifactPath (Join-Path $artifactRoot ('image-copy-save/unsigned-identity-probe/' + $runId))
[IO.Directory]::CreateDirectory($runDirectory) | Out-Null
[void](Assert-PlainArtifactPath $runDirectory)
$resultPath = Join-Path $runDirectory 'result.json'
$result = [ordered]@{
    schemaVersion = 1; runId = $runId; startedUtc = [DateTime]::UtcNow.ToString('o')
    status = 'RUNNING'; stage = 'preflight'; registration = 'NOT RUN'; cleanup = 'NOT RUN'
    identity = $probeName; publisher = $probePublisher; version = $probeVersion; architecture = 'x64'
    securityChanged = $false; securitySettingsChangedByProbe = $false
    certificateMutation = $false; developerModeMutation = $false; policyMutation = $false; elevated = $null
    payloadModified = $false; explorerRestarted = $false; explorerG0 = 'NOT RUN'; productionRelease = $false
    registrationAttempted = $false; expectedPackageFullName = $null; remainingRegistrations = @()
}
$mutex = $null
$lockAcquired = $false
$attempted = $false
$expectedFullName = $null
$registrationError = $null
$cleanupError = $null
try {
    Write-ProbeResult
    if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use Windows PowerShell 5.1 (powershell.exe), which supplies the Appx module.' }
    if (-not [Environment]::Is64BitProcess -or [Environment]::OSVersion.Version.Build -lt 22000 -or [Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') { throw 'The probe requires Windows 11 x64 and a 64-bit PowerShell process.' }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $result.elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($result.elevated) { throw 'Run the probe in a non-elevated ordinary-user session. No elevation is requested.' }
    $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $result.os = [ordered]@{ build = $os.CurrentBuild; updateBuildRevision = $os.UBR; displayVersion = $os.DisplayVersion; processArchitecture = 'x64' }
    $appxCommand = Get-Command Add-AppxPackage -ErrorAction Stop
    if (-not $appxCommand.Parameters.ContainsKey('AllowUnsigned') -or -not $appxCommand.Parameters.ContainsKey('ExternalLocation')) { throw 'The installed Appx module does not provide both required probe options.' }
    $mutex = New-Object Threading.Mutex($false, 'Local\ImageCopySave.UnsignedSparseProbe')
    try { $lockAcquired = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $lockAcquired = $true }
    if (-not $lockAcquired) { throw 'Another unsigned identity probe is active.' }
    Assert-NoImageRegistration
    $result.preflightRegistrations = @()
    $external = Assert-PlainArtifactPath ((Resolve-Path -LiteralPath $ExternalLocation -ErrorAction Stop).Path)
    if (-not (Test-Path -LiteralPath $external -PathType Container)) { throw 'ExternalLocation must be a built package staging directory.' }
    $inputs = New-Object Collections.ArrayList
    foreach ($relative in @('ImageCopySave.Helper.exe', 'ImageCopySave.Shell.dll', 'ImageCopySave.Helper.runtimeconfig.json', 'ImageCopySave.Helper.deps.json', 'coreclr.dll', 'PresentationFramework.dll', 'Assets\StoreLogo.png', 'Assets\Square150x150Logo.png', 'Assets\Square44x44Logo.png')) {
        $file = Assert-PlainArtifactPath (Join-Path $external $relative)
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Required external payload file is absent: $relative" }
        [void]$inputs.Add([ordered]@{ path = $relative; bytes = (Get-Item -LiteralPath $file).Length; sha256 = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash })
    }
    $result.externalLocation = $external
    $result.payloadInputs = @($inputs.ToArray())
    $makeAppxPath = Resolve-ImageCopySaveSdkTool 'MakeAppx.exe' $MakeAppx
    $result.makeAppx = $makeAppxPath

    # Derive the exact full name using the OS API before any registration.
    if (-not ('ImageCopySaveProbe.PackageIdentity' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
namespace ImageCopySaveProbe {
    public static class PackageIdentity {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct PackageId {
            public uint Reserved;
            public uint Architecture;
            public ulong Version;
            [MarshalAs(UnmanagedType.LPWStr)] public string Name;
            [MarshalAs(UnmanagedType.LPWStr)] public string Publisher;
            [MarshalAs(UnmanagedType.LPWStr)] public string ResourceId;
            [MarshalAs(UnmanagedType.LPWStr)] public string PublisherId;
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern int PackageFullNameFromId(ref PackageId id, ref uint length, StringBuilder fullName);
        public static string FullName(string name, string publisher, string version) {
            var v = new Version(version);
            var id = new PackageId { Architecture = 9, Name = name, Publisher = publisher, ResourceId = "",
                Version = ((ulong)v.Major << 48) | ((ulong)v.Minor << 32) | ((ulong)v.Build << 16) | (uint)v.Revision };
            uint length = 0;
            int error = PackageFullNameFromId(ref id, ref length, null);
            if (error != 122) throw new Win32Exception(error);
            var value = new StringBuilder((int)length);
            error = PackageFullNameFromId(ref id, ref length, value);
            if (error != 0) throw new Win32Exception(error);
            return value.ToString();
        }
    }
}
'@
    }
    $expectedFullName = [ImageCopySaveProbe.PackageIdentity]::FullName($probeName, $probePublisher, $probeVersion)
    $result.expectedPackageFullName = $expectedFullName
    $manifestDirectory = Join-Path $runDirectory 'identity'
    [IO.Directory]::CreateDirectory($manifestDirectory) | Out-Null
    $manifestPath = Join-Path $manifestDirectory 'AppxManifest.xml'
    $manifest = @"
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
 xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
 xmlns:uap10="http://schemas.microsoft.com/appx/manifest/uap/windows10/10"
 xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities"
 xmlns:com="http://schemas.microsoft.com/appx/manifest/com/windows10"
 xmlns:desktop4="http://schemas.microsoft.com/appx/manifest/desktop/windows10/4"
 xmlns:desktop5="http://schemas.microsoft.com/appx/manifest/desktop/windows10/5"
 IgnorableNamespaces="uap uap10 rescap com desktop4 desktop5">
 <Identity Name="$probeName" Publisher="$probePublisher" Version="$probeVersion" ProcessorArchitecture="x64" />
 <Properties><DisplayName>ImageCopySave unsigned identity probe</DisplayName><PublisherDisplayName>ImageCopySave probe</PublisherDisplayName><Logo>Assets\StoreLogo.png</Logo><uap10:AllowExternalContent>true</uap10:AllowExternalContent></Properties>
 <Resources><Resource Language="ko-KR" /></Resources>
 <Dependencies><TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.22000.0" MaxVersionTested="10.0.22631.0" /></Dependencies>
 <Applications>
  <Application Id="ImageCopySave" Executable="ImageCopySave.Helper.exe" uap10:RuntimeBehavior="win32App" uap10:TrustLevel="mediumIL">
   <uap:VisualElements DisplayName="ImageCopySave probe" Description="Temporary unsigned identity probe" BackgroundColor="transparent" Square150x150Logo="Assets\Square150x150Logo.png" Square44x44Logo="Assets\Square44x44Logo.png" AppListEntry="none" />
   <Extensions>
    <com:Extension Category="windows.comServer"><com:ComServer><com:SurrogateServer DisplayName="ImageCopySave probe commands">
     <com:Class Id="$saveClsid" Path="ImageCopySave.Shell.dll" ThreadingModel="STA" />
     <com:Class Id="$copyClsid" Path="ImageCopySave.Shell.dll" ThreadingModel="STA" />
    </com:SurrogateServer></com:ComServer></com:Extension>
    <desktop4:Extension Category="windows.fileExplorerContextMenus"><desktop4:FileExplorerContextMenus>
     <desktop5:ItemType Type="Directory\Background"><desktop5:Verb Id="SaveImage" Clsid="$saveClsid" /></desktop5:ItemType>
     <desktop5:ItemType Type="*"><desktop5:Verb Id="CopyImage" Clsid="$copyClsid" /></desktop5:ItemType>
    </desktop4:FileExplorerContextMenus></desktop4:Extension>
   </Extensions>
  </Application>
 </Applications>
 <Capabilities><rescap:Capability Name="runFullTrust" /><rescap:Capability Name="unvirtualizedResources" /></Capabilities>
</Package>
"@
    [IO.File]::WriteAllText($manifestPath, $manifest, $utf8)
    $packagePath = Join-Path $runDirectory 'ImageCopySave.UnsignedSparseProbe.msix'
    $result.stage = 'makeappx-pack'
    $result.package = $packagePath
    $result.makeAppxValidation = 'Documented /nv for external-location references; registration performs OS validation.'
    Write-ProbeResult
    # /nv is Microsoft's documented sparse-package packing option: all binary/logo paths are external.
    $packArguments = @('pack', '/d', ('"' + $manifestDirectory + '"'), '/p', ('"' + $packagePath + '"'), '/nv')
    $pack = Start-Process -FilePath $makeAppxPath -ArgumentList $packArguments -WindowStyle Hidden -PassThru -Wait -RedirectStandardOutput (Join-Path $runDirectory 'makeappx.stdout.log') -RedirectStandardError (Join-Path $runDirectory 'makeappx.stderr.log')
    $result.makeAppxExitCode = $pack.ExitCode
    if ($pack.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw 'MakeAppx failed; see the owned run directory logs.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $entries = @($archive.Entries | ForEach-Object { $_.FullName })
        foreach ($entry in $entries) {
            if ($entry -cnotin @('AppxManifest.xml', 'AppxBlockMap.xml', '[Content_Types].xml')) { throw "Unexpected identity-only package entry: $entry" }
        }
        foreach ($required in @('AppxManifest.xml', 'AppxBlockMap.xml', '[Content_Types].xml')) {
            if (@($entries | Where-Object { $_ -ceq $required }).Count -ne 1) { throw "Package footprint mismatch: $required" }
        }
        $stream = $archive.GetEntry('AppxManifest.xml').Open()
        $reader = New-Object IO.StreamReader($stream)
        try { if ($reader.ReadToEnd() -cne $manifest) { throw 'Packaged manifest differs from the fixed probe manifest.' } }
        finally { $reader.Dispose() }
    } finally { $archive.Dispose() }
    $result.signaturePresent = $false
    $result.packageSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
    $result.packageBytes = (Get-Item -LiteralPath $packagePath).Length
    foreach ($inputFile in $inputs) {
        if ((Get-FileHash -LiteralPath (Join-Path $external $inputFile.path) -Algorithm SHA256).Hash -cne $inputFile.sha256) { throw 'External payload changed before registration.' }
    }
    Assert-NoImageRegistration
    $result.stage = 'register-current-user'
    $result.registrationAttempted = $true
    $attempted = $true
    Write-ProbeResult
    try {
        Add-AppxPackage -Path $packagePath -ExternalLocation $external -AllowUnsigned -ErrorAction Stop
    } catch {
        $registrationError = $_
        $result.registration = 'BLOCKED'
        $result.status = 'BLOCKED'
        $result.registrationError = Get-ErrorEvidence $_
        $errorText = $_ | Out-String
        $activityMatch = [regex]::Match($errorText, '(?i)ActivityId[^0-9a-f]*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')
        if ($activityMatch.Success) {
            $result.activityId = $activityMatch.Groups[1].Value
            try { Get-AppxLog -ActivityID $result.activityId -ErrorAction Stop | Format-List * | Out-File -LiteralPath (Join-Path $runDirectory 'deployment-events.log') -Encoding utf8 }
            catch { $result.deploymentEventReadError = $_.Exception.Message }
        }
    }
    if ($null -eq $registrationError) {
        $registered = @(Get-ImageRegistrations)
        if ($registered.Count -ne 1 -or $registered[0].PackageFullName -cne $expectedFullName -or $registered[0].Name -cne $probeName -or $registered[0].Publisher -cne $probePublisher -or [version]$registered[0].Version -ne [version]$probeVersion -or [string]$registered[0].Architecture -ine 'X64' -or [string]$registered[0].Status -ne 'Ok') { throw 'Registration did not produce exactly the expected healthy package identity.' }
        $result.registeredPackage = $registered[0] | Select-Object Name, Publisher, Version, Architecture, PackageFullName, Status, InstallLocation, IsDevelopmentMode
        $result.registration = 'PASS'
        $result.status = 'PASS'
    }
} catch {
    $result.status = 'FAIL'
    $result.error = Get-ErrorEvidence $_
} finally {
    if ($attempted) {
        $result.stage = 'cleanup-owned-identity'
        try {
            $currentPackages = @(Get-ImageRegistrations)
            $owned = @($currentPackages | Where-Object { $_.PackageFullName -ceq $expectedFullName -and $_.Name -ceq $probeName -and $_.Publisher -ceq $probePublisher -and [version]$_.Version -eq [version]$probeVersion -and [string]$_.Architecture -ieq 'X64' })
            if ($owned.Count -gt 1) { throw 'Duplicate exact identities found; no ambiguous removal was attempted.' }
            if ($owned.Count -eq 1) {
                Remove-AppxPackage -Package $expectedFullName -ErrorAction Stop
                $result.removedPackageFullName = $expectedFullName
            }
            $remaining = @(Get-ImageRegistrations)
            $result.remainingRegistrations = @($remaining | Select-Object Name, Publisher, Version, PackageFullName)
            if ($remaining.Count -ne 0) { throw 'An ImageCopySave identity remains; only this run exact identity may be removed automatically.' }
            $result.cleanup = 'PASS'
            $result.noRegistrationAfterProbe = $true
        } catch {
            $cleanupError = $_
            $result.cleanup = 'FAIL'
            $result.status = 'FAIL'
            $result.noRegistrationAfterProbe = $false
            $result.cleanupError = Get-ErrorEvidence $_
        }
    }
    if ($lockAcquired) { $mutex.ReleaseMutex() }
    if ($null -ne $mutex) { $mutex.Dispose() }
    $result.finishedUtc = [DateTime]::UtcNow.ToString('o')
    $result.stage = 'complete'
    Write-ProbeResult
    Write-Host ('Probe result: ' + $result.status + '; registration=' + $result.registration + '; cleanup=' + $result.cleanup)
    Write-Host ('Evidence: ' + $resultPath)
}
# Distinguish an OS refusal from a broken probe or failed cleanup.
if ($result.status -eq 'BLOCKED') { exit 2 }
if ($result.status -ne 'PASS') { exit 1 }
