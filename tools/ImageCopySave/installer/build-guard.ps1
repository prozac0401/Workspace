[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (-not $output.StartsWith(($root + '\artifacts\'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Guard output must be inside this worktree artifacts.' }
$current = $output
while ($current -ne $root) {
    $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
    if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Guard output may not traverse a reparse point.' }
    $current = [IO.Path]::GetDirectoryName($current)
}
[IO.Directory]::CreateDirectory($output) | Out-Null
$utf8 = New-Object Text.UTF8Encoding($false)
$msvc = Join-Path $root '.tools/image-copy-save-native/msvc'
$sdk = Join-Path $root '.tools/image-copy-save-native/sdk'
$versions = @(Get-ChildItem -LiteralPath (Join-Path $sdk 'Include') -Directory | Where-Object { $_.Name -match '^10\.0\.\d+\.0$' } | Sort-Object { [version]$_.Name } -Descending)
if (-not $versions.Count) { throw 'Windows SDK is unavailable.' }
$version = $versions[0].Name
$compiler = Join-Path $msvc 'bin/Hostx64/x64/cl.exe'
foreach ($path in @($compiler, (Join-Path $msvc 'include/vector'), (Join-Path $msvc 'lib/x64/libcmt.lib'), (Join-Path $sdk ('Include/'+$version+'/um/msi.h')), (Join-Path $sdk ('Lib/'+$version+'/um/x64/msi.lib')))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Incomplete guard build toolchain: $path" }
}
$script:guardLaunchRetries = New-Object 'System.Collections.Generic.List[string]'
function Run([string[]]$Arguments, [string]$LogName, [string]$Executable = $compiler) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable; $info.WorkingDirectory = $output
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.Arguments = (@($Arguments | ForEach-Object {
        if ($_.Contains('"') -or $_.EndsWith('\')) { throw 'Ambiguous native guard argument.' }
        '"' + $_ + '"'
    }) -join ' ')
    $process = $null
    try { $process = [Diagnostics.Process]::Start($info) }
    catch [ComponentModel.Win32Exception] {
        if ($_.Exception.NativeErrorCode -ne 5) { throw }
        # Newly linked local test binaries have transiently been unavailable
        # while Windows inspected them. Retry the identical normal launch once;
        # persistent policy or access failures still stop the build.
        $script:guardLaunchRetries.Add($LogName)
        Start-Sleep -Seconds 3
        $process = [Diagnostics.Process]::Start($info)
    }
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'Native guard build/test exceeded the timeout.' }
        $text = $stdout.Result + $stderr.Result
        [IO.File]::WriteAllText((Join-Path $output $LogName), $text, $utf8)
        if ($process.ExitCode -ne 0) { throw "Native guard step $LogName failed ($($process.ExitCode)). See $output." }
        return $text
    } finally { $process.Dispose() }
}
$source = Join-Path $PSScriptRoot 'guard/Guard.cpp'
$testsSource = Join-Path $PSScriptRoot 'guard/GuardTests.cpp'
$sourceHashes = @{}
foreach ($path in @($source, $testsSource, $PSCommandPath)) { $sourceHashes[[IO.Path]::GetFileName($path)] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
$priorPath = $env:PATH; $priorInclude = $env:INCLUDE; $priorLib = $env:LIB
try {
    $env:PATH = (Join-Path $msvc 'bin/Hostx64/x64') + ';' + (Join-Path $sdk ('bin/'+$version+'/x64')) + ';' + $env:PATH
    $env:INCLUDE = @((Join-Path $msvc 'include'), (Join-Path $sdk ('Include/'+$version+'/ucrt')), (Join-Path $sdk ('Include/'+$version+'/shared')), (Join-Path $sdk ('Include/'+$version+'/um'))) -join ';'
    $env:LIB = @((Join-Path $msvc 'lib/x64'), (Join-Path $sdk ('Lib/'+$version+'/ucrt/x64')), (Join-Path $sdk ('Lib/'+$version+'/um/x64'))) -join ';'
    $dll = Join-Path $output 'ImageCopySave.Guard.dll'
    $testExe = Join-Path $output 'ImageCopySave.Guard.Tests.exe'
    $common = @('/nologo','/std:c++17','/EHsc','/MT','/O2','/W4','/WX','/utf-8','/guard:cf','/DUNICODE','/D_UNICODE','/D_WIN32_WINNT=0x0A00','/DWINVER=0x0A00')
    $link = @('/link','/DYNAMICBASE','/NXCOMPAT','/GUARD:CF','/WX','/MACHINE:X64','msi.lib','bcrypt.lib','advapi32.lib')
    Run ($common + @('/LD',$source,('/Fo'+(Join-Path $output 'guard.obj')),('/Fe'+$dll)) + $link) 'guard-build.log' | Out-Null
    Run ($common + @($testsSource,('/Fo'+(Join-Path $output 'guard-tests.obj')),('/Fe'+$testExe)) + $link) 'guard-tests-build.log' | Out-Null
    $testOutput = Run @('--fixtures',(Join-Path $output ('fixtures-'+[Guid]::NewGuid().ToString('N')))) 'guard-tests.log' $testExe
    $testLine = @($testOutput -split '[\r\n]+' | Where-Object { $_.StartsWith('{"status":') })[-1]
    $tests = $testLine | ConvertFrom-Json
    if ($tests.status -ne 'PASS' -or $tests.failed -ne 0 -or $tests.passed -lt 20) { throw 'Native ownership tests did not all pass.' }
    foreach ($path in @($source, $testsSource, $PSCommandPath)) {
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $sourceHashes[[IO.Path]::GetFileName($path)]) { throw 'Guard sources changed during build.' }
    }
    $metadata = [ordered]@{ status='PASS'; schema=1; dll=$dll; dllSha256=(Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash; architecture='x64'; runtime='static CRT'; sdk=$version; compilerVersion=(Get-Item -LiteralPath $compiler).VersionInfo.FileVersion; sourceHashes=$sourceHashes; tests=$tests; normalLaunchRetries=@($script:guardLaunchRetries.ToArray()); registryFixtureCreated=$true; registryFixtureCleaned=$true; productRegistrationModified=$false; installed=$false }
    [IO.File]::WriteAllText((Join-Path $output 'build-metadata.json'), ($metadata | ConvertTo-Json -Depth 6), $utf8)
    Write-Output "Native ownership guard: $dll"
    Write-Output "Native ownership checks passed: $($tests.passed)"
} finally { $env:PATH=$priorPath; $env:INCLUDE=$priorInclude; $env:LIB=$priorLib }
