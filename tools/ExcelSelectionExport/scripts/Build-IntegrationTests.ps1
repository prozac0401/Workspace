[CmdletBinding()]
param(
    [ValidateSet('x64', 'x86')]
    [string]$Architecture = 'x64'
)
# Developer-only compilation. This script never launches any produced test executable,
# Excel, an installer, a COM object, or a user workbook.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$productRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot "artifacts\selection-export\integration-tests\$Architecture"))
$boundary = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\selection-export\integration-tests')) + [IO.Path]::DirectorySeparatorChar
if (-not $outputRoot.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase)) { throw 'Integration-test output escaped its intended directory.' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'The developer machine requires the .NET Framework C# compiler.' }
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

function Invoke-IntegrationCompiler([string[]]$Arguments, [string]$LogPath) {
    $quoted = @($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' })
    $launchLog = $LogPath + '.launch.jsonl'
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $process = New-Object Diagnostics.Process
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $compiler
        $info.Arguments = [string]::Join(' ', $quoted)
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process.StartInfo = $info
        $record = [ordered]@{ utc = [DateTime]::UtcNow.ToString('o'); executable = $compiler; arguments = $Arguments; attempt = $attempt; state = 'starting' }
        Add-Content -LiteralPath $launchLog -Value ($record | ConvertTo-Json -Depth 5 -Compress) -Encoding UTF8
        try {
            if (-not $process.Start()) { throw 'The compiler process did not start.' }
        } catch {
            $nativeError = $null
            $exception = $_.Exception
            while ($null -ne $exception) {
                if ($exception -is [ComponentModel.Win32Exception]) { $nativeError = $exception.NativeErrorCode; break }
                $exception = $exception.InnerException
            }
            $record['state'] = 'creation-failed'
            $record['nativeError'] = $nativeError
            $record['message'] = $_.Exception.Message
            Add-Content -LiteralPath $launchLog -Value ($record | ConvertTo-Json -Depth 5 -Compress) -Encoding UTF8
            $process.Dispose()
            if (($nativeError -eq 5 -or $nativeError -eq 32) -and $attempt -lt 3) {
                Write-Warning "Compiler start failed with Win32 $nativeError; retrying the same file after one second ($attempt/3): $compiler"
                Start-Sleep -Seconds 1
                continue
            }
            throw
        }
        try {
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $stdout = $stdoutTask.GetAwaiter().GetResult()
            $stderr = $stderrTask.GetAwaiter().GetResult()
            [IO.File]::WriteAllText($LogPath, $stdout, [Text.Encoding]::UTF8)
            [IO.File]::WriteAllText(($LogPath + '.stderr'), $stderr, [Text.Encoding]::UTF8)
            if ($stdout) { Write-Output $stdout.TrimEnd() }
            if ($stderr) { Write-Output $stderr.TrimEnd() }
            $record['state'] = 'completed'
            $record['exitCode'] = $process.ExitCode
            Add-Content -LiteralPath $launchLog -Value ($record | ConvertTo-Json -Depth 5 -Compress) -Encoding UTF8
            if ($process.ExitCode -ne 0) { throw "Integration-test compilation failed: $($process.ExitCode). See $LogPath" }
            return
        } finally { $process.Dispose() }
    }
}

$targets = @(
    @{ Name = 'ExcelProbe'; EntryPoint = 'ExcelProbe'; References = @('Microsoft.CSharp.dll', 'System.Core.dll', 'System.IO.Compression.dll', 'System.IO.Compression.FileSystem.dll') },
    @{ Name = 'FunctionalTests'; EntryPoint = 'ExcelSelectionExport.IntegrationTests.FunctionalTests'; References = @('Microsoft.CSharp.dll', 'System.Core.dll') },
    @{ Name = 'EngineFailureTests'; EntryPoint = 'ExcelSelectionExport.IntegrationTests.EngineFailureTests'; References = @('Microsoft.CSharp.dll', 'System.Core.dll') },
    @{ Name = 'OutputCancellationTests'; EntryPoint = 'ExcelSelectionExport.IntegrationTests.OutputCancellationTests'; References = @('Microsoft.CSharp.dll', 'System.Core.dll', 'System.IO.Compression.dll', 'System.IO.Compression.FileSystem.dll') },
    @{ Name = 'UndoHistoryTests'; EntryPoint = 'UndoHistoryTests'; References = @('Microsoft.CSharp.dll', 'System.Core.dll') },
    @{ Name = 'CancellationTests'; EntryPoint = 'ExcelSelectionExport.IntegrationTests.CancellationTests'; References = @('Microsoft.CSharp.dll', 'System.Core.dll') }
)
$records = @()
foreach ($target in $targets) {
    $source = Join-Path $productRoot ("tests\" + $target.Name + '.cs')
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Integration-test source is missing: $source" }
    $output = Join-Path $outputRoot ($target.Name + '.exe')
    $arguments = @('/nologo', '/target:exe', '/optimize+', "/platform:$Architecture", ("/main:" + $target.EntryPoint), "/out:$output")
    $arguments += @($target.References | ForEach-Object { '/reference:' + $_ })
    $arguments += $source
    if ($target.Name -eq 'OutputCancellationTests') { $arguments += (Join-Path $productRoot 'tests\ExcelProbe.cs') }
    Invoke-IntegrationCompiler $arguments (Join-Path $outputRoot ($target.Name + '.compile.log'))
    $records += [ordered]@{
        name = $target.Name; source = $source.Substring($repoRoot.Length + 1);
        sourceSha256 = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;
        output = [IO.Path]::GetFileName($output); outputSha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash;
        references = $target.References
        additionalSources = @(if ($target.Name -eq 'OutputCancellationTests') { [ordered]@{ path = 'tools/ExcelSelectionExport/tests/ExcelProbe.cs'; sha256 = (Get-FileHash -LiteralPath (Join-Path $productRoot 'tests\ExcelProbe.cs') -Algorithm SHA256).Hash } })
    }
}
$manifest = [ordered]@{
    product = 'ExcelSelectionExport'; purpose = 'developer integration-test compilation only';
    utc = [DateTime]::UtcNow.ToString('o'); architecture = $Architecture;
    compiler = (Get-Item -LiteralPath $compiler).VersionInfo.FileVersion;
    compileTimeProductDllDependency = $false; executedTests = $false; startedExcel = $false;
    scriptSha256 = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash;
    outputs = $records
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputRoot 'integration-build-manifest.json') -Encoding UTF8
Write-Output "Compiled integration helpers only: $outputRoot"
