[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ZipPath,
    [Parameter(Mandatory)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedSha256,
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')][string]$Version = '0.1.1'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$product = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repo = [IO.Path]::GetFullPath((Join-Path $product '..\..'))
$zip = (Resolve-Path -LiteralPath $ZipPath).Path
$actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $ExpectedSha256.ToLowerInvariant()) { throw 'Release ZIP differs from the explicitly expected SHA-256.' }
& (Join-Path $PSScriptRoot 'verify-package.ps1') -ZipPath $zip
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
    $reader = New-Object IO.StreamReader($archive.GetEntry('version.txt').Open())
    try { if ($reader.ReadToEnd().Trim() -ne $Version) { throw 'ZIP version differs from the requested installer version.' } }
    finally { $reader.Dispose() }
} finally { $archive.Dispose() }
$output = Join-Path $repo "artifacts\visible-cells-paste\single-$Version"
New-Item -ItemType Directory -Path $output -Force | Out-Null
$hashResource = Join-Path $output 'Release.sha256'
[IO.File]::WriteAllText($hashResource, $actual, [Text.Encoding]::ASCII)
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$source = Join-Path $product 'installer\Bootstrap.cs'
$tests = Join-Path $product 'installer\BootstrapTests.cs'
$manifest = Join-Path $product 'installer\Setup.manifest'
$exe = Join-Path $output "VisibleCellsPaste-$Version-Setup.exe"
function Run([string]$File, [string[]]$Arguments, [string]$Log) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = [string]::Join(' ', @($Arguments | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }))
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.WindowStyle = 'Hidden'
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) { throw 'Build helper could not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $text = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path $output $Log), $text, [Text.Encoding]::UTF8)
        if ($process.ExitCode -ne 0) { throw "Build helper failed: $text" }
        Write-Output $text.TrimEnd()
    } finally { $process.Dispose() }
}
$references = @('/r:System.Core.dll','/r:System.Windows.Forms.dll','/r:System.IO.Compression.dll')
$resources = @("/resource:$zip,Release.zip", "/resource:$hashResource,Release.sha256")
Run $compiler (@('/nologo','/target:winexe','/platform:anycpu','/optimize+',"/out:$exe","/win32manifest:$manifest") + $references + $resources + @($source)) 'compile.log'
$testExe = Join-Path $output 'BootstrapTests.exe'
Run $compiler (@('/nologo','/target:exe','/platform:anycpu','/main:BootstrapTests',"/out:$testExe") + $references + $resources + @($source,$tests)) 'test-compile.log'
Run $testExe @((Join-Path $output ('test-' + [Guid]::NewGuid().ToString('N')))) 'tests.log'
$exeHash = (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'), "$exeHash  $([IO.Path]::GetFileName($exe))`r`n", [Text.Encoding]::ASCII)
[ordered]@{
    product = 'VisibleCellsPaste'; version = $Version; wrapperVersion = '0.1.1.1'; signed = $false
    inputZipSha256 = $actual; outputSha256 = $exeHash
    sources = @(@($source,$tests,$manifest,$PSCommandPath) | ForEach-Object { [ordered]@{ path = $_.Substring($repo.Length + 1); sha256 = (Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant() } })
    note = 'Embeds the release ZIP unchanged. Product COM DLL and installation.xml engine are not rebuilt. Actual Windows/Excel tests are separate.'
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'single-installer-manifest.json') -Encoding UTF8
Write-Output "Unsigned single installer: $exe"
