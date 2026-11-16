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
& $testExe $OutputDirectory
if($LASTEXITCODE -ne 0) { throw 'App tests failed' }
$secure = Get-Content -LiteralPath (Join-Path $OutputDirectory 'cipher.txt') -Raw | ConvertTo-SecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { if([Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) -cne 'New한글42!') { throw 'C# / PowerShell DPAPI interoperability failed' } }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secure.Dispose(); Remove-Item -LiteralPath (Join-Path $OutputDirectory 'cipher.txt') }
Write-Output 'PASS C# / Windows PowerShell DPAPI interoperability'
@{status='PASS';assertions=31;dpapi='Windows PowerShell ConvertTo-SecureString';timestamp=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'app-results.json') -Encoding UTF8
