[CmdletBinding()]
param(
    [string]$PackageResult = '',
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version = '0.1.1',
    [switch]$RollbackTest
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$utf8 = New-Object Text.UTF8Encoding($false)
if ([Version]$Version -gt [Version]'255.255.65535' -or ([Version]$Version).Minor -gt 255 -or ([Version]$Version).Build -gt 65535) { throw 'Version exceeds Windows Installer version limits.' }
function Owned-Path([string]$Path) {
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith(($root + '\artifacts\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Build inputs and output must be inside this worktree artifacts.' }
    $current = $full
    while ($current -ne $root) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Build content may not traverse reparse points.' }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return $full
}
function Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Plain-Files([string]$Directory) {
    [void](Owned-Path $Directory)
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse point in build content.' }
        if ($item.PSIsContainer) { Plain-Files $item.FullName } else { $item }
    }
}
function Xml([string]$Value) { [Security.SecurityElement]::Escape($Value) }
function Id([string]$Value) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant())))).Replace('-','').Substring(0,32) }
    finally { $hash.Dispose() }
}
function Run([string]$Executable, [string[]]$Arguments, [string]$LogName) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable; $info.WorkingDirectory = $root; $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.Arguments = (@($Arguments | ForEach-Object {
        if ($_.Contains('"') -or $_.EndsWith('\')) { throw 'Ambiguous build argument.' }
        '"' + $_ + '"'
    }) -join ' ')
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [IO.File]::WriteAllText((Join-Path $output $LogName), ($stdout.Result + $stderr.Result), $utf8)
        if ($process.ExitCode -ne 0) { throw "$LogName failed with exit $($process.ExitCode). See $output." }
    } finally { $process.Dispose() }
}
if ([string]::IsNullOrWhiteSpace($PackageResult)) { $PackageResult = Join-Path $root 'artifacts/image-copy-save/package-evaluation/package-result.json' }
$PackageResult = Owned-Path $PackageResult
$previous = Get-Content -LiteralPath $PackageResult -Encoding UTF8 -Raw | ConvertFrom-Json
if ($previous.status -ne 'PASS' -or $previous.contentVerification -ne 'PASS') { throw 'A successfully verified self-contained helper payload is required.' }
$payload = Owned-Path $previous.staging
foreach ($inputFile in $previous.managedSourceInputs) {
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $root $inputFile.path))
    if (-not $sourcePath.StartsWith(($root + '\'), [StringComparison]::OrdinalIgnoreCase) -or (Sha $sourcePath) -ne $inputFile.sha256) { throw "Managed source has changed since the verified publish: $($inputFile.path)" }
}
$nativeRoot = Join-Path $root 'artifacts/image-copy-save/native-shell'
$native = Get-Content -LiteralPath (Join-Path $nativeRoot 'build-metadata.json') -Encoding UTF8 -Raw | ConvertFrom-Json
foreach ($property in $native.sourceHashes.PSObject.Properties) {
    if ((Sha (Join-Path $root ('tools/ImageCopySave/source/ImageCopySave.Shell/' + $property.Name))) -ne $property.Value) { throw "Native source changed after the last native build: $($property.Name)" }
}
$nativeDll = Join-Path $nativeRoot 'ImageCopySave.Shell.dll'
if ((Sha $nativeDll) -ne $native.dllSha256 -or $native.architecture -ne 'x64') { throw 'Native build metadata does not match the DLL.' }
$runId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [Guid]::NewGuid().ToString('N')
$output = Owned-Path (Join-Path $root ('artifacts/image-copy-save/msi/' + $runId))
[IO.Directory]::CreateDirectory($output) | Out-Null
$productSource = Join-Path $output 'Product.wxs'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Product.wxs') -Destination $productSource
$installerSourceHashes = @{}
foreach ($source in @('Product.wxs','build-msi.ps1')) { $installerSourceHashes[$source] = Sha (Join-Path $PSScriptRoot $source) }
$stage = Join-Path $output 'payload'; [IO.Directory]::CreateDirectory($stage) | Out-Null
$files = @(Plain-Files $payload | Sort-Object FullName)
$expectedInventory = @{}
foreach ($entry in $previous.inventory) { $expectedInventory[$entry.path] = $entry.sha256 }
$inventory = New-Object 'System.Collections.Generic.List[object]'
foreach ($file in $files) {
    $relative = $file.FullName.Substring($payload.Length + 1).Replace('\','/')
    if (-not $expectedInventory.ContainsKey($relative) -or (Sha $file.FullName) -ne $expectedInventory[$relative]) { throw "Payload differs from the verified package: $relative" }
    if ($relative -eq 'AppxManifest.xml' -or $relative.StartsWith('Assets/')) { continue }
    $target = Join-Path $stage $relative
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath $(if ($relative -eq 'ImageCopySave.Shell.dll') { $nativeDll } else { $file.FullName }) -Destination $target
    $inventory.Add([ordered]@{ path=$relative; sha256=(Sha $target); bytes=(Get-Item -LiteralPath $target).Length })
}
if ($files.Count -ne $expectedInventory.Count) { throw 'Verified payload file count changed.' }
foreach ($required in @('ImageCopySave.Helper.exe','ImageCopySave.Helper.dll','ImageCopySave.Shell.dll','coreclr.dll','hostfxr.dll','hostpolicy.dll','PresentationFramework.dll','WindowsBase.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $stage $required))) { throw "Missing self-contained runtime or product file: $required" }
}
$lines = New-Object 'System.Collections.Generic.List[string]'
$lines.Add('<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"><Fragment>')
$directories = @{}
foreach ($entry in $inventory) {
    $relativeDir = [IO.Path]::GetDirectoryName($entry.path).Replace('\','/')
    while ($relativeDir) { $directories[$relativeDir] = 'D_' + (Id $relativeDir); $relativeDir = [IO.Path]::GetDirectoryName($relativeDir).Replace('\','/') }
}
foreach ($directory in @($directories.Keys | Sort-Object)) {
    $parent = [IO.Path]::GetDirectoryName($directory).Replace('\','/')
    $parentId = $(if ($parent) { $directories[$parent] } else { 'INSTALLFOLDER' })
    $lines.Add('<DirectoryRef Id="' + $parentId + '"><Directory Id="' + $directories[$directory] + '" Name="' + (Xml ([IO.Path]::GetFileName($directory))) + '" /></DirectoryRef>')
}
$lines.Add('<ComponentGroup Id="ApplicationFiles">')
foreach ($entry in $inventory) {
    $relativeDir = [IO.Path]::GetDirectoryName($entry.path).Replace('\','/')
    $directoryId = $(if ($relativeDir) { $directories[$relativeDir] } else { 'INSTALLFOLDER' })
    $fileId = Id $entry.path
    $lines.Add('<Component Id="C_' + $fileId + '" Guid="*" Directory="' + $directoryId + '" Bitness="always64"><File Id="F_' + $fileId + '" Source="' + (Xml (Join-Path $stage $entry.path)) + '" KeyPath="yes" /></Component>')
}
$lines.Add('</ComponentGroup></Fragment></Wix>')
$filesWxs = Join-Path $output 'Files.wxs'
[IO.File]::WriteAllLines($filesWxs, $lines, $utf8)
$productCode = '{' + ([Guid]::ParseExact((Id ('ImageCopySave.Product.' + $Version + $(if ($RollbackTest) { '.RollbackTest' } else { '' }))), 'N')).ToString().ToUpperInvariant() + '}'
$name = 'ImageCopySave-' + $Version + '-x64' + $(if ($RollbackTest) { '-ROLLBACK-TEST' } else { '' }) + '.msi'
$msi = Join-Path $output $name
$wix = Join-Path $root '.tools/wix/wix.exe'
Run $wix @('build',$productSource,$filesWxs,'-arch','x64','-d',"Version=$Version",'-d',"ProductCode=$productCode",'-d',"RollbackTest=$([int][bool]$RollbackTest)",'-pdbtype','none','-o',$msi) 'wix-build.log'
if ((Get-AuthenticodeSignature -LiteralPath $msi).Status -ne 'NotSigned') { throw 'The MSI must remain unsigned.' }
$metadata = [ordered]@{ status='PASS'; productionRelease=$false; artifactKind='unsigned-self-contained-msi'; version=$Version; productCode=$productCode; upgradeCode='{78C90F77-8CC3-4B10-BA9A-00E84ADAF375}'; msi=$msi; msiSha256=(Sha $msi); signatureStatus='NotSigned'; payloadEmbedded=$true; registration='HKLM classic IExplorerCommand'; installScope='perMachine'; runtimeElevation=$false; rollbackTest=[bool]$RollbackTest; files=@($inventory.ToArray()); nativeDllSha256=$native.dllSha256; priorVerifiedPackageResult=$PackageResult; sourceHashes=@{} }
foreach ($source in @('Product.wxs','build-msi.ps1','verify-msi.ps1')) { if (Test-Path -LiteralPath (Join-Path $PSScriptRoot $source)) { $metadata.sourceHashes[$source] = Sha (Join-Path $PSScriptRoot $source) } }
foreach ($source in $installerSourceHashes.Keys) { if ($installerSourceHashes[$source] -ne $metadata.sourceHashes[$source]) { throw 'Installer sources changed during the build. Rebuild before using this artifact.' } }
[IO.File]::WriteAllText((Join-Path $output 'build-metadata.json'), ($metadata | ConvertTo-Json -Depth 8), $utf8)
Write-Output "Self-contained unsigned MSI: $msi"
Write-Output "Output directory: $output"
