[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ReleaseDirectory,[Parameter(Mandatory=$true)][string]$OutputDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Existing Excel; no changes.'}
$installed=Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare'
$manifest=Get-Content -LiteralPath (Join-Path $installed 'install.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if($manifest.productId -ne 'SLC-68A45C44-2026' -or $manifest.installDirectory -ine $installed){throw 'Not the owned test installation.'}
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Use a new evidence directory.'}
[void](New-Item -ItemType Directory -Path $output)
$extra=Join-Path $installed 'e2e-preserve-extra.txt'
if(Test-Path -LiteralPath $extra){throw 'Existing extra file preserved; test cancelled.'}
[IO.File]::WriteAllText($extra,'Synthetic extra file; not owned by the installer.')
$hash=(Get-FileHash -LiteralPath $extra).Hash
$env:SLC_SETUP_NO_PAUSE='1'
Push-Location $ReleaseDirectory
try { & cmd.exe /d /c 'Uninstall.cmd -ConfirmProduct SLC-68A45C44-2026 2>&1' | Out-File -LiteralPath (Join-Path $output 'uninstall.log') -Encoding UTF8; $code=$LASTEXITCODE }
finally { Pop-Location }
$extraPreserved=(Test-Path -LiteralPath $extra) -and (Get-FileHash -LiteralPath $extra).Hash -eq $hash
$ownedRemaining=@('ExcelSmartListCompare.xlam','README.md','Setup.ps1','Uninstall.cmd','install.json') | Where-Object {Test-Path -LiteralPath (Join-Path $installed $_)}
$target=Join-Path $installed 'ExcelSmartListCompare.xlam'
$options=Get-Item -LiteralPath ('HKCU:/Software/Microsoft/Office/'+$manifest.excelVersion+'/Excel/Options')
$ownEntries=@($options.GetValueNames() | Where-Object {$_ -match '^OPEN\d*$' -and ([string]$options.GetValue($_)).Trim('"') -ieq $target})
$pass=$code -eq 0 -and $extraPreserved -and @($ownedRemaining).Count -eq 0 -and $ownEntries.Count -eq 0
# Remove only this test's exact unchanged sentinel; preserve anything else.
if($extraPreserved){Remove-Item -LiteralPath $extra}
if((Test-Path -LiteralPath $installed) -and @(Get-ChildItem -LiteralPath $installed -Force).Count -eq 0){Remove-Item -LiteralPath $installed}
[ordered]@{status=if($pass){'PASS'}else{'FAIL'};actualExit=$code;extraFilePreserved=$extraPreserved;ownedFilesRemaining=@($ownedRemaining);ownOpenValuesRemaining=$ownEntries;testExtraCleaned=$extraPreserved;installedDirectoryAbsent=(-not(Test-Path -LiteralPath $installed))} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $output 'removal.json') -Encoding UTF8
if(-not $pass){exit 1}
