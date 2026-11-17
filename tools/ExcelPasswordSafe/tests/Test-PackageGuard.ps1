[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$OutputDirectory,[string]$Dotnet)
$ErrorActionPreference='Stop'
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$exe=Join-Path $OutputDirectory 'PackageGuardTests.exe'
if(-not $Dotnet) { $Dotnet=Join-Path $PSScriptRoot '..\..\..\.tools\dotnet\dotnet.exe' }
$Dotnet=(Resolve-Path -LiteralPath $Dotnet).Path
$lock=Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\crypto\compiler-lock.json') -Raw | ConvertFrom-Json
$compiler=Join-Path (Split-Path -Parent $Dotnet) ('sdk\'+$lock.sdkVersion+'\Roslyn\bincore\csc.dll')
if((Get-FileHash -LiteralPath $compiler -Algorithm SHA256).Hash -ine $lock.cscSha256) { throw 'Pinned Roslyn compiler changed' }
$references=@('mscorlib.dll','System.dll','System.Core.dll','System.Xml.dll','System.IO.Compression.dll') | ForEach-Object { '/r:'+(Join-Path $framework $_) }
& $Dotnet $compiler /nologo /target:exe /nostdlib+ /utf8output /warnaserror+ "/out:$exe" $references (Join-Path $PSScriptRoot '..\crypto\PackageGuard.cs') (Join-Path $PSScriptRoot 'PackageGuardTests.cs')
if($LASTEXITCODE -ne 0) { throw 'Package guard tests compile failed' }
$fixtures=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\upstream\1.1.0\ExcelPasswordSafe\tests\fixtures')).Path
$stdout=Join-Path $OutputDirectory 'guard-tests.log'
$stderr=Join-Path $OutputDirectory 'guard-tests-error.log'
$process=Start-Process -FilePath $exe -ArgumentList ('"'+$fixtures+'"') -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
[void]$process.Handle
try {
    if(-not $process.WaitForExit(60000)) { throw 'Package guard tests timed out; inspect test process.' }
    if($process.ExitCode -ne 0) { throw ('Package guard tests failed: '+(Get-Content -LiteralPath $stderr -Raw)) }
} finally { $process.Dispose() }
$lines=@(Get-Content -LiteralPath $stdout -Encoding UTF8)
$total=@($lines | Where-Object { $_ -match '^PASS total=\d+$' })
if($total.Count -ne 1) { throw 'Missing guard test count' }
@{status='PASS';assertions=[int]($total[0] -replace '^PASS total=','');inputBytesUnchanged='All cases';actualExcel='NotRun';timestamp=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'guard-results.json') -Encoding UTF8
$lines | Write-Output
