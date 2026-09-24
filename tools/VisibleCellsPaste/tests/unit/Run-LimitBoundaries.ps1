[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$productRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$repoRoot=[IO.Path]::GetFullPath((Join-Path $productRoot '..\..'))
$output=[IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\visible-cells-paste\unit-boundaries'))
$boundary=[IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts\visible-cells-paste'))+[IO.Path]::DirectorySeparatorChar
if (-not $output.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw 'Boundary output escaped the owned artifacts directory.' }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
function Invoke-Checked([string]$File,[string[]]$Arguments,[string]$Log) {
 $p=New-Object Diagnostics.Process
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$File
 $info.Arguments=[string]::Join(' ',@($Arguments | ForEach-Object { '"'+($_ -replace '"','\"')+'"' }))
 $info.UseShellExecute=$false; $info.CreateNoWindow=$true; $info.WindowStyle=[Diagnostics.ProcessWindowStyle]::Hidden
 $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true; $p.StartInfo=$info
 try {
  $started=$false
  for ($attempt=0; $attempt -lt 3; $attempt++) {
   try { $started=$p.Start(); if ($started) { break }; throw 'The process did not start.' }
   catch {
    $cause=$_.Exception.InnerException
    if ($attempt -ge 2 -or $cause -isnot [ComponentModel.Win32Exception] -or $cause.NativeErrorCode -notin @(5,32)) { throw }
    Write-Warning ("Process start temporarily failed with Win32 {0}; retrying the same command." -f $cause.NativeErrorCode)
    Start-Sleep -Milliseconds 1000
   }
  }
  if (-not $started) { throw 'The process did not start.' }
  $stdout=$p.StandardOutput.ReadToEndAsync(); $stderr=$p.StandardError.ReadToEndAsync()
  $p.WaitForExit()
  $text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
  [IO.File]::WriteAllText($Log,$text,[Text.Encoding]::UTF8)
  Write-Output $text
  if ($p.ExitCode -ne 0) { throw "Process failed with exit $($p.ExitCode); see $Log" }
 } finally { $p.Dispose() }
}
$exe=Join-Path $output 'PayloadBoundaryTests.exe'
$argsToCompile=@('/nologo','/target:exe','/main:PayloadBoundaryTests','/reference:System.Core.dll','/reference:System.Xml.Linq.dll',"/out:$exe")
$argsToCompile+=@('src\core\Models.cs','src\core\Planner.cs','src\clipboard\SpreadsheetXmlParser.cs','src\clipboard\BoundedZip.cs','src\clipboard\XlsbDateSupplement.cs','tests\unit\PayloadBoundaryTests.cs') | ForEach-Object { Join-Path $productRoot $_ }
Invoke-Checked $compiler $argsToCompile (Join-Path $output 'compile.log')
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Compiler did not create the boundary test executable.' }
Invoke-Checked $exe @() (Join-Path $output 'results.txt')
Write-Output 'Pure boundary tests only. No Excel, clipboard, installation or registry calls.'
