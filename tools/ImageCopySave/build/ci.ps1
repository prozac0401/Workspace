[CmdletBinding()]
param([string]$DotNet = 'dotnet')
$ErrorActionPreference = 'Stop'
$toolRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $toolRoot '../..')).Path
$output = Join-Path $repoRoot 'artifacts/image-copy-save/ci'
New-Item -ItemType Directory -Path $output -Force | Out-Null
$dotnetPath = (Get-Command $DotNet -ErrorAction Stop).Source
function Invoke-RecordedDotNet([string[]]$Arguments, [string]$LogName) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $dotnetPath
    $info.WorkingDirectory = $repoRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
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
        $text = $stdout.Result + [Environment]::NewLine + $stderr.Result
        [System.IO.File]::WriteAllText((Join-Path $output $LogName), $text)
        Write-Host $text
        return $process.ExitCode
    } finally { $process.Dispose() }
}
$helper = Join-Path $toolRoot 'source/ImageCopySave.Helper/ImageCopySave.Helper.csproj'
$tests = Join-Path $toolRoot 'source/ImageCopySave.Tests/ImageCopySave.Tests.csproj'
$helperExecutable = Join-Path $toolRoot 'source/ImageCopySave.Helper/bin/Release/net10.0-windows/ImageCopySave.Helper.exe'
$resultPath = Join-Path $output 'results.json'
# Clear only this script's four owned evidence files; never collect stale logs.
foreach ($name in @('results.json', 'helper-build.log', 'tests-build.log', 'tests.log')) {
    $ownedFile = Join-Path $output $name
    if (Test-Path -LiteralPath $ownedFile) { Remove-Item -LiteralPath $ownedFile }
}
$code = Invoke-RecordedDotNet @('build', $helper, '-c', 'Release') 'helper-build.log'
if ($code -ne 0) { exit $code }
$code = Invoke-RecordedDotNet @('build', $tests, '-c', 'Release') 'tests-build.log'
if ($code -ne 0) { exit $code }
$code = Invoke-RecordedDotNet @('run', '--project', $tests, '-c', 'Release', '--no-build', '--', '--require-clipboard', '--report', $resultPath, '--helper', $helperExecutable) 'tests.log'
if ($code -ne 0) { exit $code }
if (-not (Test-Path -LiteralPath $resultPath)) { throw 'Required test report is missing.' }
$report = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
$clipboard = @($report.results | Where-Object { $_.name.StartsWith('clipboard isolated ') })
$product = @($report.results | Where-Object { $_.name.StartsWith('clipboard isolated product-') })
if (-not $report.requireClipboard -or $report.failed -ne 0 -or $report.skipped -ne 0 -or
    @($report.results).Count -ne 77 -or $clipboard.Count -ne 21 -or $product.Count -ne 12 -or
    @($report.results | Where-Object { $_.status -ne 'PASS' }).Count -ne 0) {
    throw 'Required 77 tests, including 21 isolated clipboard cases and 12 actual helper cases, were not all PASS.'
}
$requiredExtended = @(
    'filesystem/actual-source-read-ACL-denial',
    'filesystem/actual-destination-write-ACL-denial',
    'filesystem/owned-VHD-real-disk-full',
    'limits/actual-pixel-boundaries-roundtrip',
    'performance/4k-engine-save-read-p50-p95',
    'clipboard isolated product-snapshot-other-copy',
    'clipboard isolated product-corrupt-clipboard',
    'clipboard isolated product-copy-preparation-race',
    'clipboard isolated product-worker-inflight-cancel'
)
foreach ($name in $requiredExtended) {
    if (@($report.results | Where-Object { $_.name -eq $name -and $_.status -eq 'PASS' }).Count -ne 1) {
        throw ('Required extended scenario did not pass: ' + $name)
    }
}
if (-not $report.isolatedFileSystemRequested -or @($report.filesystemEvidence).Count -lt 4 -or
    @($report.boundaryPerformanceEvidence).Count -lt 2) {
    throw 'Extended filesystem and boundary/performance evidence is missing.'
}
Write-Host '77 native/engine tests passed, including 12 actual helper cases and a test-owned full disk. This does not verify Explorer G0, external application paste, public Ctrl+C UI, or product installation.'
exit 0
