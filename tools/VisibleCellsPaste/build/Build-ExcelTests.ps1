[CmdletBinding()]
param([ValidateSet('x86','x64')][string]$Architecture='x64')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$productRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repoRoot=[IO.Path]::GetFullPath((Join-Path $productRoot '..\..'))
$output=[IO.Path]::GetFullPath((Join-Path $repoRoot "artifacts\visible-cells-paste\excel-e2e\$Architecture"))
$boundary=[IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\visible-cells-paste\excel-e2e')) + [IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw 'Excel test output escaped its artifact directory.' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$references=@('/reference:System.Core.dll','/reference:System.Xml.Linq.dll','/reference:System.Xml.dll','/reference:Microsoft.CSharp.dll','/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll')
function Compile([string[]]$Arguments,[string]$Log) {
    $process=New-Object Diagnostics.Process
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$compiler
    $info.Arguments=[string]::Join(' ',@($Arguments | ForEach-Object { '"'+($_ -replace '"','\"')+'"' }))
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
    $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true; $process.StartInfo=$info
    try {
        if (-not $process.Start()) { throw 'Compiler did not start.' }
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText($Log,$text,[Text.Encoding]::UTF8)
        if ($process.ExitCode -ne 0) { throw "Compiler failed. See $Log : $text" }
    } finally { $process.Dispose() }
}
$sources=@(Get-ChildItem -LiteralPath (Join-Path $productRoot 'src') -Recurse -Filter '*.cs' -File | Sort-Object FullName | ForEach-Object FullName)
$dll=Join-Path $output 'VisibleCellsPaste.AddIn.dll'
Compile (@('/nologo','/target:library','/define:VCP_TESTING',"/platform:$Architecture","/out:$dll")+$references+$sources) (Join-Path $output 'compile-fault-enabled-library.log')
$exe=Join-Path $output 'FunctionalTests.exe'
$testSources=@((Join-Path $productRoot 'tests\excel_e2e\FunctionalTests.cs'),(Join-Path $productRoot 'tests\excel_e2e\ExcelProbe.cs'))
Compile (@('/nologo','/target:exe','/main:FunctionalTests',"/platform:$Architecture","/out:$exe","/reference:$dll",'/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll')+$references+$testSources) (Join-Path $output 'compile-functional-tests.log')
$built=@($exe)
foreach ($testName in @('ClipboardIntegrationTests','ExtendedTests','PerformanceTests','OverlapClipboardTests','RemainingSafetyTests','ClipboardAdversarialTests')) {
    $testSource=Join-Path $productRoot ("tests\excel_e2e\"+$testName+'.cs')
    if (Test-Path -LiteralPath $testSource -PathType Leaf) {
        $testExe=Join-Path $output ($testName+'.exe')
        $optionalSources=@($testSource,(Join-Path $productRoot 'tests\excel_e2e\ExcelProbe.cs'))
        Compile (@('/nologo','/target:exe',"/main:$testName","/platform:$Architecture","/out:$testExe","/reference:$dll",'/reference:System.IO.Compression.dll','/reference:System.IO.Compression.FileSystem.dll')+$references+$optionalSources) (Join-Path $output ("compile-"+$testName+'.log'))
        $built+=$testExe
    }
}
Write-Output ("Built ONLY: "+[string]::Join(', ',$built))
Write-Output 'Fault-enabled artifacts are test-only and are outside the package directory. This command does not start Excel, invoke tests, install, or change registration.'
