[CmdletBinding()]
param()
# Local synthetic tests only. Does not execute the lifecycle entry point, Excel,
# an installer, or a registry mutation. Functions are loaded from its AST.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$source=Join-Path $PSScriptRoot 'windows-rc10-lifecycle.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
$wanted=@('Json','Canonical','Same','Assert-NoReparse','File-Hash','File-Metadata','Set-RegistryValue','Write-Tree','Protected-State','Flow-ChildEligible','Flow-ExitObservation','Quote-NativeArgument','Child-SearchPath','Start-LifecycleChild','Run-PowerShellChild','Write-Json','Lifecycle-SuccessStatus','Run-PackageInstall','Run-PackageUninstall','Run-InstalledVerification','Assert-PhysicalPathMatch')
foreach($f in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)) {
    if($f.Name -in $wanted){. ([scriptblock]::Create($f.Extent.Text))}
}
$count=0
function Test([string]$Name,[bool]$Value){if(-not $Value){throw $Name};$script:count++;Write-Host ('PASS '+$Name)}
function Rejects([scriptblock]$Action){try{& $Action;return $false}catch{return $true}}
Test 'Parser accepts lifecycle script' ($errors.Count -eq 0)
Test 'Physical path accepts exact normal location' (-not (Rejects {Assert-PhysicalPathMatch 'C:\Synthetic\file.xlam' 'C:\Synthetic\file.xlam'}))
Test 'Physical path accepts equivalent extended local path' (-not (Rejects {Assert-PhysicalPathMatch 'C:\Synthetic\file.xlam' '\\?\C:\Synthetic\file.xlam'}))
Test 'Physical path accepts equivalent extended UNC path' (-not (Rejects {Assert-PhysicalPathMatch '\\server\share\file.xlam' '\\?\UNC\server\share\file.xlam'}))
Test 'Physical path rejects package-local redirection' (Rejects {Assert-PhysicalPathMatch 'C:\Synthetic\file.xlam' 'C:\Synthetic\PackageCache\file.xlam'})
Test 'Physical path rejects missing observations' (Rejects {Assert-PhysicalPathMatch 'C:\Synthetic\file.xlam' ''})
Test 'Canonical state ignores dictionary insertion order' (Same ([ordered]@{b=2;a=[ordered]@{d=4;c=3}}) ([ordered]@{a=[ordered]@{c=3;d=4};b=2}))
Test 'Empty array differs from null' (-not (Same @() $null))
Test 'Present empty value differs from missing' (-not (Same ([ordered]@{value=''}) ([ordered]@{value=$null})))
Test 'Changed value kind differs' (-not (Same ([ordered]@{kind='String';value='1'}) ([ordered]@{kind='DWord';value=1})))
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$temp=Join-Path $repo ('artifacts\lifecycle-safety-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$file=Join-Path $temp 'known.txt'
[IO.File]::WriteAllText($file,'fixture')
Test 'Missing known file is absent' ($null -eq (File-Hash (Join-Path $temp 'missing.txt')))
Test 'Directory cannot masquerade as absent known file' (Rejects {File-Hash $temp})
Test 'Metadata also rejects a known-file directory' (Rejects {File-Metadata $temp})
Test 'A file in an expected parent directory is rejected' (Rejects {File-Hash (Join-Path $file 'child.txt')})
$before=File-Metadata $file
[IO.File]::SetLastWriteTimeUtc($file,[DateTime]::UtcNow.AddDays(-1))
Test 'Metadata comparison detects an external timestamp edit' (-not (Same $before (File-Metadata $file)))
$script:written=$null
$fake=New-Object PSObject
$fake | Add-Member ScriptMethod SetValue {param($n,$v,$k) $script:written=@($n,$v,[string]$k)}
Set-RegistryValue $fake ([ordered]@{name='sample';kind='DWord';value=1})
Test 'Registry kind conversion retains DWord' ($written[2] -ceq 'DWord' -and $written[1] -is [int])
Set-RegistryValue $fake ([ordered]@{name='sample';kind='Binary';value='AQI='})
Test 'Binary backup decodes into byte array' ($written[1] -is [byte[]] -and $written[1].Length -eq 2)
function Check([string]$Name,[bool]$Pass){if(-not $Pass){throw $Name}}
function Registry-Tree([string]$Path,[string]$Hive='HKCU') {return [ordered]@{exists=$true;values=@([ordered]@{name='External';kind='String';value='preserve'});children=[ordered]@{}}}
$absent=[ordered]@{exists=$false;values=@();children=[ordered]@{}}
Test 'Changed registry tree is rejected before mutation APIs' (Rejects {Write-Tree 'Software\MustNeverBeCreatedByThisTest' $absent $absent})
$excelRoot='Software\Microsoft\Office\16.0\Excel'
$target='C:\Synthetic\ExcelSmartListCompare.xlam'
$openSlots=@('OPEN1')
$trustPaths=@($excelRoot+'\Security\Trusted Locations\Location9')
$script:visited=@()
function Registry-Tree([string]$Path,[string]$Hive='HKCU') {
    $script:visited+=($Hive+'/'+$Path)
    if($Path -eq ($excelRoot+'\Options')) {
        return [ordered]@{exists=$true;values=@([ordered]@{name='OPEN';kind='String';value='Other.xlam'},[ordered]@{name='OPEN1';kind='String';value=$target},[ordered]@{name='MRU';kind='String';value='Changes normally'});children=[ordered]@{}}
    }
    return [ordered]@{exists=$false;values=@();children=[ordered]@{}}
}
$protected=Protected-State
Test 'Protected paths are fourteen separate roots' ($visited.Count -eq 14 -and $visited -contains ('HKCU/'+$excelRoot+'\Options') -and $visited -contains ('HKCU/'+$excelRoot+'\Security'))
$options=$protected['HKCU/'+$excelRoot+'\Options']
Test 'Other OPEN values remain protected' (@($options.values).Count -eq 1 -and $options.values[0].value -ceq 'Other.xlam')
Test 'Normal Excel options are not restoration blockers' (@($options.values | Where-Object name -eq 'MRU').Count -eq 0)
$owner=[pscustomobject]@{pid=123;startTimeUtcTicksText='123456789012345678'}
$flow=[pscustomobject]@{status='PENDING_HOST_RELEASE';failure=$null;cleanupErrors=@();quitSent=$true;normalStartup='PASS';owner=$owner;excelExited=$false;exitConfirmation='PENDING_HOST_RELEASE'}
Test 'Safe pending child is eligible only for separate observation' (Flow-ChildEligible $flow)
$flow.cleanupErrors=@('Actual cleanup failure')
Test 'Actual cleanup failure cannot become pending success' (-not (Flow-ChildEligible $flow))
$flow.cleanupErrors=@();$flow.quitSent=$false
Test 'Pending child without successful Quit is rejected' (-not (Flow-ChildEligible $flow))
$flow.quitSent=$true;$flow.status='FAIL'
Test 'Failure child is never promoted by supervision' (-not (Flow-ChildEligible $flow))
$observed=Flow-ExitObservation $owner @([pscustomobject]@{pid=123;startTimeUtcTicksText='999999999999999999'})
Test 'PID reuse differs from owned identity but still blocks global absence' ($observed.ownedIdentityExited -and $observed.globalExcelCount -eq 1)
$observed=Flow-ExitObservation $owner @($owner)
Test 'A still-running exact owned process is not an exit' (-not $observed.ownedIdentityExited -and $observed.globalExcelCount -eq 1)
$observed=Flow-ExitObservation $owner @()
Test 'Only fresh empty process observations satisfy global absence' ($observed.ownedIdentityExited -and $observed.globalExcelCount -eq 0)
Test 'Native child quoting keeps a space and trailing slash' ((Quote-NativeArgument 'C:\path with spaces\') -ceq '"C:\path with spaces\\"')
Test 'Embedded quote in a child argument is rejected' (Rejects {Quote-NativeArgument 'bad"argument'})
$pathProbe=Child-SearchPath 'C:\Tools;c:\windows\SYSTEM32;C:\Other' 'C:\Windows'
Test 'Child PATH starts with standard Windows locations without duplicates' ($pathProbe.StartsWith('C:\Windows\System32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0;') -and @($pathProbe -split ';' | Where-Object {$_ -ieq 'C:\Windows\System32'}).Count -eq 1 -and $pathProbe.EndsWith('C:\Tools;C:\Other'))
$output=Join-Path $temp 'child process evidence'
[void][IO.Directory]::CreateDirectory($output)
$child=Join-Path $output 'exit probe.ps1'
[IO.File]::Copy((Join-Path $PSScriptRoot 'fixtures\rc10-child-exit.ps1'),$child,$false)
$psExe=Join-Path $PSHOME 'powershell.exe'
if(-not $env:SystemRoot){$env:SystemRoot=[Environment]::GetFolderPath('Windows')}
$pathBefore=$env:PATH
$code=Run-PowerShellChild @('-NoProfile','-File',$child,'-ExitCode','37','-Message','argument with spaces') 'exit37' 30
Test 'Real synthetic child exit 37 remains nonzero' ($code -eq 37)
$processRecord=Get-Content -LiteralPath (Join-Path $output 'exit37.child.private.json') -Raw | ConvertFrom-Json
Test 'Child host record independently captures exit 37' ($processRecord.hostExited -eq $true -and $processRecord.exitCode -eq 37 -and $processRecord.status -ceq 'EXITED_NONZERO')
Test 'Space-containing path and argument reach child intact' ([IO.File]::ReadAllText((Join-Path $output 'exit37.stdout.private.log')).Trim() -ceq 'argument with spaces')
Test 'Child stderr is kept separate from stdout' ([IO.File]::ReadAllText((Join-Path $output 'exit37.stderr.private.log')).Trim() -ceq 'synthetic stderr 37')
Test 'Child launch restores harness PATH immediately' ($env:PATH -ceq $pathBefore)
$originalPathExt=$env:PATHEXT
$env:PATHEXT=$null
try {
    $code=Run-PowerShellChild @('-NoProfile','-File',$child,'-ExitCode','0','-Message','zero child','-ShowPathExt') 'exit0' 30
    Test 'Missing PATHEXT is defaulted only in the child' ([IO.File]::ReadAllText((Join-Path $output 'exit0.stdout.private.log')).Contains('PATHEXT=.COM;.EXE;.BAT;.CMD') -and [string]::IsNullOrEmpty($env:PATHEXT))
} finally {$env:PATHEXT=$originalPathExt}
Test 'Real synthetic child exit zero is recorded' ($code -eq 0 -and (Get-Content -LiteralPath (Join-Path $output 'exit0.child.private.json') -Raw | ConvertFrom-Json).status -ceq 'EXITED_ZERO')
Test 'Engine success has a separate acceptance scope' ((Lifecycle-SuccessStatus 'Engine' $false) -ceq 'INSTALL_ENGINE_STEPS_PASS')
Test 'Engine assisted cleanup remains partial' ((Lifecycle-SuccessStatus 'Engine' $true) -ceq 'INSTALL_ENGINE_STEPS_PARTIAL')
Test 'EXE result scope remains unchanged' ((Lifecycle-SuccessStatus 'EXE' $false) -ceq 'AUTOMATED_STEPS_PASS')
$script:routed=@()
function Run-Engine([string]$Action,[string]$Label){$script:routed+=('Engine/'+$Action+'/'+$Label)}
function Run-Installer([string]$Exe,[string]$Label,[switch]$Uninstall){throw 'An engine-channel test must not invoke the EXE channel.'}
$InstallChannel='Engine'
Run-PackageInstall 'upgrade'
Run-PackageUninstall
Test 'Direct-engine channel never routes to EXE installation/removal' ($routed.Count -eq 2 -and $routed[0] -ceq 'Engine/Install/upgrade' -and $routed[1] -ceq 'Engine/Uninstall/uninstall')
$scopeParameter=@($ast.ParamBlock.Parameters | Where-Object {$_.Name.VariablePath.UserPath -ceq 'VerificationScope'})
Test 'Existing callers retain the Full verification default' ($scopeParameter.Count -eq 1 -and $scopeParameter[0].DefaultValue.Value -ceq 'Full')
$script:flowCalls=@();$script:flowFailure=$false
function Run-Flow([string]$FlowMode,[string]$Label){
    $script:flowCalls+=@([ordered]@{mode=$FlowMode;label=$Label})
    if($script:flowFailure){throw 'Synthetic normal-start/ownership failure'}
}
$VerificationScope='Full';$checks=New-Object Collections.Generic.List[object]
$result=[ordered]@{functionalChecks='NOT_RUN';functionalChecksExecuted=0;functionalChecksSkipped=0;openExcelGuards='NOT_RUN'}
foreach($label in @('upgraded-functional','repaired-functional','clean-functional')){Run-InstalledVerification $label}
Test 'Full scope still runs all three functional checks' ($flowCalls.Count -eq 3 -and @($flowCalls | Where-Object mode -ne 'Functional').Count -eq 0 -and $result.functionalChecksExecuted -eq 3 -and $result.functionalChecksSkipped -eq 0 -and $result.functionalChecks -ceq 'PASS')
$VerificationScope='InstallationOnly';$script:flowCalls=@();$checks=New-Object Collections.Generic.List[object]
$result=[ordered]@{functionalChecks='NOT_RUN';functionalChecksExecuted=0;functionalChecksSkipped=0;openExcelGuards='NOT_RUN'}
foreach($label in @('upgraded-functional','repaired-functional','clean-functional')){Run-InstalledVerification $label}
Test 'InstallationOnly routes all three phases to normal startup with accurate labels' ($flowCalls.Count -eq 3 -and @($flowCalls | Where-Object mode -ne 'NormalStart').Count -eq 0 -and (($flowCalls | ForEach-Object label) -join '|') -ceq 'upgraded-installation-startup|repaired-installation-startup|clean-installation-startup')
Test 'InstallationOnly cannot claim functional or Excel-open guard success' ($result.functionalChecks -ceq 'NOT_RUN' -and $result.functionalChecksExecuted -eq 0 -and $result.functionalChecksSkipped -eq 3 -and $result.openExcelGuards -ceq 'NOT_RUN' -and $checks.Count -eq 3 -and @($checks | Where-Object status -ne 'NOT_RUN').Count -eq 0)
$script:flowFailure=$true
Test 'InstallationOnly still stops on normal-start or ownership failure' (Rejects {Run-InstalledVerification 'upgraded-functional'})
$VerificationScope='Full'
Test 'Full functional failure is propagated and remains FAIL' ((Rejects {Run-InstalledVerification 'upgraded-functional'}) -and $result.functionalChecks -ceq 'FAIL')
# The synthetic path is kept as local evidence. No recursive deletion is needed.
Write-Host ('PASS: '+$count+' synthetic lifecycle safety checks; registry/Excel/installer mutations=0')
