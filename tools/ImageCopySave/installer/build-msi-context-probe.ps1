[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProbePackage,
    [Parameter(Mandatory = $true)][string]$ExternalLocation,
    [switch]$WaitForUserRegistration
)
# Produces a local diagnostic MSI, not a distributable product installer.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
function Artifact-Path([string]$Path) {
    $full = (Resolve-Path -LiteralPath $Path).Path
    if (-not $full.StartsWith(($root + '\artifacts\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Inputs must be in this worktree artifacts.' }
    $current = $full
    while ($current -ne $root) {
        if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse paths are not accepted.' }
        $current = [IO.Path]::GetDirectoryName($current)
    }
    return $full
}
$ProbePackage = Artifact-Path $ProbePackage
$ExternalLocation = Artifact-Path $ExternalLocation
if (-not (Test-Path -LiteralPath (Join-Path $ExternalLocation 'ImageCopySave.Shell.dll'))) { throw 'External payload is missing.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($ProbePackage)
try {
    if ($null -ne $archive.GetEntry('AppxSignature.p7x')) { throw 'Only the unsigned probe identity is accepted.' }
    $reader = New-Object IO.StreamReader($archive.GetEntry('AppxManifest.xml').Open())
    try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $id = $manifest.Package.Identity
    if ($id.Name -cne 'ImageCopySave.UnsignedSparseProbe' -or $id.Version -cne '0.1.1.0' -or $id.ProcessorArchitecture -cne 'x64' -or $id.Publisher -cne 'CN=ImageCopySave.UnsignedSparseProbe, OID.2.25.311729368913984317654407730594956997722=1') { throw 'Unexpected probe package identity.' }
} finally { $archive.Dispose() }
$output = Join-Path $root ('artifacts/image-copy-save/msi-context-probe/' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($output) | Out-Null
$null = Artifact-Path $output
$framework = Join-Path $env:windir 'Microsoft.NET/Framework64/v4.0.30319'
function Invoke-BuildTool([string]$Executable, [string[]]$Arguments, [string]$LogName) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.WorkingDirectory = $output
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.Arguments = (@($Arguments | ForEach-Object {
        if ($_.Contains('"') -or $_.EndsWith('\')) { throw 'Ambiguous build argument.' }
        '"' + $_ + '"'
    }) -join ' ')
    $process = [Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [IO.File]::WriteAllText((Join-Path $output $LogName), ($stdout.Result + $stderr.Result))
        if ($process.ExitCode -ne 0) { throw "$LogName failed: exit $($process.ExitCode). See $output." }
    } finally { $process.Dispose() }
}
$compiler = Join-Path $framework 'csc.exe'
$wix = Join-Path $root '.tools/wix/wix.exe'
foreach ($tool in @($compiler, $wix)) { if (-not (Test-Path -LiteralPath $tool)) { throw "Required existing build tool not found: $tool" } }
$exe = Join-Path $output 'MsiContextProbe.exe'
$references = @('Windows.Management', 'Windows.ApplicationModel', 'Windows.Foundation') | ForEach-Object { '/r:' + (Join-Path $env:windir ('System32/WinMetadata/' + $_ + '.winmd')) }
$references += @('System.Runtime', 'System.Runtime.WindowsRuntime', 'System.Runtime.InteropServices.WindowsRuntime') | ForEach-Object { '/r:' + (Join-Path $framework ($_ + '.dll')) }
Invoke-BuildTool $compiler (@('/nologo','/platform:x64','/target:exe',"/out:$exe") + $references + @((Join-Path $PSScriptRoot 'MsiContextProbe.cs'))) 'compile.log'
$packageHash = (Get-FileHash -LiteralPath $ProbePackage -Algorithm SHA256).Hash
$msi = Join-Path $output 'ImageCopySave-MsiContextProbe.msi'
$report = Join-Path $output 'system-probe.log'
$waitArgument = $(if ($WaitForUserRegistration) { 'wait' } else { '' })
Invoke-BuildTool $wix @('build', (Join-Path $PSScriptRoot 'MsiContextProbe.wxs'), '-arch', 'x64', '-d', "ProbeExecutable=$exe", '-d', "ProbePackage=$ProbePackage", '-d', "Payload=$ExternalLocation", '-d', "PackageHash=$packageHash", '-d', "ResultPath=$report", '-d', "WaitArgument=$waitArgument", '-pdbtype', 'none', '-o', $msi) 'wix-build.log'
$signature = Get-AuthenticodeSignature -LiteralPath $msi
if ($signature.Status -ne 'NotSigned') { throw 'The diagnostic MSI must be unsigned.' }
$metadata = [ordered]@{ purpose='Local MSI SYSTEM feasibility only'; productionRelease=$false; payloadEmbedded=$false; msi=$msi; msiSha256=(Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash; signatureStatus=[string]$signature.Status; probePackage=$ProbePackage; packageSha256=$packageHash; externalLocation=$ExternalLocation; resultPath=$report; waitForUserRegistration=[bool]$WaitForUserRegistration; sourceHashes=@{} }
foreach ($source in @('MsiContextProbe.cs', 'MsiContextProbe.wxs', 'test-msi-context.ps1', 'build-msi-context-probe.ps1')) { $metadata.sourceHashes[$source] = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $source) -Algorithm SHA256).Hash }
[IO.File]::WriteAllText((Join-Path $output 'build-metadata.json'), ($metadata | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
Write-Output "Local diagnostic MSI: $msi"
Write-Output "Output directory: $output"
