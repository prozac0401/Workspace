[CmdletBinding()]
param([ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.]+)?$')][string]$Version = '0.1.0')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$productRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repoRoot = [IO.Path]::GetFullPath((Join-Path $productRoot '..\..'))
$output = [IO.Path]::GetFullPath((Join-Path $repoRoot "artifacts\visible-cells-paste\$Version"))
$expected = [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\visible-cells-paste')) + [IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($expected, [StringComparison]::OrdinalIgnoreCase)) { throw 'Output path escaped the product artifact directory.' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw '.NET Framework 4.8 C# compiler is required on the build machine.' }
$package = Join-Path $output 'package'
# Do not delete old output: package construction uses an explicit inventory, and ZIP is replaced only after successful creation.
New-Item -ItemType Directory -Path $output,$package -Force | Out-Null
$sources = @(Get-ChildItem -LiteralPath (Join-Path $productRoot 'src') -Filter '*.cs' -Recurse -File | Sort-Object FullName | ForEach-Object FullName)
if ($sources.Count -eq 0) { throw 'No add-in sources.' }
function Invoke-Tool([string]$Executable, [string[]]$Arguments, [string]$Log) {
    $process = New-Object Diagnostics.Process
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Executable
    $info.Arguments = [string]::Join(' ', @($Arguments | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }))
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process.StartInfo = $info
    try {
        for($attempt=1;$attempt -le 3;$attempt++) {
            try {
                if (-not $process.Start()) { throw "Cannot start $Executable" }
                break
            } catch {
                $nativeCode=$null;$exception=$_.Exception
                while($null -ne $exception) { if($exception -is [ComponentModel.Win32Exception]){$nativeCode=$exception.NativeErrorCode;break};$exception=$exception.InnerException }
                $record=[ordered]@{utc=[DateTime]::UtcNow.ToString('o');executable=$Executable;attempt=$attempt;state='process-create-failed';nativeError=$nativeCode}
                Add-Content -LiteralPath ($Log+'.launch.jsonl') -Value ($record | ConvertTo-Json -Compress) -Encoding UTF8
                if(($nativeCode -eq 5 -or $nativeCode -eq 32) -and $attempt -lt 3) { Start-Sleep -Milliseconds 1000;continue }
                throw
            }
        }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $result = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($Log, $result, [Text.Encoding]::UTF8)
        if ($process.ExitCode -ne 0) { throw "Process failed ($($process.ExitCode)). See $Log : $result" }
    } finally { $process.Dispose() }
}
function Compile([string[]]$Arguments, [string]$Log) { Invoke-Tool $compiler $Arguments $Log }
$references = @('/reference:Microsoft.CSharp.dll','/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll','/reference:System.Core.dll','/reference:System.Xml.Linq.dll','/reference:System.Xml.dll')
$payloadHashes = @()
$inventory = @()
foreach ($arch in @('x86','x64')) {
    $archDir = Join-Path $package $arch
    New-Item -ItemType Directory -Path $archDir -Force | Out-Null
    $dll = Join-Path $archDir 'VisibleCellsPaste.AddIn.dll'
    Compile (@('/nologo','/target:library','/optimize+','/debug-',"/platform:$arch","/out:$dll") + $references + $sources) (Join-Path $output "compile-$arch.log")
    $payloadHashes += "$arch/VisibleCellsPaste.AddIn.dll " + (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()
    $inventory += "$arch/VisibleCellsPaste.AddIn.dll"
}
$integrity = Join-Path $output 'PayloadHashes.txt'
[IO.File]::WriteAllLines($integrity, $payloadHashes, [Text.Encoding]::ASCII)
$setupExe = Join-Path $package 'VisibleCellsPaste.Setup.exe'
Compile (@('/nologo','/target:winexe','/optimize+','/debug-','/platform:anycpu',"/out:$setupExe", "/resource:$integrity,PayloadHashes.txt", ("/win32manifest:" + (Join-Path $productRoot 'installer\Setup.manifest'))) + $references + (Join-Path $productRoot 'installer\Setup.cs')) (Join-Path $output 'compile-setup.log')
$inventory += 'VisibleCellsPaste.Setup.exe'
$coreTests = Join-Path $output 'CoreTests.exe'
$coreInputs = @((Join-Path $productRoot 'tests\unit\CoreTests.cs'),(Join-Path $productRoot 'src\core\Models.cs'),(Join-Path $productRoot 'src\core\Planner.cs'),(Join-Path $productRoot 'src\clipboard\SpreadsheetXmlParser.cs'),(Join-Path $productRoot 'src\clipboard\BoundedZip.cs'),(Join-Path $productRoot 'src\clipboard\XlsbDateSupplement.cs'))
Compile (@('/nologo','/target:exe','/main:CoreTests',"/out:$coreTests") + $references + $coreInputs) (Join-Path $output 'core-tests-build.log')
Invoke-Tool $coreTests @((Join-Path $productRoot 'tests\fixtures\excel-vertical-5.xml')) (Join-Path $output 'core-tests.log')

$nativeTests = Join-Path $output 'NativeClipboardTests.exe'
$nativeInputs = @($coreInputs | Where-Object { [IO.Path]::GetFileName($_) -ne 'CoreTests.cs' }) + @((Join-Path $productRoot 'tests\unit\NativeClipboardTests.cs'))
Compile (@('/nologo','/target:exe','/main:NativeClipboardTests',"/out:$nativeTests") + $references + $nativeInputs) (Join-Path $output 'native-clipboard-tests-build.log')
$nativeFixtureRoot = Join-Path $productRoot 'tests\fixtures\native'
$nativeFixtures = @(Get-ChildItem -LiteralPath $nativeFixtureRoot -File | Sort-Object FullName | ForEach-Object FullName)
Invoke-Tool $nativeTests @($nativeFixtureRoot) (Join-Path $output 'native-clipboard-tests.log')
$nativeTestArch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
$testLibrary = Join-Path $output 'VisibleCellsPaste.AddIn.dll'
Copy-Item -LiteralPath (Join-Path $package "$nativeTestArch\VisibleCellsPaste.AddIn.dll") -Destination $testLibrary -Force
$bulkTests = Join-Path $output 'CellSnapshotReaderTests.exe'
Compile (@('/nologo','/target:exe','/main:CellSnapshotReaderTests',"/platform:$nativeTestArch","/out:$bulkTests","/reference:$testLibrary") + $references + @((Join-Path $productRoot 'tests\unit\CellSnapshotReaderTests.cs'))) (Join-Path $output 'bulk-snapshot-tests-build.log')
Invoke-Tool $bulkTests @() (Join-Path $output 'bulk-snapshot-tests.log')
$lifecycleTests = Join-Path $output 'AddInLifecycleTests.exe'
Compile (@('/nologo','/target:exe','/main:AddInLifecycleTests',"/platform:$nativeTestArch","/out:$lifecycleTests","/reference:$testLibrary") + $references + @((Join-Path $productRoot 'tests\unit\AddInLifecycleTests.cs'))) (Join-Path $output 'addin-lifecycle-tests-build.log')
Invoke-Tool $lifecycleTests @() (Join-Path $output 'addin-lifecycle-tests.log')
$globalRecoveryTests = Join-Path $output 'GlobalStateRecoveryTests.exe'
Compile (@('/nologo','/target:exe','/main:GlobalStateRecoveryTests',"/platform:$nativeTestArch","/out:$globalRecoveryTests","/reference:$testLibrary") + $references + @((Join-Path $productRoot 'tests\unit\GlobalStateRecoveryTests.cs'))) (Join-Path $output 'global-state-recovery-tests-build.log')
Invoke-Tool $globalRecoveryTests @() (Join-Path $output 'global-state-recovery-tests.log')
$presentationTests = Join-Path $output 'PresentationAndEntryTests.exe'
Compile (@('/nologo','/target:exe','/main:PresentationAndEntryTests',"/platform:$nativeTestArch","/out:$presentationTests","/reference:$testLibrary") + $references + @((Join-Path $productRoot 'tests\unit\PresentationAndEntryTests.cs'))) (Join-Path $output 'presentation-entry-tests-build.log')
Invoke-Tool $presentationTests @() (Join-Path $output 'presentation-entry-tests.log')
$setupTests = Join-Path $output 'SetupTests.exe'
Compile (@('/nologo','/target:exe','/main:SetupTests',"/out:$setupTests") + $references + @((Join-Path $productRoot 'installer\Setup.cs'),(Join-Path $productRoot 'installer\SetupTests.cs'))) (Join-Path $output 'setup-tests-build.log')
Invoke-Tool $setupTests @((Join-Path $output 'setup-tests-owned-temp')) (Join-Path $output 'setup-tests.log')
foreach ($launcher in @('Install.cmd','Uninstall.cmd')) {
    Copy-Item -LiteralPath (Join-Path $productRoot "installer\$launcher") -Destination (Join-Path $package $launcher) -Force
    $inventory += $launcher
}
[IO.File]::WriteAllText((Join-Path $package 'version.txt'), $Version, [Text.Encoding]::ASCII)
$inventory += 'version.txt'
foreach ($name in @('README.md','CHANGELOG.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $productRoot $name))) { throw "Required release document missing: $name" }
    Copy-Item -LiteralPath (Join-Path $productRoot $name) -Destination (Join-Path $package $name) -Force
    $inventory += $name
}
$docs = @('architecture.md','clipboard-compatibility.md','undo-safety.md','install-security.md','test-report.md','release-checklist.md','native-format-research.md')
New-Item -ItemType Directory -Path (Join-Path $package 'docs') -Force | Out-Null
foreach ($doc in $docs) {
    if (-not (Test-Path -LiteralPath (Join-Path $productRoot "docs\$doc"))) { throw "Required release document missing: docs/$doc" }
    Copy-Item -LiteralPath (Join-Path $productRoot "docs\$doc") -Destination (Join-Path $package "docs\$doc") -Force
    $inventory += "docs/$doc"
}
$sourceManifest = @($sources + $nativeFixtures + @((Join-Path $productRoot 'installer\Setup.cs'),(Join-Path $productRoot 'installer\Setup.manifest'),(Join-Path $productRoot 'installer\SetupTests.cs'),(Join-Path $productRoot 'tests\unit\CoreTests.cs'),(Join-Path $productRoot 'tests\unit\NativeClipboardTests.cs'),(Join-Path $productRoot 'tests\unit\CellSnapshotReaderTests.cs'),(Join-Path $productRoot 'tests\unit\AddInLifecycleTests.cs'),(Join-Path $productRoot 'tests\unit\GlobalStateRecoveryTests.cs'),(Join-Path $productRoot 'tests\unit\PresentationAndEntryTests.cs'),(Join-Path $productRoot 'tests\fixtures\excel-vertical-5.xml'),(Join-Path $productRoot 'installer\Install.cmd'),(Join-Path $productRoot 'installer\Uninstall.cmd'),(Join-Path $PSScriptRoot 'verify-package.ps1'),(Join-Path $PSScriptRoot 'verify-assembly.ps1'),$PSCommandPath) | ForEach-Object { [ordered]@{ path = $_.Substring($repoRoot.Length + 1); sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant() } })
$manifest = [ordered]@{ product='VisibleCellsPaste'; version=$Version; assemblyVersion='0.1.0.0'; utc=[DateTime]::UtcNow.ToString('o'); architectures=@('x86','x64'); signed=$false; classification='unsigned release build'; actualExcelValidation='See docs/test-report.md. Successful build does not establish Excel acceptance.'; compiler=(Get-Item -LiteralPath $compiler).VersionInfo.FileVersion; sources=$sourceManifest }
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $package 'build-manifest.json') -Encoding UTF8
$inventory += 'build-manifest.json'
$hashLines = @($inventory | Sort-Object | ForEach-Object { (Get-FileHash -LiteralPath (Join-Path $package $_) -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + $_ })
[IO.File]::WriteAllLines((Join-Path $package 'SHA256SUMS.txt'),$hashLines,[Text.Encoding]::UTF8)
$inventory += 'SHA256SUMS.txt'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipFile = Join-Path $output "VisibleCellsPaste_$Version.zip"
$tempZip = Join-Path $output ([Guid]::NewGuid().ToString('N') + '.zip')
$stream = [IO.File]::Open($tempZip,[IO.FileMode]::CreateNew)
try {
    $archive = New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
    try { foreach ($item in $inventory | Sort-Object) { [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $package $item),$item,[IO.Compression.CompressionLevel]::Optimal) | Out-Null } }
    finally { $archive.Dispose() }
} finally { $stream.Dispose() }
& (Join-Path $PSScriptRoot 'verify-package.ps1') -ZipPath $tempZip
Move-Item -LiteralPath $tempZip -Destination $zipFile -Force
[IO.File]::WriteAllText((Join-Path $output 'SHA256SUMS.txt'),(Get-FileHash -LiteralPath $zipFile -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($zipFile) + [Environment]::NewLine,[Text.Encoding]::ASCII)
Write-Output "Unsigned release package: $zipFile"
