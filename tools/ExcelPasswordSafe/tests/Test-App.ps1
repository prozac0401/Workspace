[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AppPath, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$AppPath = (Resolve-Path -LiteralPath $AppPath).Path
if(-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot ('..\..\..\artifacts\excel-password-safe\app-tests\' + [guid]::NewGuid().ToString('N')) }
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$references = @('System.dll','System.Core.dll','System.Security.dll','System.Xaml.dll') | ForEach-Object { '/r:' + (Join-Path $framework $_) }
$references += @('WindowsBase.dll','PresentationFramework.dll','PresentationCore.dll') | ForEach-Object { '/r:' + (Join-Path (Join-Path $framework 'WPF') $_) }
$testExe = Join-Path $OutputDirectory 'AppTests.exe'
& (Join-Path $framework 'csc.exe') /nologo /target:exe "/out:$testExe" "/r:$AppPath" $references (Join-Path $PSScriptRoot 'AppTests.cs')
if($LASTEXITCODE -ne 0) { throw 'App test compile failed' }
Copy-Item -LiteralPath $AppPath -Destination (Join-Path $OutputDirectory 'ExcelPasswordSafe.exe')
$stdout=Join-Path $OutputDirectory 'app-tests.log'
$stderr=Join-Path $OutputDirectory 'app-tests-error.log'
# Use explicit streams, as the Wizard harness does: inherited PowerShell 5.1
# console handles can fail inside Framework Console.WriteLine during a run.
$process=Start-Process -FilePath $testExe -ArgumentList ('"'+$OutputDirectory+'"') -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
[void]$process.Handle
try {
    if(-not $process.WaitForExit(60000)) { throw 'App tests timed out; inspect the test process.' }
    if($process.ExitCode -ne 0) { throw 'App tests failed; see app-tests-error.log' }
} finally { $process.Dispose() }
$appOutput=@(Get-Content -LiteralPath $stdout -Encoding UTF8)
$appOutput | Write-Output
$totalLine=@($appOutput | Where-Object { $_ -match '^PASS total=\d+$' })
if($totalLine.Count -ne 1) { throw 'App tests did not produce a count' }
$assertionCount=[int]($totalLine[0] -replace '^PASS total=','')+1
$secure = Get-Content -LiteralPath (Join-Path $OutputDirectory 'cipher.txt') -Raw | ConvertTo-SecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { if([Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) -cne 'New한글42!') { throw 'C# / PowerShell DPAPI interoperability failed' } }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secure.Dispose(); Remove-Item -LiteralPath (Join-Path $OutputDirectory 'cipher.txt') }
Write-Output 'PASS C# / Windows PowerShell DPAPI interoperability'
@{status='PASS';assertions=$assertionCount;dpapi='Windows PowerShell ConvertTo-SecureString';timestamp=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'app-results.json') -Encoding UTF8
