[CmdletBinding()]
param([ValidateSet('x86','x64')][string]$Architecture='x64')
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$productRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$repoRoot=[IO.Path]::GetFullPath((Join-Path $productRoot '..\..'))
$output=Join-Path $repoRoot "artifacts\visible-cells-paste\ui-smoke\$Architecture"
New-Item -ItemType Directory -Path $output -Force | Out-Null
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
$exe=Join-Path $output 'UiSmokeProbe.exe'
$arguments=@('/nologo','/target:exe','/main:UiSmokeProbe',"/platform:$Architecture","/out:$exe",'/reference:Microsoft.CSharp.dll','/reference:System.Core.dll','/reference:System.IO.Compression.dll',
    (Join-Path $productRoot 'tests\excel_e2e\UiSmokeProbe.cs'),(Join-Path $productRoot 'tests\excel_e2e\ExcelProbe.cs'))
$info=New-Object Diagnostics.ProcessStartInfo
$info.FileName=$compiler
$info.Arguments=[string]::Join(' ',@($arguments | ForEach-Object { '"'+$_+'"' }))
$info.UseShellExecute=$false; $info.CreateNoWindow=$true
$info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
$process=New-Object Diagnostics.Process
$process.StartInfo=$info
try {
    if (-not $process.Start()) { throw 'Compiler did not start.' }
    $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $text=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
    [IO.File]::WriteAllText((Join-Path $output 'compile.log'),$text,[Text.Encoding]::UTF8)
    if ($process.ExitCode -ne 0) { throw "Compiler failed: $text" }
} finally { $process.Dispose() }
Write-Output "Built ONLY: $exe"
Write-Output 'No product build, Excel launch, installation or registration change was performed.'
