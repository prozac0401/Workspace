[CmdletBinding()]
param(
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.]+)?$')]
    [string]$Version = '0.1.0-rc.9',
    [string]$InnoCompiler = (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Inno Setup 6\ISCC.exe')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$productRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot "artifacts\selection-export\$Version"))
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\selection-export')) + [IO.Path]::DirectorySeparatorChar
if (-not $outputRoot.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Build output is outside product artifacts.' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw '.NET Framework C# compiler was not found.' }
if (-not (Test-Path -LiteralPath $InnoCompiler -PathType Leaf)) { throw 'Inno Setup 6 is required on the developer machine.' }
$sources = @(Get-ChildItem -LiteralPath (Join-Path $productRoot 'src') -Filter '*.cs' -File | Sort-Object Name | ForEach-Object FullName)
if ($sources.Count -eq 0) { throw 'No add-in source files found.' }
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
function Invoke-BuildTool([string]$FilePath, [string[]]$Arguments, [string]$LogPath) {
    $quoted = @($Arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' })
    $launchLog = $LogPath + '.launch.jsonl'
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $process = New-Object System.Diagnostics.Process
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $FilePath
        $info.Arguments = [string]::Join(' ', $quoted)
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process.StartInfo = $info
        $record = [ordered]@{ utc = [DateTime]::UtcNow.ToString('o'); executable = $FilePath; arguments = $Arguments; attempt = $attempt; state = 'starting' }
        Add-Content -LiteralPath $launchLog -Value ($record | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
        try {
            $started = $process.Start()
            if (-not $started) { throw 'Process.Start did not create a process.' }
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
            Add-Content -LiteralPath $launchLog -Value ($record | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
            $process.Dispose()
            if (($nativeError -eq 5 -or $nativeError -eq 32) -and $attempt -lt 3) {
                Write-Warning ("Build tool process creation failed (Win32 {0}), attempt {1}/3: {2}. Retrying the same executable after one second." -f $nativeError, $attempt, $FilePath)
                Start-Sleep -Seconds 1
                continue
            }
            throw
        }
        try {
            # Drain both streams concurrently to avoid blocking a compiler on a full pipe.
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
            Add-Content -LiteralPath $launchLog -Value ($record | ConvertTo-Json -Compress -Depth 5) -Encoding UTF8
            # A running tool's nonzero exit is never retried or hidden.
            if ($process.ExitCode -ne 0) { throw "$FilePath failed: $($process.ExitCode). See $LogPath" }
            return
        } finally { $process.Dispose() }
    }
}
$sourceRecords = @()
foreach ($sourceFile in $sources + @((Join-Path $productRoot 'installer\SetupProbe.cs'), (Join-Path $productRoot 'installer\SelectionExport.iss'), (Join-Path $productRoot 'tests\SetupProbeTests.cs'), (Join-Path $productRoot 'tests\M1Tests.cs'), (Join-Path $productRoot 'tests\EngineTests.cs'), (Join-Path $productRoot 'tests\EngineGuardTests.cs'), (Join-Path $productRoot 'tests\Test-Package.ps1'), (Join-Path $productRoot 'README.md'), (Join-Path $productRoot 'CHANGELOG.md'), $PSCommandPath)) {
    $sourceRecords += [ordered]@{ path = $sourceFile.Substring($repoRoot.Length + 1); sha256 = (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash }
}
foreach ($arch in @('x86', 'x64')) {
    $payload = Join-Path $outputRoot $arch
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    $dll = Join-Path $payload 'ExcelSelectionExport.AddIn.dll'
    $compilerArguments = @('/nologo', '/target:library', '/optimize+', '/debug-', "/platform:$arch", "/out:$dll", '/reference:Microsoft.CSharp.dll', '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', '/reference:System.Core.dll') + $sources
    Invoke-BuildTool $compiler $compilerArguments (Join-Path $payload 'compile.log')
    $probe = Join-Path $payload 'SetupProbe.exe'
    Invoke-BuildTool $compiler @('/nologo', '/target:exe', '/optimize+', '/debug-', "/platform:$arch", "/out:$probe", (Join-Path $productRoot 'installer\SetupProbe.cs')) (Join-Path $payload 'probe-compile.log')
    $m1Tests = Join-Path $payload 'M1Tests.exe'
    Invoke-BuildTool $compiler @('/nologo', '/target:exe', "/platform:$arch", "/out:$m1Tests", "/reference:$dll", '/reference:System.Xml.Linq.dll', '/reference:System.Core.dll', '/reference:Microsoft.CSharp.dll', '/reference:System.Windows.Forms.dll', '/reference:System.Drawing.dll', (Join-Path $productRoot 'tests\M1Tests.cs')) (Join-Path $payload 'm1-tests-build.log')
    Invoke-BuildTool $m1Tests @() (Join-Path $payload 'm1-tests.log')
    $engineTests = Join-Path $payload 'EngineTests.exe'
    Invoke-BuildTool $compiler @('/nologo', '/target:exe', "/platform:$arch", '/main:EngineTests', "/out:$engineTests", '/reference:System.Core.dll', (Join-Path $productRoot 'tests\EngineTests.cs'), (Join-Path $productRoot 'src\VisibleRangePlan.cs')) (Join-Path $payload 'engine-tests-build.log')
    Invoke-BuildTool $engineTests @() (Join-Path $payload 'engine-tests.log')
    $guardTests = Join-Path $payload 'EngineGuardTests.exe'
    Invoke-BuildTool $compiler @('/nologo', '/target:exe', "/platform:$arch", '/main:EngineGuardTests', "/out:$guardTests", '/reference:System.Core.dll', (Join-Path $productRoot 'tests\EngineGuardTests.cs')) (Join-Path $payload 'engine-guard-tests-build.log')
    Invoke-BuildTool $guardTests @($dll) (Join-Path $payload 'engine-guard-tests.log')
    Copy-Item -LiteralPath (Join-Path $productRoot 'README.md') -Destination (Join-Path $payload 'README.md')
    Copy-Item -LiteralPath (Join-Path $productRoot 'CHANGELOG.md') -Destination (Join-Path $payload 'CHANGELOG.md')
    [IO.File]::WriteAllText((Join-Path $payload 'product.id'), 'Workspace.ExcelSelectionExport.2A2A4B8C-6D6C-4E28-AB96-E34B9B4319A1', [Text.Encoding]::ASCII)
    Invoke-BuildTool $InnoCompiler @('/Qp', "/DPayloadDir=$payload", "/DProductVersion=$Version", "/DArch=$arch", "/O$outputRoot", (Join-Path $productRoot 'installer\SelectionExport.iss')) (Join-Path $payload 'installer-build.log')
}
$probeTests = Join-Path $outputRoot 'SetupProbeTests.exe'
Invoke-BuildTool $compiler @('/nologo', '/target:exe', '/platform:x64', '/main:SetupProbeTests', "/out:$probeTests", (Join-Path $productRoot 'installer\SetupProbe.cs'), (Join-Path $productRoot 'tests\SetupProbeTests.cs')) (Join-Path $outputRoot 'probe-tests-build.log')
Invoke-BuildTool $probeTests @() (Join-Path $outputRoot 'probe-tests.log')
$packages = @(Get-ChildItem -LiteralPath $outputRoot -Filter '*-Setup.exe' -File | Sort-Object Name)
$hashLines = @($packages | ForEach-Object { '{0}  {1}' -f (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), $_.Name })
[IO.File]::WriteAllLines((Join-Path $outputRoot 'SHA256SUMS.txt'), $hashLines, [Text.Encoding]::ASCII)
$manifest = [ordered]@{
    product = 'ExcelSelectionExport'; version = $Version; assemblyVersion = '0.1.0.0';
    utc = [DateTime]::UtcNow.ToString('o'); architectures = @('x86', 'x64');
    signed = $false; releaseClassification = 'unsigned evaluation build';
    actualExcelValidation = 'Record separately; building does not demonstrate Excel loading or functional acceptance.';
    compiler = (Get-Item -LiteralPath $compiler).VersionInfo.FileVersion;
    inno = (Get-Item -LiteralPath $InnoCompiler).VersionInfo.FileVersion;
    sourceFiles = $sourceRecords
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $outputRoot 'build-manifest.json') -Encoding UTF8
Write-Output "Unsigned evaluation packages: $outputRoot"
