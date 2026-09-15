[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PreviousReleaseDirectory,
    [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
    [Parameter(Mandatory=$true)][string]$PreviousXlamSha256,
    [Parameter(Mandatory=$true)][string]$ExpectedXlamSha256,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
# Run as the ordinary desktop user. Requires an initially absent product and no Excel.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Use a fresh evidence directory.'}
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Existing Excel; no installation changed.'}
$installed=Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare'
if(Test-Path -LiteralPath $installed){throw 'Existing product directory; this lifecycle requires an absent installation.'}
foreach($pair in @(@($PreviousReleaseDirectory,$PreviousXlamSha256),@($ReleaseDirectory,$ExpectedXlamSha256))){if((Get-FileHash (Join-Path $pair[0] 'ExcelSmartListCompare.xlam')).Hash -ine $pair[1]){throw 'Unexpected package hash.'}}
[void](New-Item -ItemType Directory -Path $output)
& (Join-Path $PSScriptRoot 'windows-baseline.ps1') -OutputPath (Join-Path $output 'baseline-before.private.json')
$initial=Get-Content (Join-Path $output 'baseline-before.private.json') -Raw|ConvertFrom-Json
if(-not $initial.sameDesktopAccount -or $initial.elevated){throw 'Use the ordinary desktop account.'}
$checks=[ordered]@{}
$psExe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
$oldNoPause=$env:SLC_SETUP_NO_PAUSE
$env:SLC_SETUP_NO_PAUSE='1'
$created=$false
$extra=Join-Path $installed 'slc-upgrade-synthetic-note.txt'
$extraText='SLC upgrade preservation fixture'
function Check([string]$Name,[bool]$Pass){$checks[$Name]=$Pass;$checks|ConvertTo-Json|Set-Content (Join-Path $output 'checks.json') -Encoding UTF8;if(-not $Pass){throw ('Failed: '+$Name)}}
function Run-Setup([string]$Package,[string]$Action,[string]$LogName){
    Push-Location $Package
    try{
        if($Action -eq 'Install'){& cmd.exe /d /c 'Install.cmd -ConfirmProduct SLC-68A45C44-2026 2>&1'|Out-File (Join-Path $output ($LogName+'.log')) -Encoding UTF8}
        elseif($Action -eq 'Uninstall'){& cmd.exe /d /c 'Uninstall.cmd -ConfirmProduct SLC-68A45C44-2026 2>&1'|Out-File (Join-Path $output ($LogName+'.log')) -Encoding UTF8}
        else{throw 'Unsupported test action'}
        $code=$LASTEXITCODE
    }finally{Pop-Location}
    Check ($LogName+' exit code') ($code -eq 0)
}
try {
    $created=$true
    Run-Setup $PreviousReleaseDirectory 'Install' 'previous-install'
    $previous=Get-Content (Join-Path $installed 'install.json') -Raw|ConvertFrom-Json
    Check 'Previous release installed with expected hash' ($previous.installerVersion -eq '0.2.0-rc.5' -and (Get-FileHash (Join-Path $installed 'ExcelSmartListCompare.xlam')).Hash -ieq $PreviousXlamSha256)
    [IO.File]::WriteAllText($extra,$extraText)
    & (Join-Path $PSScriptRoot 'windows-install-rollback.ps1') -ReleaseDirectory $ReleaseDirectory -OutputDirectory (Join-Path $output 'failed-upgrade')
    $rollback=Get-Content (Join-Path $output 'failed-upgrade/rollback.json') -Raw|ConvertFrom-Json
    Check 'Failed RC5 to RC6 upgrade restores files and registrations' ($rollback.status -eq 'PASS' -and (Get-Content (Join-Path $installed 'install.json') -Raw|ConvertFrom-Json).installerVersion -eq '0.2.0-rc.5')
    $mutex=New-Object Threading.Mutex($false,'Local\ExcelSmartListCompare-Setup')
    $held=$mutex.WaitOne(0)
    try{
        if(-not $held){throw 'Another installer owns the mutex.'}
        $child=Start-Process -FilePath $psExe -ArgumentList @('-NoProfile','-STA','-File',('"'+(Join-Path $ReleaseDirectory 'Setup.ps1')+'"'),'-Action','Install','-ConfirmProduct','SLC-68A45C44-2026') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'concurrent-install.log') -RedirectStandardError (Join-Path $output 'concurrent-install.error.log')
        $null=$child.Handle
        if(-not $child.WaitForExit(30000)){throw 'Concurrent setup check did not finish.'}
        Check 'Concurrent install rejected with code 4 and previous version preserved' ($child.ExitCode -eq 4 -and (Get-FileHash (Join-Path $installed 'ExcelSmartListCompare.xlam')).Hash -ieq $PreviousXlamSha256)
        $child.Dispose()
    }finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
    Run-Setup $ReleaseDirectory 'Install' 'upgrade-install'
    $next=Get-Content (Join-Path $installed 'install.json') -Raw|ConvertFrom-Json
    Check 'RC6 version and exact XLAM installed' ($next.installerVersion -eq '0.2.0-rc.6' -and $next.sha256 -ieq $ExpectedXlamSha256 -and (Get-FileHash (Join-Path $installed 'ExcelSmartListCompare.xlam')).Hash -ieq $ExpectedXlamSha256)
    Check 'Final installer script installed exactly' ((Get-FileHash (Join-Path $installed 'Setup.ps1')).Hash -ceq (Get-FileHash (Join-Path $ReleaseDirectory 'Setup.ps1')).Hash)
    Check 'Upgrade retains product trust token' ($next.trustedLocation.token -ceq $previous.trustedLocation.token)
    Check 'Upgrade preserves additional file' ([IO.File]::ReadAllText($extra) -ceq $extraText)
    Run-Setup $ReleaseDirectory 'Install' 'same-version-reinstall'
    Check 'Same version repair retains exact XLAM' ((Get-FileHash (Join-Path $installed 'ExcelSmartListCompare.xlam')).Hash -ieq $ExpectedXlamSha256)
    & $psExe -NoProfile -STA -File (Join-Path $PSScriptRoot 'windows-window-state.ps1') -SetupPath (Join-Path $ReleaseDirectory 'Setup.ps1') -ExpectedXlamSha256 $ExpectedXlamSha256 -OutputDirectory (Join-Path $output 'window-state') *> (Join-Path $output 'window-state.log')
    Check 'Upgraded normal startup and window-state test exit code' ($LASTEXITCODE -eq 0)
    $window=Get-Content (Join-Path $output 'window-state/window-state.json') -Raw|ConvertFrom-Json
    Check 'Upgraded binary passes all 70 window-state checks' ($window.Count -eq 70 -and @($window|Where-Object status -ne 'PASS').Count -eq 0)
    Run-Setup $ReleaseDirectory 'Uninstall' 'upgraded-uninstall'
    Check 'Uninstall preserves additional file' ((Test-Path -LiteralPath $extra) -and [IO.File]::ReadAllText($extra) -ceq $extraText)
    Check 'Uninstall removes product payload and ownership marker' (-not(Test-Path -LiteralPath (Join-Path $installed 'ExcelSmartListCompare.xlam')) -and -not(Test-Path -LiteralPath (Join-Path $installed 'install.json')))
    Run-Setup $ReleaseDirectory 'Uninstall' 'repeated-uninstall'
}finally{
    if($created -and (Test-Path -LiteralPath (Join-Path $installed 'install.json'))){
        $owner=Get-Content (Join-Path $installed 'install.json') -Raw|ConvertFrom-Json
        if($owner.productId -ne 'SLC-68A45C44-2026' -or $owner.installDirectory -ine $installed){throw 'Unexpected installation marker preserved.'}
        if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Excel still running; installation preserved for inspection.'}
        Run-Setup $ReleaseDirectory 'Uninstall' 'restore-uninstall'
    }
    if(Test-Path -LiteralPath $extra){if([IO.File]::ReadAllText($extra) -cne $extraText){throw 'Changed synthetic fixture preserved.'};Remove-Item -LiteralPath $extra}
    if((Test-Path -LiteralPath $installed) -and @(Get-ChildItem -LiteralPath $installed -Force).Count -eq 0){[IO.Directory]::Delete($installed,$false)}
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Owned Excel has not exited; no settings changed.'}
    $optionPath='HKCU:/Software/Microsoft/Office/16.0/Excel/Options'
    $position=@($initial.registry.$optionPath|Where-Object name -eq 'Pos')
    if($position.Count -eq 1){Set-ItemProperty -LiteralPath $optionPath -Name Pos -Value $position[0].value}
    elseif(Test-Path -LiteralPath $optionPath){Remove-ItemProperty -LiteralPath $optionPath -Name Pos -ErrorAction SilentlyContinue}
    $env:SLC_SETUP_NO_PAUSE=$oldNoPause
    & (Join-Path $PSScriptRoot 'windows-baseline.ps1') -OutputPath (Join-Path $output 'baseline-after.private.json')
    $after=Get-Content (Join-Path $output 'baseline-after.private.json') -Raw|ConvertFrom-Json
    $same=[ordered]@{}
    foreach($p in $initial.registry.PSObject.Properties){$same[$p.Name]=($p.Value|ConvertTo-Json -Depth 12 -Compress) -ceq ($after.registry.($p.Name)|ConvertTo-Json -Depth 12 -Compress)}
    $same|ConvertTo-Json|Set-Content (Join-Path $output 'registry-restoration.json') -Encoding UTF8
    Check 'All 14 Office and policy registry groups restored' (@($same.Values|Where-Object {-not $_}).Count -eq 0)
    Check 'Initial absent installation restored' (-not $after.productDirectoryExists -and @($after.excelProcesses).Count -eq 0)
}
