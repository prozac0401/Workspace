#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AppPath, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$AppPath = (Resolve-Path -LiteralPath $AppPath).Path
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot ('..\..\..\artifacts\excel-password-safe\wizard-tests\' + [guid]::NewGuid().ToString('N')) }
[IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($OutputDirectory)) | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$references = @('System.dll','System.Core.dll','System.Web.Extensions.dll') | ForEach-Object { '/reference:' + (Join-Path $framework $_) }
$references += @('WindowsBase.dll','PresentationCore.dll') | ForEach-Object { '/reference:' + (Join-Path $framework ('WPF\'+$_)) }
$testExe = Join-Path $OutputDirectory 'WizardTests.exe'
& (Join-Path $framework 'csc.exe') /nologo /target:exe /warnaserror+ /utf8output "/out:$testExe" "/reference:$AppPath" $references (Join-Path $PSScriptRoot 'WizardTests.cs')
if ($LASTEXITCODE -ne 0) { throw 'Wizard test compilation failed' }
$testApp = Join-Path $OutputDirectory ([IO.Path]::GetFileName($AppPath))
if (-not $AppPath.Equals($testApp,[StringComparison]::OrdinalIgnoreCase)) { Copy-Item -LiteralPath $AppPath -Destination $testApp }
$argument = '"' + $OutputDirectory + $(if ($OutputDirectory.EndsWith('\')) { '\' }) + '"'
$stdout = Join-Path $OutputDirectory 'wizard-tests.log'
$stderr = Join-Path $OutputDirectory 'wizard-tests-error.log'
# Explicit redirection avoids a Windows PowerShell 5.1 inherited-console startup
# failure observed when invoking this Framework test executable with &.
$process = Start-Process -FilePath $testExe -ArgumentList $argument -PassThru -Wait -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Get-Content -LiteralPath $stdout -Encoding UTF8
if ($process.ExitCode -ne 0) { throw 'Wizard rule checks failed; see wizard-results.json and wizard-tests-error.log' }
$recordPath = Join-Path $OutputDirectory 'wizard-results.json'
$record = Get-Content -LiteralPath $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
$record | Add-Member -NotePropertyName assemblyPath -NotePropertyValue $AppPath
$record | Add-Member -NotePropertyName assemblySHA256 -NotePropertyValue ((Get-FileHash -LiteralPath $AppPath -Algorithm SHA256).Hash)
[IO.File]::WriteAllText($recordPath,($record | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
