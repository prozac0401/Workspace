[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$InstallerPath,
    [Parameter(Mandatory=$true)][string]$ReleaseDirectory,
    [Parameter(Mandatory=$true)][string]$PreviousReleaseDirectory,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$IncludeExcelSmoke,
    [string]$ExpectedInstallerVersion='0.2.0-rc.8',
    [string]$PreviousInstallerVersion='0.2.0-rc.7'
)
# Actual EXE lifecycle, only when the current user has no product or Excel open.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
if(-not $output.StartsWith(($repo+'\artifacts\'),[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Use a fresh repository artifacts directory.'}
$installer=[IO.Path]::GetFullPath($InstallerPath)
$release=[IO.Path]::GetFullPath($ReleaseDirectory)
$previous=[IO.Path]::GetFullPath($PreviousReleaseDirectory)
$product=Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare'
$manager=Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare.Setup'
$appKey='HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/ExcelSmartListCompare.OneFile_is1'
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count -or (Test-Path -LiteralPath $product) -or (Test-Path -LiteralPath $manager) -or (Test-Path -LiteralPath $appKey)){throw 'Existing Excel or installation; no state changed.'}
[void](New-Item -ItemType Directory -Path $output)
$checks=New-Object 'Collections.Generic.List[object]'
$manifest=Join-Path $product 'install.json'
$noPause=$env:SLC_SETUP_NO_PAUSE
$env:SLC_SETUP_NO_PAUSE='1'
$psExe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
$created=$false
$fixtureText='SLC one-file synthetic preservation fixture'
$productNote=Join-Path $product 'onefile-synthetic-note.txt'
$managerNote=Join-Path $manager 'onefile-synthetic-note.txt'
function Check([string]$Name,[bool]$Pass){
    $checks.Add([pscustomobject]@{name=$Name;status=$(if($Pass){'PASS'}else{'FAIL'})})
    $checks.ToArray()|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $output 'checks.json') -Encoding UTF8
    Write-Host (($checks.Count).ToString()+' '+$(if($Pass){'PASS '}else{'FAIL '})+$Name)
    if(-not $Pass){throw ('Failed: '+$Name)}
}
function Run-Exe([string]$Exe,[string]$Label,[string]$Extra='',[string]$TempDirectory=''){
    $log=Join-Path $output ($Label+'.private.log')
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$Exe
    $info.Arguments='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /LOG="'+$log+'" '+$Extra
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    if($TempDirectory){
        # Exercise the installer's extraction environment without changing the
        # long-running test host's own CLR/PowerShell temporary directory.
        $info.EnvironmentVariables['TEMP']=$TempDirectory
        $info.EnvironmentVariables['TMP']=$TempDirectory
    }
    $process=[Diagnostics.Process]::Start($info)
    try{
        if(-not $process.WaitForExit(60000)){throw ('Owned setup timed out; inspect '+$Label+' PID '+$process.Id)}
        $code=$process.ExitCode
        if([IO.Path]::GetFileName($Exe) -like 'unins*.exe'){
            # Inno's original remover can exit while its temporary second phase
            # is still removing its own executable and directory.
            $timer=[Diagnostics.Stopwatch]::StartNew()
            do{
                $content=''
                if(Test-Path -LiteralPath $log){
                    $stream=[IO.File]::Open($log,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
                    $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true)
                    try{$content=$reader.ReadToEnd()}finally{$reader.Dispose()}
                }
                if($content -match 'Log closed\.'){break}
                Start-Sleep -Milliseconds 150
            }while($timer.Elapsed.TotalSeconds -lt 30)
            if($content -notmatch 'Log closed\.'){throw ('Uninstall completion log missing: '+$Label)}
            if($code -eq 0 -and $content -notmatch 'Uninstallation process succeeded\.'){return 1}
        }
        return $code
    }finally{$process.Dispose()}
}
function Run-Cmd([string]$Directory,[string]$Action){
    if($Action -notin @('Install','Uninstall')){throw 'Unknown launcher action.'}
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$env:ComSpec
    $info.Arguments='/d /v:off /c '+$Action+'.cmd -ConfirmProduct SLC-68A45C44-2026'
    $info.WorkingDirectory=$Directory
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $process=[Diagnostics.Process]::Start($info)
    try{
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(60000)){throw ('Owned launcher timed out; inspect PID '+$process.Id)}
        [IO.File]::WriteAllText((Join-Path $output ($Action+'-cmd.private.log')),($stdout.Result+$stderr.Result),[Text.Encoding]::UTF8)
        if($process.ExitCode){throw ('Original launcher failed: '+$process.ExitCode)}
    }finally{$process.Dispose()}
}
function Assert-Payload{
    foreach($name in @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md')){
        Check ('Installed exact requested bytes: '+$name) ((Get-FileHash -LiteralPath (Join-Path $product $name)).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $release $name)).Hash)
    }
    Check 'Requested ownership schema and version retained' ((Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json).installerVersion -eq $ExpectedInstallerVersion)
    Check 'Windows Apps entry and remover registered' ((Test-Path -LiteralPath $appKey) -and (Test-Path -LiteralPath (Join-Path $manager 'unins000.exe')))
}
function Remove-Synthetic([string]$Path){
    if(Test-Path -LiteralPath $Path){
        if([IO.File]::ReadAllText($Path) -cne $fixtureText){throw 'Changed synthetic note preserved.'}
        Remove-Item -LiteralPath $Path
    }
}
function Remove-Empty([string]$Path){
    if((Test-Path -LiteralPath $Path) -and @(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0){[IO.Directory]::Delete($Path,$false)}
}
& (Join-Path $PSScriptRoot 'windows-baseline.ps1') -OutputPath (Join-Path $output 'before.private.json') | Out-Null
$initial=Get-Content -LiteralPath (Join-Path $output 'before.private.json') -Raw|ConvertFrom-Json
if(-not $initial.sameDesktopAccount -or $initial.elevated){throw 'Use the ordinary desktop account.'}
try{
    Check 'Alternate manager path rejected before engine starts' ((Run-Exe $installer 'alternate-path' ('/DIR="'+(Join-Path $output 'wrong-dir')+'"')) -ne 0 -and -not(Test-Path -LiteralPath $product) -and -not(Test-Path -LiteralPath $manager))
    foreach($lockName in @('Local\ExcelSmartListCompare.OneFile','Local\ExcelSmartListCompare-Setup')){
        $mutex=New-Object Threading.Mutex($true,$lockName)
        try{
            $label=if($lockName.EndsWith('OneFile')){'wrapper-lock'}else{'engine-lock'}
            Check ($label+' rejects concurrent installation') ((Run-Exe $installer $label) -ne 0 -and -not(Test-Path -LiteralPath $product) -and -not(Test-Path -LiteralPath $manager))
            if($label -eq 'engine-lock'){Check 'Original engine failure code 4 propagated to installer log' ([IO.File]::ReadAllText((Join-Path $output ($label+'.private.log'))) -match 'SLC_ENGINE_EXIT_CODE=4')}
        }finally{$mutex.ReleaseMutex();$mutex.Dispose()}
    }
    [void](New-Item -ItemType Directory -Path $manager)
    [IO.File]::WriteAllText($managerNote,$fixtureText)
    try{Check 'Unknown manager directory preserved' ((Run-Exe $installer 'foreign-manager') -ne 0 -and [IO.File]::ReadAllText($managerNote) -ceq $fixtureText -and -not(Test-Path -LiteralPath $product))}
    finally{Remove-Synthetic $managerNote;Remove-Empty $manager}

    $created=$true
    Check 'Fresh EXE installation succeeds' ((Run-Exe $installer 'fresh-install') -eq 0)
    Check 'Korean engine output preserved in local log' ([IO.File]::ReadAllText((Join-Path $output 'fresh-install.private.log')) -match '설치했습니다\.')
    Assert-Payload
    $mutex=New-Object Threading.Mutex($true,'Local\ExcelSmartListCompare-Setup')
    try{
        Check 'Failed engine uninstall preserves installed product and Apps entry' ((Run-Exe (Join-Path $manager 'unins000.exe') 'blocked-uninstall') -ne 0 -and (Test-Path -LiteralPath $manifest) -and (Test-Path -LiteralPath $appKey))
    }finally{$mutex.ReleaseMutex();$mutex.Dispose()}
    Check 'Windows registered remover succeeds' ((Run-Exe (Join-Path $manager 'unins000.exe') 'fresh-uninstall') -eq 0)
    Check 'Fresh removal leaves no product, manager, or Apps entry' (-not(Test-Path -LiteralPath $product) -and -not(Test-Path -LiteralPath $manager) -and -not(Test-Path -LiteralPath $appKey))

    Run-Cmd $previous 'Install'
    $old=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
    Check 'Previous version installed for actual upgrade test' ($old.installerVersion -eq $PreviousInstallerVersion)
    [IO.File]::WriteAllText($productNote,$fixtureText)
    $beforeFiles=@{}
    foreach($name in @('ExcelSmartListCompare.xlam','Setup.ps1','Uninstall.cmd','README.md','install.json')){$beforeFiles[$name]=(Get-FileHash -LiteralPath (Join-Path $product $name)).Hash}
    & (Join-Path $PSScriptRoot 'windows-baseline.ps1') -OutputPath (Join-Path $output 'upgrade-before.private.json') | Out-Null
    $locked=[IO.File]::Open($manifest,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{Check 'EXE reports injected upgrade write failure' ((Run-Exe $installer 'failed-upgrade') -ne 0)}finally{$locked.Dispose()}
    foreach($name in $beforeFiles.Keys){Check ('Upgrade rollback restores '+$name) ((Get-FileHash -LiteralPath (Join-Path $product $name)).Hash -ceq $beforeFiles[$name])}
    & (Join-Path $PSScriptRoot 'windows-baseline.ps1') -OutputPath (Join-Path $output 'upgrade-after.private.json') | Out-Null
    $upgradeBefore=Get-Content -LiteralPath (Join-Path $output 'upgrade-before.private.json') -Raw|ConvertFrom-Json
    $upgradeAfter=Get-Content -LiteralPath (Join-Path $output 'upgrade-after.private.json') -Raw|ConvertFrom-Json
    Check 'Failed upgrade restores all Office and policy registrations' (($upgradeBefore.registry|ConvertTo-Json -Depth 15 -Compress) -ceq ($upgradeAfter.registry|ConvertTo-Json -Depth 15 -Compress))
    Check 'Failed upgrade creates no manager or Apps entry' (-not(Test-Path -LiteralPath $manager) -and -not(Test-Path -LiteralPath $appKey))
    Check 'EXE upgrades previous version to requested version' ((Run-Exe $installer 'upgrade') -eq 0)
    Assert-Payload
    Check 'Upgrade retains original trust ownership token' ((Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json).trustedLocation.token -ceq $old.trustedLocation.token)
    Check 'Same EXE repairs installed version successfully' ((Run-Exe $installer 'repair') -eq 0)
    Check 'Repair retains trust ownership token' ((Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json).trustedLocation.token -ceq $old.trustedLocation.token)
    [IO.File]::WriteAllText($managerNote,$fixtureText)

    # Only the owned engine copy is omitted to exercise the packaged recovery path.
    $saved=Join-Path $output 'installed-Setup.saved.ps1'
    [IO.File]::Move((Join-Path $product 'Setup.ps1'),$saved)
    Check 'Registered remover recovers a missing installed Setup.ps1' ((Run-Exe (Join-Path $manager 'unins000.exe') 'fallback-uninstall') -eq 0)
    Check 'Core and manager extra files survive removal' ([IO.File]::ReadAllText($productNote) -ceq $fixtureText -and [IO.File]::ReadAllText($managerNote) -ceq $fixtureText)
    Check 'Removal clears owned manifest and Apps entry' (-not(Test-Path -LiteralPath $manifest) -and -not(Test-Path -LiteralPath $appKey))
    Remove-Synthetic $productNote;Remove-Empty $product
    Remove-Synthetic $managerNote;Remove-Empty $manager

    # Unicode, spaces and CMD metacharacters in both download and extraction paths.
    $special=Join-Path $output '한글 경로 & ! (100%)'
    [void](New-Item -ItemType Directory -Path $special)
    $specialExe=Join-Path $special ([IO.Path]::GetFileName($installer))
    [IO.File]::Copy($installer,$specialExe)
    Check 'EXE installs from Unicode and shell-metacharacter extraction path' ((Run-Exe $specialExe 'special-path' -TempDirectory $special) -eq 0)
    Check 'Installed engine hash retained after special-path installation' ((Get-FileHash -LiteralPath (Join-Path $product 'Setup.ps1')).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $release 'Setup.ps1')).Hash)
    if($IncludeExcelSmoke){
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $release 'Setup.ps1'),[ref]$null,[ref]$null)
        foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){. ([scriptblock]::Create($f.Extent.Text))}
        $Root=$release
        $script:Excel=$null;$script:ExcelVersion=$null;$script:ExcelProcess=$null;$script:ExcelBootstrap=$null;$script:ExcelSessionBook=$null
        try{
            Start-OwnExcel -NormalStart
            $ownedExcelId=$script:ExcelProcess.Id
            Check 'Running Excel blocks EXE installation without closing Excel' ((Run-Exe $installer 'excel-running-install') -ne 0 -and $null -ne (Get-Process -Id $ownedExcelId -ErrorAction SilentlyContinue))
            Check 'Original engine Excel guard returns code 3' ([IO.File]::ReadAllText((Join-Path $output 'excel-running-install.private.log')) -match 'SLC_ENGINE_EXIT_CODE=3')
            Check 'Running Excel blocks registered removal and preserves Apps entry' ((Run-Exe (Join-Path $manager 'unins000.exe') 'excel-running-uninstall') -ne 0 -and (Test-Path -LiteralPath $manifest) -and (Test-Path -LiteralPath $appKey))
        }finally{Stop-OwnExcel}
        $expectedHash=(Get-FileHash -LiteralPath (Join-Path $release 'ExcelSmartListCompare.xlam')).Hash
        & $psExe -NoProfile -STA -File (Join-Path $PSScriptRoot 'windows-context-menu-content.ps1') -SetupPath (Join-Path $release 'Setup.ps1') -ExpectedXlamSha256 $expectedHash -ExpectedReleaseVersion $ExpectedInstallerVersion -OutputDirectory (Join-Path $output 'excel-smoke') *> (Join-Path $output 'excel-smoke.private.log')
        Check 'Installed XLAM normal-start and comparison smoke succeeds' ($LASTEXITCODE -eq 0)
        $smoke=Get-Content -LiteralPath (Join-Path $output 'excel-smoke/context-menu-content.json') -Raw|ConvertFrom-Json
        Check 'All 164 original context-content and comparison assertions pass' ($smoke.Count -eq 164 -and @($smoke|Where-Object status -ne 'PASS').Count -eq 0)
    }
    Run-Cmd $product 'Uninstall'
    Check 'Installed CMD self-removal succeeds with exact exit code' (-not(Test-Path -LiteralPath $product) -and (Test-Path -LiteralPath $appKey))
    Check 'Apps remover cleans up after original CMD removal' ((Run-Exe (Join-Path $manager 'unins000.exe') 'already-removed') -eq 0 -and -not(Test-Path -LiteralPath $manager) -and -not(Test-Path -LiteralPath $appKey))
}catch{
    $_|Out-File -LiteralPath (Join-Path $output 'primary-error.private.log') -Encoding UTF8
    throw
}finally{
    if($created -and (Test-Path -LiteralPath $manifest)){
        $owner=Get-Content -LiteralPath $manifest -Raw|ConvertFrom-Json
        if($owner.productId -ne 'SLC-68A45C44-2026' -or $owner.installDirectory -ine $product){throw 'Unexpected product preserved for inspection.'}
        if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Excel opened during testing; product preserved for inspection.'}
        Run-Cmd $release 'Uninstall'
    }
    if($created -and (Test-Path -LiteralPath (Join-Path $manager 'unins000.exe'))){
        if((Run-Exe (Join-Path $manager 'unins000.exe') 'cleanup-remover') -ne 0){throw 'Manager cleanup failed; preserved for inspection.'}
    }
    Remove-Synthetic $productNote;Remove-Empty $product
    Remove-Synthetic $managerNote;Remove-Empty $manager
    $env:SLC_SETUP_NO_PAUSE=$noPause
    if($IncludeExcelSmoke){
        if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Excel still open; preserve settings for inspection.'}
        # Excel changes only its window-position value during this owned smoke.
        $optionPath='HKCU:/Software/Microsoft/Office/16.0/Excel/Options'
        $position=@($initial.registry.$optionPath|Where-Object name -eq 'Pos')
        if($position.Count -eq 1){Set-ItemProperty -LiteralPath $optionPath -Name Pos -Value $position[0].value}
        elseif(Test-Path -LiteralPath $optionPath){Remove-ItemProperty -LiteralPath $optionPath -Name Pos -ErrorAction SilentlyContinue}
    }
    & (Join-Path $PSScriptRoot 'windows-baseline.ps1') -OutputPath (Join-Path $output 'after.private.json') | Out-Null
    $after=Get-Content -LiteralPath (Join-Path $output 'after.private.json') -Raw|ConvertFrom-Json
    Check 'All 14 Office and policy groups restored' (($initial.registry|ConvertTo-Json -Depth 15 -Compress) -ceq ($after.registry|ConvertTo-Json -Depth 15 -Compress))
    Check 'Initial absent installation and process state restored' (-not $after.productDirectoryExists -and @($after.excelProcesses).Count -eq 0 -and -not(Test-Path -LiteralPath $manager) -and -not(Test-Path -LiteralPath $appKey))
}
