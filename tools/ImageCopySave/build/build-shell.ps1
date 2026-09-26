[CmdletBinding()]
param([string]$VCToolsRoot, [string]$WindowsSdkRoot, [string]$WindowsSdkVersion)
$ErrorActionPreference = 'Stop'
$toolRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repoRoot = (Resolve-Path (Join-Path $toolRoot '../..')).Path
$output = Join-Path $repoRoot 'artifacts/image-copy-save/native-shell'
New-Item -ItemType Directory -Path $output -Force | Out-Null
function Invoke-Captured([string]$Executable, [string[]]$Arguments, [string]$LogName) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Executable; $info.WorkingDirectory = $output
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $quoted = foreach ($argument in $Arguments) {
        if ($argument.Contains('"') -or $argument.EndsWith('\')) { throw 'Ambiguous native build argument.' }
        '"' + $argument + '"'
    }
    $info.Arguments = $quoted -join ' '
    $process = [System.Diagnostics.Process]::Start($info)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(120000)) { $process.Kill(); throw 'Native build or direct COM test exceeded its deadline.' }
        $text = $stdout.Result + [Environment]::NewLine + $stderr.Result
        [System.IO.File]::WriteAllText((Join-Path $output $LogName), $text)
        Write-Host $text
        if ($process.ExitCode -ne 0) { throw ('Native command failed: ' + $LogName + ' exit=' + $process.ExitCode) }
    } finally { $process.Dispose() }
}
$programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
if (-not $VCToolsRoot) {
    $localMsvc = Join-Path $repoRoot '.tools/image-copy-save-native/msvc'
    if ((Test-Path -LiteralPath (Join-Path $localMsvc 'include/vector')) -and (Test-Path -LiteralPath (Join-Path $localMsvc 'lib/x64/libcmt.lib'))) { $VCToolsRoot = $localMsvc }
}
if (-not $VCToolsRoot) {
    $vswhere = Join-Path $programFilesX86 'Microsoft Visual Studio/Installer/vswhere.exe'
    $installations = @()
    if (Test-Path -LiteralPath $vswhere) {
        $info = New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName = $vswhere
        $info.Arguments = '-all -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath'
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.RedirectStandardOutput = $true
        $p = [System.Diagnostics.Process]::Start($info)
        try { $text = $p.StandardOutput.ReadToEnd(); $p.WaitForExit(); if ($p.ExitCode -eq 0) { $installations = @($text -split '[\r\n]+' | Where-Object { $_ }) } }
        finally { $p.Dispose() }
    }
    foreach ($installation in $installations) {
        $msvc = Join-Path $installation 'VC/Tools/MSVC'
        if (-not (Test-Path -LiteralPath $msvc)) { continue }
        foreach ($version in (Get-ChildItem -LiteralPath $msvc -Directory | Sort-Object { [version]$_.Name } -Descending)) {
            if ((Test-Path -LiteralPath (Join-Path $version.FullName 'include/vector')) -and (Test-Path -LiteralPath (Join-Path $version.FullName 'lib/x64/libcmt.lib'))) { $VCToolsRoot = $version.FullName; break }
        }
        if ($VCToolsRoot) { break }
    }
}
if (-not $VCToolsRoot) { throw 'MSVC x64 compiler, headers and libraries are required. Install the C++ build workload or specify a complete -VCToolsRoot. No machine configuration was changed.' }
$VCToolsRoot = (Resolve-Path -LiteralPath $VCToolsRoot).Path
if (-not $WindowsSdkRoot) {
    $localSdk = Join-Path $repoRoot '.tools/image-copy-save-native/sdk'
    if (Test-Path -LiteralPath (Join-Path $localSdk 'Include') -PathType Container) { $WindowsSdkRoot = $localSdk }
    else {
        $key = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots' -ErrorAction SilentlyContinue
        if ($key.KitsRoot10) { $WindowsSdkRoot = $key.KitsRoot10 }
        else { $WindowsSdkRoot = Join-Path $programFilesX86 'Windows Kits/10' }
    }
}
if (-not (Test-Path -LiteralPath $WindowsSdkRoot)) { throw 'Windows SDK 10/11 headers, libraries and tools are required. No SDK was installed automatically.' }
$WindowsSdkRoot = (Resolve-Path -LiteralPath $WindowsSdkRoot).Path
if (-not $WindowsSdkVersion) {
    $candidates = @(Get-ChildItem -LiteralPath (Join-Path $WindowsSdkRoot 'Include') -Directory | Where-Object { $_.Name -match '^10\.0\.\d+\.0$' } | Sort-Object { [version]$_.Name } -Descending)
    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath (Join-Path $candidate.FullName 'um/Windows.h')) -and (Test-Path -LiteralPath (Join-Path $WindowsSdkRoot ('Lib/' + $candidate.Name + '/um/x64/shell32.lib')))) { $WindowsSdkVersion = $candidate.Name; break }
    }
}
if (-not $WindowsSdkVersion -or [version]$WindowsSdkVersion -lt [version]'10.0.22000.0') { throw 'A Windows 11 SDK (10.0.22000.0 or later) is required for this evaluation build.' }
$compiler = Join-Path $VCToolsRoot 'bin/Hostx64/x64/cl.exe'
foreach ($file in @($compiler, (Join-Path $VCToolsRoot 'include/vector'), (Join-Path $VCToolsRoot 'lib/x64/libcmt.lib'), (Join-Path $WindowsSdkRoot ('Include/' + $WindowsSdkVersion + '/um/shobjidl.h')))) {
    if (-not (Test-Path -LiteralPath $file)) { throw ('Incomplete native build toolchain: ' + $file) }
}
$oldPath = $env:PATH; $oldInclude = $env:INCLUDE; $oldLib = $env:LIB
try {
    $env:PATH = (Join-Path $VCToolsRoot 'bin/Hostx64/x64') + ';' + (Join-Path $WindowsSdkRoot ('bin/' + $WindowsSdkVersion + '/x64')) + ';' + $env:PATH
    $env:INCLUDE = @((Join-Path $VCToolsRoot 'include'), (Join-Path $WindowsSdkRoot ('Include/' + $WindowsSdkVersion + '/ucrt')), (Join-Path $WindowsSdkRoot ('Include/' + $WindowsSdkVersion + '/shared')), (Join-Path $WindowsSdkRoot ('Include/' + $WindowsSdkVersion + '/um')), (Join-Path $WindowsSdkRoot ('Include/' + $WindowsSdkVersion + '/winrt'))) -join ';'
    $env:LIB = @((Join-Path $VCToolsRoot 'lib/x64'), (Join-Path $WindowsSdkRoot ('Lib/' + $WindowsSdkVersion + '/ucrt/x64')), (Join-Path $WindowsSdkRoot ('Lib/' + $WindowsSdkVersion + '/um/x64'))) -join ';'
    $shellSource = Join-Path $toolRoot 'source/ImageCopySave.Shell/ImageCopySave.Shell.cpp'
    $shellDef = Join-Path $toolRoot 'source/ImageCopySave.Shell/ImageCopySave.Shell.def'
    $testsSource = Join-Path $toolRoot 'source/ImageCopySave.Shell.Tests/ShellTests.cpp'
    $dll = Join-Path $output 'ImageCopySave.Shell.dll'; $exe = Join-Path $output 'ImageCopySave.Shell.Tests.exe'
    $common = @('/nologo', '/std:c++17', '/EHsc', '/MT', '/O2', '/W4', '/WX', '/utf-8', '/guard:cf', '/DUNICODE', '/D_UNICODE', '/DWIN32_LEAN_AND_MEAN', '/DNOMINMAX', '/D_WIN32_WINNT=0x0A00', '/DWINVER=0x0A00')
    Invoke-Captured $compiler ($common + @('/LD', $shellSource, ('/Fo' + (Join-Path $output 'shell.obj')), ('/Fe' + $dll), '/link', ('/DEF:' + $shellDef), '/DYNAMICBASE', '/NXCOMPAT', '/GUARD:CF', '/WX', '/MACHINE:X64', 'ole32.lib', 'shell32.lib', 'user32.lib', 'uuid.lib')) 'shell-build.log'
    Invoke-Captured $compiler ($common + @($testsSource, ('/Fo' + (Join-Path $output 'tests.obj')), ('/Fe' + $exe), '/link', '/DYNAMICBASE', '/NXCOMPAT', '/GUARD:CF', '/WX', '/MACHINE:X64', 'ole32.lib', 'shell32.lib', 'user32.lib', 'uuid.lib')) 'tests-build.log'
    $report = Join-Path $output 'shell-results.json'
    if (Test-Path -LiteralPath $report) { Remove-Item -LiteralPath $report }
    Invoke-Captured $exe @('--dll', $dll, '--report', $report) 'shell-tests.log'
    $results = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    if ($results.failed -ne 0 -or $results.total -lt 1 -or $results.passed -ne $results.total) { throw 'Native policy/direct COM tests did not all pass.' }
    $sourceHashes = @{}
    foreach ($sourceFile in Get-ChildItem -LiteralPath (Join-Path $toolRoot 'source/ImageCopySave.Shell') -File | Where-Object { $_.Extension -in @('.cpp', '.h', '.def') }) {
        $sourceHashes[$sourceFile.Name] = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
    }
    $metadata = [ordered]@{ timestamp = [DateTimeOffset]::UtcNow.ToString('o'); compilerVersion = (Get-Item -LiteralPath $compiler).VersionInfo.FileVersion; msvc = (Split-Path $VCToolsRoot -Leaf); sdk = $WindowsSdkVersion; architecture = 'x64'; runtime = 'static CRT'; source = 'IExplorerCommand and IObjectWithSite native DLL'; registered = $false; explorerUiTested = $false; clipboardAccessInTests = $false; total = $results.total; dllSha256 = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash }
    $metadata.sourceHashes = $sourceHashes
    $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'build-metadata.json') -Encoding UTF8
    Write-Host 'Native policy/direct COM tests passed. Explorer placement, clipboard-driven menu visibility, installation and removal are NOT RUN.'
} finally { $env:PATH = $oldPath; $env:INCLUDE = $oldInclude; $env:LIB = $oldLib }
