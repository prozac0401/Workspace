[CmdletBinding()]
param(
    [string]$DotNet = 'dotnet',
    [string]$MakeAppx = '',
    [ValidateNotNullOrEmpty()][string]$Publisher = 'CN=ImageCopySave.Evaluation',
    [ValidatePattern('^\d+\.\d+\.\d+\.\d+$')][string]$Version = '0.1.1.0'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$toolRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $toolRoot '../..')).Path
$outputRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts/image-copy-save/package-evaluation'))
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Assert-OwnedPlainPath([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    $prefix = $repoRoot.TrimEnd('\') + '\'
    if ($full -ne $repoRoot -and -not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the repository: $full"
    }
    $current = $full
    while ($true) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Reparse points are not allowed in packaging paths: $current"
        }
        if ($current -eq $repoRoot) { break }
        $current = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrEmpty($current)) { throw 'Repository path boundary was not reached.' }
    }
    return $full
}
function New-OwnedDirectory([string]$Path) {
    $full = Assert-OwnedPlainPath $Path
    [IO.Directory]::CreateDirectory($full) | Out-Null
    [void](Assert-OwnedPlainPath $full)
}
function Get-PlainFiles([string]$Directory) {
    [void](Assert-OwnedPlainPath $Directory)
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    $pending.Enqueue($Directory)
    while ($pending.Count -gt 0) {
        $current = $pending.Dequeue()
        foreach ($item in Get-ChildItem -LiteralPath $current -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse point in package content: $($item.FullName)"
            }
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) }
            else { Write-Output $item }
        }
    }
}
function Resolve-Executable([string]$Value) {
    $command = Get-Command $Value -CommandType Application -ErrorAction Stop | Select-Object -First 1
    if ($null -eq $command) { throw "Executable was not found: $Value" }
    return $command.Source
}
function Find-MakeAppx {
    if (-not [string]::IsNullOrWhiteSpace($MakeAppx)) { return Resolve-Executable $MakeAppx }
    $command = Get-Command 'MakeAppx.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) { return $command.Source }
    $localSdkBin = Join-Path $repoRoot '.tools/image-copy-save-native/sdk/bin'
    if (Test-Path -LiteralPath $localSdkBin -PathType Container) {
        foreach ($version in Get-ChildItem -LiteralPath $localSdkBin -Directory | Sort-Object Name -Descending) {
            $candidate = Join-Path $version.FullName 'x64/MakeAppx.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $sdkBin = Join-Path $programFilesX86 'Windows Kits/10/bin'
    if (Test-Path -LiteralPath $sdkBin -PathType Container) {
        foreach ($version in Get-ChildItem -LiteralPath $sdkBin -Directory | Sort-Object Name -Descending) {
            if ($version.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $candidate = Join-Path $version.FullName 'x64/MakeAppx.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    throw 'MakeAppx.exe was not found. Supply -MakeAppx with an existing Windows SDK x64 tool path. This script does not install an SDK.'
}
function Write-Result {
    [void](Assert-OwnedPlainPath $resultPath)
    [IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 12), $utf8)
}
function Invoke-RecordedProcess([string]$Executable, [string[]]$Arguments, [string]$Name) {
    $logPath = Join-Path $logs ($Name + '.log')
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.WorkingDirectory = $repoRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $quoted = foreach ($argument in $Arguments) {
        if ($argument.Contains('"') -or $argument.EndsWith('\')) { throw 'Unsupported command argument quoting.' }
        '"' + $argument + '"'
    }
    $info.Arguments = $quoted -join ' '
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $info
    $started = [DateTime]::UtcNow
    $text = ''
    $exitCode = $null
    try {
        if (-not $process.Start()) { throw "Could not start $Executable" }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $text = $stdout.Result + [Environment]::NewLine + $stderr.Result
        $exitCode = $process.ExitCode
        if ($exitCode -ne 0) { throw "$Name failed with exit code $exitCode. See $logPath" }
    } catch {
        $text += [Environment]::NewLine + $_.Exception.Message
        throw
    } finally {
        [IO.File]::WriteAllText($logPath, $text, $utf8)
        [void]$steps.Add([ordered]@{
            name = $Name; executable = $Executable; arguments = $Arguments
            exitCode = $exitCode; log = $logPath
            elapsedMilliseconds = [math]::Round(([DateTime]::UtcNow - $started).TotalMilliseconds)
        })
        $process.Dispose()
    }
    Write-Host "$Name completed. Log: $logPath"
}
function Get-PeInfo([string]$Path, [bool]$ExpectDll) {
    $stream = [IO.File]::OpenRead($Path)
    $reader = New-Object IO.BinaryReader($stream)
    try {
        if ($stream.Length -lt 64 -or $reader.ReadUInt16() -ne 0x5A4D) { throw "Not a PE file: $Path" }
        $stream.Position = 0x3C
        $offset = $reader.ReadInt32()
        if ($offset -lt 64 -or $offset -gt ($stream.Length - 26)) { throw "Invalid PE header offset: $Path" }
        $stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x00004550) { throw "Missing PE signature: $Path" }
        $machine = $reader.ReadUInt16()
        $stream.Position = $offset + 22
        $characteristics = $reader.ReadUInt16()
        $optionalMagic = $reader.ReadUInt16()
        $isDll = ($characteristics -band 0x2000) -ne 0
        if ($machine -ne 0x8664 -or $optionalMagic -ne 0x20B -or $isDll -ne $ExpectDll) {
            throw "Expected an x64 PE32+ file (DLL=$ExpectDll): $Path"
        }
        return [ordered]@{ path = $Path; machine = '0x8664'; format = 'PE32+'; isDll = $isDll; sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    } finally { $reader.Dispose(); $stream.Dispose() }
}
function Get-ManagedSourceInventory {
    $paths = New-Object 'System.Collections.Generic.List[string]'
    $pending = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($project in @('ImageCopySave.Helper', 'ImageCopySave.Engine')) { $pending.Enqueue((Join-Path $toolRoot ('source/' + $project))) }
    while ($pending.Count -gt 0) {
        $directory = $pending.Dequeue()
        [void](Assert-OwnedPlainPath $directory)
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
            if ($item.PSIsContainer -and $item.Name -in @('bin', 'obj')) { continue }
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Managed source inputs must not be reparse points.' }
            if ($item.PSIsContainer) { $pending.Enqueue($item.FullName) }
            else { $paths.Add($item.FullName) }
        }
    }
    foreach ($directory in @($repoRoot, (Join-Path $repoRoot 'tools'), $toolRoot, (Join-Path $toolRoot 'source'))) {
        foreach ($name in @('Directory.Build.props', 'Directory.Build.targets', 'Directory.Packages.props', 'global.json', 'NuGet.Config')) {
            $path = Join-Path $directory $name
            if (Test-Path -LiteralPath $path -PathType Leaf) { [void](Assert-OwnedPlainPath $path); $paths.Add($path) }
        }
    }
    return @($paths | Sort-Object -Unique | ForEach-Object {
        [ordered]@{ path = $_.Substring($repoRoot.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash }
    })
}
function Get-SourceClsid([string]$Text, [string]$Name) {
    $match = [regex]::Match($Text, '(?s)' + [regex]::Escape($Name) + '\s*=\s*\{([^;]+)\};')
    if (-not $match.Success) { throw "Missing native CLSID definition: $Name" }
    $parts = @([regex]::Matches($match.Groups[1].Value, '0x([0-9a-fA-F]+)') | ForEach-Object { [Convert]::ToUInt32($_.Groups[1].Value, 16) })
    if ($parts.Count -ne 11) { throw "Invalid native CLSID definition: $Name" }
    return ('{0:x8}-{1:x4}-{2:x4}-{3:x2}{4:x2}-{5:x2}{6:x2}{7:x2}{8:x2}{9:x2}{10:x2}' -f $parts)
}
function Assert-Manifest([string]$Directory) {
    [xml]$xml = [IO.File]::ReadAllText((Join-Path $Directory 'AppxManifest.xml'))
    $ns = New-Object Xml.XmlNamespaceManager($xml.NameTable)
    $ns.AddNamespace('f', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
    $ns.AddNamespace('uap', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')
    $ns.AddNamespace('uap10', 'http://schemas.microsoft.com/appx/manifest/uap/windows10/10')
    $ns.AddNamespace('com', 'http://schemas.microsoft.com/appx/manifest/com/windows10')
    $ns.AddNamespace('d4', 'http://schemas.microsoft.com/appx/manifest/desktop/windows10/4')
    $ns.AddNamespace('d5', 'http://schemas.microsoft.com/appx/manifest/desktop/windows10/5')
    $ns.AddNamespace('rescap', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities')
    $identity = $xml.SelectSingleNode('/f:Package/f:Identity', $ns)
    if ($null -eq $identity -or $identity.GetAttribute('Name') -ne 'ImageCopySave.Evaluation' -or $identity.GetAttribute('Publisher') -cne $Publisher -or $identity.GetAttribute('Version') -ne $Version -or $identity.GetAttribute('ProcessorArchitecture') -ne 'x64') { throw 'Unexpected evaluation identity or architecture.' }
    $target = $xml.SelectSingleNode('/f:Package/f:Dependencies/f:TargetDeviceFamily', $ns)
    if ($null -eq $target -or $target.GetAttribute('Name') -ne 'Windows.Desktop' -or $target.GetAttribute('MinVersion') -ne '10.0.22000.0' -or $target.GetAttribute('MaxVersionTested') -ne '10.0.22000.0') { throw 'Unexpected target device family.' }
    $apps = $xml.SelectNodes('/f:Package/f:Applications/f:Application', $ns)
    if ($apps.Count -ne 1) { throw 'Exactly one helper application is required.' }
    $app = $apps[0]
    if ($app.Id -ne 'ImageCopySave' -or $app.Executable -ne 'ImageCopySave.Helper.exe' -or $app.GetAttribute('RuntimeBehavior', $ns.LookupNamespace('uap10')) -ne 'packagedClassicApp' -or $app.GetAttribute('TrustLevel', $ns.LookupNamespace('uap10')) -ne 'mediumIL' -or $app.HasAttribute('EntryPoint')) { throw 'Unexpected full-trust helper launch contract.' }
    $visual = $app.SelectSingleNode('uap:VisualElements', $ns)
    if ($null -eq $visual -or $visual.AppListEntry -ne 'none') { throw 'The helper must not add an All Apps entry.' }
    if ($xml.SelectNodes('//uap10:AllowExternalContent', $ns).Count -ne 0 -or $xml.SelectNodes('//rescap:Capability[@Name="runFullTrust"]', $ns).Count -ne 1 -or $xml.SelectNodes('//rescap:Capability', $ns).Count -ne 1) { throw 'Unexpected sparse-package or capability declarations.' }
    $classes = $xml.SelectNodes('//com:SurrogateServer/com:Class', $ns)
    if ($classes.Count -ne 2) { throw 'Exactly two native COM command classes are required.' }
    $expected = @{ SaveImage = $saveClsid; CopyImage = $copyClsid }
    foreach ($class in $classes) {
        if ($class.Path -ne 'ImageCopySave.Shell.dll' -or $class.ThreadingModel -ne 'STA' -or $class.Id -notin @($saveClsid, $copyClsid)) { throw 'Unexpected COM class, DLL path, or threading model.' }
    }
    $verbs = $xml.SelectNodes('//d4:FileExplorerContextMenus/d5:ItemType/d5:Verb', $ns)
    if ($verbs.Count -ne 2) { throw 'Exactly two Explorer verb registrations are required.' }
    foreach ($name in @('SaveImage', 'CopyImage')) {
        $matching = @($verbs | Where-Object { $_.Id -eq $name })
        $context = '*'
        if ($name -eq 'SaveImage') { $context = 'Directory\Background' }
        if ($matching.Count -ne 1 -or $matching[0].Clsid -ne $expected[$name] -or $matching[0].ParentNode.Type -ne $context) { throw "Unexpected Explorer registration for $name" }
        if (@($classes | Where-Object { $_.Id -eq $expected[$name] }).Count -ne 1) { throw "COM class does not match $name" }
    }
    foreach ($relative in @('ImageCopySave.Helper.exe', 'ImageCopySave.Shell.dll', 'ImageCopySave.Helper.runtimeconfig.json', 'ImageCopySave.Helper.deps.json', 'coreclr.dll', 'PresentationFramework.dll', 'Assets\StoreLogo.png', 'Assets\Square150x150Logo.png', 'Assets\Square44x44Logo.png')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Directory $relative) -PathType Leaf)) { throw "Required package entry is missing: $relative" }
    }
    $logo = $xml.SelectSingleNode('/f:Package/f:Properties/f:Logo', $ns)
    if ($logo.InnerText -ne 'Assets\StoreLogo.png' -or $visual.Square150x150Logo -ne 'Assets\Square150x150Logo.png' -or $visual.Square44x44Logo -ne 'Assets\Square44x44Logo.png') { throw 'Unexpected logo paths.' }
    return [ordered]@{ identity = $identity.GetAttribute('Name'); publisher = $identity.GetAttribute('Publisher'); version = $identity.GetAttribute('Version'); architecture = $identity.GetAttribute('ProcessorArchitecture'); helper = $app.Executable; saveClsid = $saveClsid; copyClsid = $copyClsid; status = 'PASS' }
}
function New-PngFromSvg([string]$SvgPath, [string]$Destination, [int]$Size) {
    [xml]$svg = [IO.File]::ReadAllText($SvgPath)
    $svgNs = New-Object Xml.XmlNamespaceManager($svg.NameTable)
    $svgNs.AddNamespace('s', 'http://www.w3.org/2000/svg')
    $root = $svg.SelectSingleNode('/s:svg', $svgNs)
    if ($null -eq $root -or $root.viewBox -ne '0 0 100 100') { throw 'Expected the owned 100 by 100 SVG source.' }
    $visual = New-Object Windows.Media.DrawingVisual
    $drawing = $visual.RenderOpen()
    try {
        $scale = $Size / 100.0
        $drawing.PushTransform((New-Object Windows.Media.ScaleTransform($scale, $scale)))
        foreach ($shape in $svg.SelectNodes('/s:svg/s:path', $svgNs)) {
            $color = [Windows.Media.ColorConverter]::ConvertFromString($shape.fill)
            $brush = New-Object Windows.Media.SolidColorBrush($color)
            $geometry = [Windows.Media.Geometry]::Parse($shape.d)
            $drawing.DrawGeometry($brush, $null, $geometry)
        }
        $drawing.Pop()
    } finally { $drawing.Close() }
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap($Size, $Size, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    return [ordered]@{ path = $Destination; width = $Size; height = $Size; sha256 = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash }
}

# Every run gets fresh owned directories. No recursive deletion, registration,
# certificate creation, trust changes, installation, or Explorer restart occurs.
New-OwnedDirectory $outputRoot
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N')
$staging = Join-Path $outputRoot ('staging/' + $runId)
$unpacked = Join-Path $outputRoot ('unpacked/' + $runId)
$logs = Join-Path $outputRoot ('logs/' + $runId)
$packagePath = Join-Path $outputRoot ('ImageCopySave.Evaluation_' + $Version + '_x64_' + $runId + '.msix')
$resultPath = Join-Path $outputRoot 'package-result.json'
New-OwnedDirectory $staging
New-OwnedDirectory $logs
New-OwnedDirectory (Split-Path -Parent $unpacked)
$steps = New-Object System.Collections.ArrayList
$result = [ordered]@{
    schemaVersion = 1; status = 'RUNNING'; startedUtc = [DateTime]::UtcNow.ToString('o')
    runId = $runId; artifactKind = 'unsigned-evaluation-package'; publisherDecision = 'PROPOSAL'
    stage = 'preflight'; staging = $staging; unpacked = $unpacked; package = $packagePath
    signing = 'NOT RUN'; installation = 'NOT RUN'; explorerG0 = 'NOT RUN'
    productionRelease = $false; steps = $steps
}
try {
    Write-Result
    $nativePath = Join-Path $repoRoot 'artifacts/image-copy-save/native-shell/ImageCopySave.Shell.dll'
    [void](Assert-OwnedPlainPath $nativePath)
    if (-not (Test-Path -LiteralPath $nativePath -PathType Leaf)) { throw "Build the native shell first; expected artifact: $nativePath" }
    $result.nativeInput = Get-PeInfo $nativePath $true
    $nativeMetadataPath = Join-Path (Split-Path -Parent $nativePath) 'build-metadata.json'
    if (-not (Test-Path -LiteralPath $nativeMetadataPath -PathType Leaf)) { throw 'Native build metadata is missing. Run build-shell.ps1 first.' }
    $nativeMetadata = Get-Content -LiteralPath $nativeMetadataPath -Raw | ConvertFrom-Json
    if ($nativeMetadata.dllSha256 -ne $result.nativeInput.sha256) { throw 'Native DLL differs from the tested build. Run build-shell.ps1 first.' }
    foreach ($sourceFile in Get-ChildItem -LiteralPath (Join-Path $toolRoot 'source/ImageCopySave.Shell') -File | Where-Object { $_.Extension -in @('.cpp', '.h', '.def') }) {
        $recordedHash = $nativeMetadata.sourceHashes.PSObject.Properties[$sourceFile.Name]
        if ($null -eq $recordedHash -or $recordedHash.Value -ne (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash) { throw 'Native sources changed after the tested build. Run build-shell.ps1 first.' }
    }
    $headerPath = Join-Path $toolRoot 'source/ImageCopySave.Shell/ShellGuids.h'
    $header = [IO.File]::ReadAllText($headerPath)
    $saveClsid = Get-SourceClsid $header 'CLSID_SaveImage'
    $copyClsid = Get-SourceClsid $header 'CLSID_CopyImage'
    $dotnetPath = Resolve-Executable $DotNet
    $makeAppxPath = Find-MakeAppx
    $result.tools = [ordered]@{ dotnet = $dotnetPath; makeAppx = $makeAppxPath }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'PNG rendering requires an STA thread. Run this build script with Windows PowerShell -STA -File.' }
    Add-Type -AssemblyName WindowsBase, PresentationCore
    $result.stage = 'publish-helper'
    $helperProject = Join-Path $toolRoot 'source/ImageCopySave.Helper/ImageCopySave.Helper.csproj'
    $managedSources = @(Get-ManagedSourceInventory)
    $result.managedSourceInputs = $managedSources
    $result.managedSourceVerification = 'RUNNING'
    Write-Result
    Invoke-RecordedProcess $dotnetPath @('publish', $helperProject, '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-p:DebugType=none', '-p:DebugSymbols=false', '-p:Product=ImageCopySave', ('-p:Version=' + $Version), '-o', $staging) 'helper-publish'
    $managedSourcesAfter = @(Get-ManagedSourceInventory)
    if (($managedSources | ConvertTo-Json -Depth 4 -Compress) -cne ($managedSourcesAfter | ConvertTo-Json -Depth 4 -Compress)) {
        $result.managedSourceVerification = 'FAIL'
        throw 'Managed source inputs changed during publication. Rebuild after the edit is complete.'
    }
    $result.managedSourceVerification = 'PASS'
    $result.managedTestGate = 'NOT ENFORCED - source consistency does not imply managed or Explorer test acceptance'
    $result.stage = 'stage-package'
    $assetsJson = Get-Content -LiteralPath (Join-Path $toolRoot 'source/ImageCopySave.Helper/obj/project.assets.json') -Raw | ConvertFrom-Json
    $runtime = Get-Content -LiteralPath (Join-Path $staging 'ImageCopySave.Helper.runtimeconfig.json') -Raw | ConvertFrom-Json
    $frameworks = @($runtime.runtimeOptions.includedFrameworks)
    if ($frameworks.Count -lt 2) { throw 'Expected self-contained .NET and Windows Desktop runtime frameworks.' }
    $licenseDirectory = Join-Path $staging 'licenses'
    New-OwnedDirectory $licenseDirectory
    $licenseFiles = New-Object System.Collections.ArrayList
    foreach ($framework in $frameworks) {
        $runtimePackage = $framework.name.ToLowerInvariant() + '.runtime.win-x64/' + $framework.version
        $found = $false
        foreach ($folder in $assetsJson.packageFolders.PSObject.Properties.Name) {
            $candidate = Join-Path $folder $runtimePackage
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                $found = $true
                $count = 0
                foreach ($name in @('LICENSE', 'LICENSE.TXT', 'THIRD-PARTY-NOTICES.TXT')) {
                    $source = Join-Path $candidate $name
                    if (Test-Path -LiteralPath $source -PathType Leaf) {
                        $destination = Join-Path $licenseDirectory ($framework.name + '-' + $name)
                        Copy-Item -LiteralPath $source -Destination $destination
                        [void]$licenseFiles.Add($destination)
                        $count++
                    }
                }
                if ($count -lt 1) { throw "Runtime license notices are missing: $runtimePackage" }
                break
            }
        }
        if (-not $found) { throw "Runtime license package was not found: $runtimePackage" }
    }
    $result.runtimeLicenses = @($licenseFiles.ToArray())
    Copy-Item -LiteralPath $nativePath -Destination (Join-Path $staging 'ImageCopySave.Shell.dll')
    Copy-Item -LiteralPath (Join-Path $toolRoot 'installer/AppxManifest.xml') -Destination (Join-Path $staging 'AppxManifest.xml')
    [xml]$stagedManifest = [IO.File]::ReadAllText((Join-Path $staging 'AppxManifest.xml'))
    $stagedManifest.Package.Identity.Publisher = $Publisher
    $stagedManifest.Package.Identity.Version = $Version
    $stagedManifest.Save((Join-Path $staging 'AppxManifest.xml'))
    $assetDirectory = Join-Path $staging 'Assets'
    New-OwnedDirectory $assetDirectory
    $svgPath = Join-Path $toolRoot 'installer/Assets/evaluation-icon.svg'
    $logoResults = New-Object System.Collections.ArrayList
    foreach ($logo in @(@('StoreLogo.png', 50), @('Square150x150Logo.png', 150), @('Square44x44Logo.png', 44))) {
        [void]$logoResults.Add((New-PngFromSvg $svgPath (Join-Path $assetDirectory $logo[0]) $logo[1]))
    }
    $result.logos = @($logoResults.ToArray())
    $result.svgSourceSha256 = (Get-FileHash -LiteralPath $svgPath -Algorithm SHA256).Hash
    $result.native = Get-PeInfo (Join-Path $staging 'ImageCopySave.Shell.dll') $true
    $result.helper = Get-PeInfo (Join-Path $staging 'ImageCopySave.Helper.exe') $false
    if ($result.native.sha256 -ne $result.nativeInput.sha256) { throw 'Native DLL changed while staging.' }
    $result.manifest = Assert-Manifest $staging
    $inventory = @(Get-PlainFiles $staging | ForEach-Object {
        [ordered]@{ path = $_.FullName.Substring($staging.Length + 1).Replace('\', '/'); bytes = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    })
    $result.stage = 'makeappx-pack'
    Invoke-RecordedProcess $makeAppxPath @('pack', '/d', $staging, '/p', $packagePath, '/v') 'makeappx-pack'
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw 'MakeAppx did not produce an MSIX file.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $archiveEntries = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        if ($archiveEntries -contains 'AppxSignature.p7x') { throw 'Unexpected signature in an unsigned evaluation package.' }
        if ($archiveEntries -notcontains 'AppxManifest.xml' -or $archiveEntries -notcontains 'AppxBlockMap.xml' -or $archiveEntries -notcontains '[Content_Types].xml') { throw 'Required MSIX footprint entries are missing.' }
        $result.archiveEntryCount = $archiveEntries.Count
        $result.signaturePresent = $false
    } finally { $archive.Dispose() }
    $result.stage = 'makeappx-unpack'
    Invoke-RecordedProcess $makeAppxPath @('unpack', '/p', $packagePath, '/d', $unpacked, '/v') 'makeappx-unpack'
    $result.stage = 'verify-unpacked-content'
    $unpackedFiles = @(Get-PlainFiles $unpacked)
    if (Test-Path -LiteralPath (Join-Path $unpacked 'AppxSignature.p7x')) { throw 'Unexpected signature in an unsigned evaluation artifact.' }
    [void](Assert-Manifest $unpacked)
    [void](Get-PeInfo (Join-Path $unpacked 'ImageCopySave.Shell.dll') $true)
    [void](Get-PeInfo (Join-Path $unpacked 'ImageCopySave.Helper.exe') $false)
    foreach ($entry in $inventory) {
        $unpackedFile = Join-Path $unpacked $entry.path
        if (-not (Test-Path -LiteralPath $unpackedFile -PathType Leaf)) { throw "Package entry is missing after unpack: $($entry.path)" }
        if ((Get-FileHash -LiteralPath $unpackedFile -Algorithm SHA256).Hash -ne $entry.sha256) { throw "Package entry hash mismatch: $($entry.path)" }
    }
    $result.inventory = $inventory
    $result.inputFileCount = $inventory.Count
    $result.unpackedFileCount = $unpackedFiles.Count
    $result.packageSha256 = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
    $result.packageBytes = (Get-Item -LiteralPath $packagePath).Length
    $result.contentVerification = 'PASS'
    $result.signaturePresent = $false
    $result.stage = 'complete'
    $result.status = 'PASS'
    $result.finishedUtc = [DateTime]::UtcNow.ToString('o')
    Write-Result
    Write-Host "Unsigned evaluation package built and inspected: $packagePath"
    Write-Host "Evidence: $resultPath"
    Write-Host 'Package construction passed. Signing, installation, and Explorer G0 remain NOT RUN.'
} catch {
    $result.status = 'FAIL'
    $result.error = $_.Exception.Message
    $result.finishedUtc = [DateTime]::UtcNow.ToString('o')
    Write-Result
    throw
}
