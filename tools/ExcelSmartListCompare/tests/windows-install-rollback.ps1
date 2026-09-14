[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ReleaseDirectory,[Parameter(Mandatory=$true)][string]$OutputDirectory)
# Inject a file-sharing failure in the owned manifest, after payload copies.
# This test requires an existing installation created by the same E2E run.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Existing Excel; no changes.'}
$installed=Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare'
$manifest=Join-Path $installed 'install.json'
$owner=Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
if($owner.productId -ne 'SLC-68A45C44-2026' -or $owner.installDirectory -ine $installed){throw 'Not an owned product installation.'}
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Use a fresh evidence directory.'}
[void](New-Item -ItemType Directory -Path $output)
$package=Join-Path $output 'rollback-package'
[void](New-Item -ItemType Directory -Path $package)
foreach($name in @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','Install.cmd','README.md')) {
    Copy-Item -LiteralPath (Join-Path $ReleaseDirectory $name) -Destination (Join-Path $package $name)
}
Add-Content -LiteralPath (Join-Path $package 'README.md') -Value 'Synthetic rollback test sentinel.' -Encoding UTF8
function Snapshot {
    $files=[ordered]@{}
    foreach($name in @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md','install.json')){$files[$name]=(Get-FileHash -LiteralPath (Join-Path $installed $name)).Hash}
    $options=Get-Item -LiteralPath ('HKCU:/Software/Microsoft/Office/'+$owner.excelVersion+'/Excel/Options')
    $entries=[ordered]@{}
    foreach($name in @($options.GetValueNames() | Where-Object {$_ -match '^OPEN\d*$'} | Sort-Object)){$entries[$name]=[string]$options.GetValue($name)}
    $trustPath='HKCU:/Software/Microsoft/Office/'+$owner.excelVersion+'/Excel/Security/Trusted Locations'
    $trust=@()
    if(Test-Path -LiteralPath $trustPath){foreach($key in @((Get-Item -LiteralPath $trustPath))+@(Get-ChildItem -LiteralPath $trustPath -Recurse | Sort-Object Name)){foreach($name in @($key.GetValueNames() | Sort-Object)){$trust+=($key.Name+'|'+$name+'|'+$key.GetValueKind($name)+'|'+$key.GetValue($name))}}}
    return [ordered]@{files=$files;openValues=$entries;trustedLocations=$trust}
}
$before=Snapshot
$stream=[IO.File]::Open($manifest,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
$oldNoPause=$env:SLC_SETUP_NO_PAUSE
try {
    $env:SLC_SETUP_NO_PAUSE='1'
    Push-Location $package
    try { & cmd.exe /d /c 'Install.cmd -ConfirmProduct SLC-68A45C44-2026 2>&1' | Out-File -LiteralPath (Join-Path $output 'install.log') -Encoding UTF8; $code=$LASTEXITCODE }
    finally { Pop-Location }
} finally { $stream.Dispose(); $env:SLC_SETUP_NO_PAUSE=$oldNoPause }
$after=Snapshot
$same=($before | ConvertTo-Json -Depth 6 -Compress) -ceq ($after | ConvertTo-Json -Depth 6 -Compress)
$leftovers=@(Get-ChildItem -LiteralPath $installed -Filter 'slc-install-*.json')
$pass=$code -eq 1 -and $same -and $leftovers.Count -eq 0 -and @(Get-Process EXCEL -ErrorAction SilentlyContinue).Count -eq 0
[ordered]@{status=if($pass){'PASS'}else{'FAIL'};injectedFailure='Owned manifest held open without delete sharing';expectedExit=1;actualExit=$code;payloadAndManifestHashesRestored=$same;registrationPreserved=$same;temporaryManifestCount=$leftovers.Count;before=$before;after=$after} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $output 'rollback.json') -Encoding UTF8
if(-not $pass){exit 1}
