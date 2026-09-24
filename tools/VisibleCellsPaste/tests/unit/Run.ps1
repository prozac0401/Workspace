param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot '..\..'))
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repositoryRoot 'artifacts\visible-cells-paste\unit' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework C# compiler not found.' }
$outputExe = Join-Path $OutputDirectory 'CoreTests.exe'
$compileArgs = @('/nologo', '/target:exe', '/r:System.Xml.Linq.dll', '/r:System.Core.dll', ('/out:' + $outputExe),
    (Join-Path $projectRoot 'src\core\Models.cs'), (Join-Path $projectRoot 'src\core\Planner.cs'),
    (Join-Path $projectRoot 'src\clipboard\SpreadsheetXmlParser.cs'),
    (Join-Path $projectRoot 'src\clipboard\BoundedZip.cs'), (Join-Path $projectRoot 'src\clipboard\XlsbDateSupplement.cs'),
    (Join-Path $PSScriptRoot 'CoreTests.cs'))
$quotedArgs = $compileArgs | ForEach-Object { '"' + $_ + '"' }
$compileProcess = Start-Process -FilePath $compiler -ArgumentList $quotedArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $OutputDirectory 'compile-stdout.txt') -RedirectStandardError (Join-Path $OutputDirectory 'compile-stderr.txt')
if ($compileProcess.ExitCode -ne 0) { Get-Content -LiteralPath (Join-Path $OutputDirectory 'compile-stdout.txt'); throw "Unit compilation failed: $($compileProcess.ExitCode)" }
$fixtureArgument = '"' + (Join-Path $projectRoot 'tests\fixtures\excel-vertical-5.xml') + '"'
$testProcess = Start-Process -FilePath $outputExe -ArgumentList $fixtureArgument -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $OutputDirectory 'results.txt') -RedirectStandardError (Join-Path $OutputDirectory 'test-stderr.txt')
Get-Content -LiteralPath (Join-Path $OutputDirectory 'results.txt') -Encoding UTF8
if ($testProcess.ExitCode -ne 0) { throw "Core unit tests failed: $($testProcess.ExitCode)" }

$nativeExe = Join-Path $OutputDirectory 'NativeClipboardTests.exe'
$nativeArgs = @('/nologo', '/target:exe', '/r:System.Xml.Linq.dll', '/r:System.Core.dll', ('/out:' + $nativeExe),
    (Join-Path $projectRoot 'src\core\Models.cs'), (Join-Path $projectRoot 'src\core\Planner.cs'),
    (Join-Path $projectRoot 'src\clipboard\SpreadsheetXmlParser.cs'), (Join-Path $projectRoot 'src\clipboard\BoundedZip.cs'),
    (Join-Path $projectRoot 'src\clipboard\XlsbDateSupplement.cs'), (Join-Path $PSScriptRoot 'NativeClipboardTests.cs'))
$nativeQuoted = $nativeArgs | ForEach-Object { '"' + $_ + '"' }
$nativeCompile = Start-Process -FilePath $compiler -ArgumentList $nativeQuoted -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $OutputDirectory 'native-compile-stdout.txt') -RedirectStandardError (Join-Path $OutputDirectory 'native-compile-stderr.txt')
if ($nativeCompile.ExitCode -ne 0) { Get-Content -LiteralPath (Join-Path $OutputDirectory 'native-compile-stdout.txt'); throw "Native unit compilation failed: $($nativeCompile.ExitCode)" }
$nativeFixture = '"' + (Join-Path $projectRoot 'tests\fixtures\native') + '"'
$nativeTests = Start-Process -FilePath $nativeExe -ArgumentList $nativeFixture -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput (Join-Path $OutputDirectory 'native-results.txt') -RedirectStandardError (Join-Path $OutputDirectory 'native-test-stderr.txt')
Get-Content -LiteralPath (Join-Path $OutputDirectory 'native-results.txt') -Encoding UTF8
if ($nativeTests.ExitCode -ne 0) { throw "Native unit tests failed: $($nativeTests.ExitCode)" }
