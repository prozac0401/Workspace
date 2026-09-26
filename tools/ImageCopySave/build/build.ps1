[CmdletBinding()]
param([string]$DotNet = 'dotnet', [switch]$PublishEvaluation, [switch]$PublishRemoteTests)
$ErrorActionPreference = 'Stop'
$toolRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $toolRoot '../..')).Path
$output = Join-Path $repoRoot 'artifacts/image-copy-save'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$dotnetPath = (Get-Command $DotNet -ErrorAction Stop).Source
function Invoke-DotNet([string[]]$Arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $dotnetPath
    $info.WorkingDirectory = $repoRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    # All arguments are fixed flags or filesystem paths ending in a filename.
    # Reject ambiguous quoting; do not pass this command through a shell.
    $quoted = foreach ($item in $Arguments) {
        if ($item.Contains('"') -or $item.EndsWith('\')) { throw 'Unsupported argument quoting.' }
        '"' + $item + '"'
    }
    $info.Arguments = $quoted -join ' '
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        Write-Host $stdout.Result
        if ($stderr.Result) { Write-Host $stderr.Result }
        if ($process.ExitCode -ne 0) { throw "dotnet failed: $($process.ExitCode)" }
    } finally { $process.Dispose() }
}
Invoke-DotNet @('build', (Join-Path $toolRoot 'source/ImageCopySave.Helper/ImageCopySave.Helper.csproj'), '-c', 'Release')
$helperExecutable = Join-Path $toolRoot 'source/ImageCopySave.Helper/bin/Release/net10.0-windows/ImageCopySave.Helper.exe'
Invoke-DotNet @('run', '--project', (Join-Path $toolRoot 'source/ImageCopySave.Tests/ImageCopySave.Tests.csproj'), '-c', 'Release', '--', '--report', (Join-Path $output 'automated-results.json'), '--helper', $helperExecutable)
if ($PublishEvaluation) {
    Invoke-DotNet @('publish', (Join-Path $toolRoot 'source/ImageCopySave.Helper/ImageCopySave.Helper.csproj'), '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-o', (Join-Path $output 'engine-evaluation'))
}

if ($PublishRemoteTests) {
    $remoteOutput = Join-Path $output 'remote-tests'
    Invoke-DotNet @('publish', (Join-Path $toolRoot 'source/ImageCopySave.Tests/ImageCopySave.Tests.csproj'), '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-p:DebugType=none', '-p:DebugSymbols=false', '-o', $remoteOutput)
    Invoke-DotNet @('publish', (Join-Path $toolRoot 'source/ImageCopySave.Helper/ImageCopySave.Helper.csproj'), '-c', 'Release', '-r', 'win-x64', '--self-contained', 'true', '-p:DebugType=none', '-p:DebugSymbols=false', '-o', (Join-Path $remoteOutput 'helper'))
    $assets = Get-Content -LiteralPath (Join-Path $toolRoot 'source/ImageCopySave.Tests/obj/project.assets.json') -Raw | ConvertFrom-Json
    $runtime = Get-Content -LiteralPath (Join-Path $remoteOutput 'ImageCopySave.Tests.runtimeconfig.json') -Raw | ConvertFrom-Json
    $licenses = Join-Path $remoteOutput 'licenses'
    New-Item -ItemType Directory -Path $licenses -Force | Out-Null
    foreach ($framework in $runtime.runtimeOptions.includedFrameworks) {
        $package = $framework.name.ToLowerInvariant() + '.runtime.win-x64/' + $framework.version
        $found = $false
        foreach ($folder in $assets.packageFolders.PSObject.Properties.Name) {
            $candidate = Join-Path $folder $package
            if (Test-Path -LiteralPath $candidate) {
                $found = $true
                $count = 0
                foreach ($name in @('LICENSE', 'LICENSE.TXT', 'THIRD-PARTY-NOTICES.TXT')) {
                    $source = Join-Path $candidate $name
                    if (Test-Path -LiteralPath $source) {
                        Copy-Item -LiteralPath $source -Destination (Join-Path $licenses ($framework.name + '-' + $name))
                        $count++
                    }
                }
                if ($count -lt 1) { throw 'Runtime license notices are missing.' }
                break
            }
        }
        if (-not $found) { throw "Runtime package missing: $package" }
    }
    Copy-Item -LiteralPath (Join-Path $repoRoot 'docs/tools/image-copy-save/remote-testing.md') -Destination (Join-Path $remoteOutput 'README.md')
    $archive = Join-Path $output 'ImageCopySave-remote-tests-win-x64.zip'
    Compress-Archive -LiteralPath $remoteOutput -DestinationPath $archive -Force
    Get-FileHash -LiteralPath $archive -Algorithm SHA256
}
