[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-fA-F0-9]{64}$')][string]$ExpectedXlamSha256,
    [Parameter(Mandatory=$true)][string]$SourceDirectory,
    [string]$ExpectedReleaseVersion='0.2.0-rc.9',
    [switch]$ApprovedTemporaryVbaAccess
)
# Run this host through Invoke-BoundedTest.ps1. The supervisor bounds blocking
# Excel COM calls and never kills Excel. If it stops this host, finally cannot
# run: recover using access-before.private.json AFTER the exact owned Excel exits.
# This developer-only test opens the installed hash, temporarily instruments VBA
# in memory, restores the module, and closes without saving. It is not native
# Esc/UI proof, an auto-load test, or an installation test.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Use Windows PowerShell 5.1 via Invoke-BoundedTest.ps1.'}
function Get-SharedReadSha256([string]$Path){
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant()}
    finally{$stream.Dispose()}
}
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$artifacts=[IO.Path]::GetFullPath((Join-Path $repo 'artifacts')).TrimEnd('\')+'\'
$output=[IO.Path]::GetFullPath($OutputDirectory)
$source=[IO.Path]::GetFullPath($SourceDirectory)
foreach($path in @($output,$source)){
    if(-not $path.StartsWith($artifacts,[StringComparison]::OrdinalIgnoreCase)){throw 'Evidence and candidate source snapshot must be below repository artifacts.'}
    $ancestor=$path
    while($ancestor){
        if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Test paths cannot traverse reparse points.'}
        $ancestor=Split-Path -Parent $ancestor
    }
}
if(Test-Path -LiteralPath $output){throw 'Existing evidence is preserved; choose a fresh OutputDirectory.'}
$mainSource=Join-Path $source 'modSLCMain.bas'
if(-not (Test-Path -LiteralPath $mainSource -PathType Leaf)){throw 'Final candidate main-module source snapshot is missing.'}
if(@([IO.File]::ReadAllBytes($mainSource)|Where-Object{$_ -gt 127}).Count){throw 'Expected the final candidate ASCII import source.'}
$installed=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare/ExcelSmartListCompare.xlam'))
if(-not (Test-Path -LiteralPath $installed -PathType Leaf)){throw 'The product must already be installed.'}
if((Get-SharedReadSha256 $installed) -ine $ExpectedXlamSha256){throw 'Installed XLAM does not match the requested final candidate.'}
[void][IO.Directory]::CreateDirectory($output)
$utf8=New-Object Text.UTF8Encoding($false)
$builder=Join-Path $PSScriptRoot 'Build-ExcelCandidate.ps1'
$statusProbe=Join-Path $PSScriptRoot 'windows-status-checkpoint.ps1'
$transactionProbe=Join-Path $PSScriptRoot 'windows-cancellation-transaction.ps1'
$transactionCases=@('replacement-tail','comparison-tail','output-tail','staged-status-error',
    'api-unavailable-replacement','api-unavailable-comparison','api-interruption-replacement','api-interruption-comparison','geometry-normalization')
# Import only these reviewed function definitions, never the builder body.
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($builder,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Candidate policy/comparison helpers failed parsing.'}
foreach($name in @('Candidate-Failure','Read-AccessValue','Same-AccessValue','Assert-VbaPolicy','Normalize-Vba')){
    $definitions=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$false))
    if($definitions.Count -ne 1){throw ('Expected exactly one builder helper: '+$name)}
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}
$audit=[ordered]@{
    schemaVersion=1;status='NOT_RUN';phase='preflight';startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null
    primaryFailure=$null;failureStack=$null;cleanupErrors=@();owner=$null;excelExited=$null;quitAttempted=$false
    installedPath=$installed;diskSha256Before=$ExpectedXlamSha256.ToLowerInvariant();diskSha256After=$null;diskUnchanged=$false
    sourcePath=$mainSource;sourceSha256=(Get-FileHash -LiteralPath $mainSource).Hash.ToLowerInvariant();sourceUnchanged=$null
    expectedReleaseVersion=$ExpectedReleaseVersion;actualReleaseVersion=$null;probeReports=@();moduleAudits=@();settingsRestored=$null
    settingsBefore=$null;settingsAfterStatusProbe=$null;settingsAfterProbes=$null;cleanupSettingsRestored=$null
    settingsBeforeHostCleanup=$null;settingsAfterHostCleanup=$null;settingsComparisons=@()
    approvedTemporaryVbaAccess=[bool]$ApprovedTemporaryVbaAccess;officeVersion=$null;accessBefore=$null;accessAfter=$null;accessRestored=$null
    temporaryAccessWriteAttempted=$false;temporaryAccessWritten=$false;externalSecurityChangeDetected=$false;ownedExcelExitedBeforeAccessRestore=$null;requiresPostExitSecurityRecheck=$false
    preservedUnexpectedWorkbooks=@();observedExcelAtEnd=@();helperHashes=@();nativeEscVerified=$false
    testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()
    transactionCaseIds=$transactionCases;apiPolicyBlockReproduced=$false
    scope='Memory-only status/checkpoint plus nine deterministic cancellation/rollback/API-error/geometry cases; no policy-block or native Esc reproduction.'
}
foreach($path in @($PSCommandPath,$builder,$statusProbe,$transactionProbe)){$audit.helperHashes+=@([ordered]@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()})}
$reportPath=Join-Path $output 'fault-probes.private.json'
function Save-Audit {
    $temporary=$reportPath+'.writing'
    [IO.File]::WriteAllText($temporary,($audit|ConvertTo-Json -Depth 15),$utf8)
    if(Test-Path -LiteralPath $reportPath){[IO.File]::Replace($temporary,$reportPath,[NullString]::Value)}else{[IO.File]::Move($temporary,$reportPath)}
}
function Release-FaultCom($Value){
    if($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)){
        try{[void][Runtime.InteropServices.Marshal]::ReleaseComObject($Value)}
        catch{$script:audit.cleanupErrors+=@('COM release failed: '+$_.Exception.Message)}
    }
}
function Text-Hash([string]$Text){
    $hash=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant()}
    finally{$hash.Dispose()}
}
function Assert-Owner {
    if($null -eq $audit.owner -or $null -eq $script:excel){throw 'Owned Excel identity unavailable.'}
    $process=Get-Process -Id $audit.owner.pid -ErrorAction Stop
    try{if($process.ProcessName -ine 'EXCEL' -or $process.StartTime.ToUniversalTime().Ticks -ne $audit.owner.startTicks){throw 'Owned Excel identity changed.'}}
    finally{$process.Dispose()}
    [uint32]$pidValue=0
    [void][SlcFaultOwner]::GetWindowThreadProcessId([IntPtr][long]$script:excel.Hwnd,[ref]$pidValue)
    if($pidValue -ne $audit.owner.pid){throw 'COM application no longer matches owned Excel.'}
}
function Read-MainModule {
    Assert-Owner
    $books=$null;$book=$null;$project=$null;$components=$null;$component=$null;$module=$null
    try{
        $books=$script:excel.Workbooks;$book=$books.Item('ExcelSmartListCompare.xlam')
        if([IO.Path]::GetFullPath([string]$book.FullName) -ine $installed -or -not [bool]$book.IsAddin){throw 'Loaded add-in identity differs from installed test subject.'}
        $project=$book.GetType().InvokeMember('VBProject',[Reflection.BindingFlags]::GetProperty,$null,$book,$null)
        $components=$project.VBComponents;$component=$components.Item('modSLCMain');$module=$component.CodeModule
        return [string]$module.Lines(1,$module.CountOfLines)
    }finally{foreach($value in @($module,$component,$components,$project,$book,$books)){Release-FaultCom $value}}
}
function Check-MainModule([string]$Phase,[string]$Expected){
    $actual=Read-MainModule;$left=Normalize-Vba $Expected;$right=Normalize-Vba $actual
    $pass=$left -ceq $right
    $audit.moduleAudits+=@([ordered]@{phase=$Phase;status=$(if($pass){'PASS'}else{'FAIL'});expectedNormalizedSha256=(Text-Hash $left);actualNormalizedSha256=(Text-Hash $right);actualRawSha256=(Text-Hash $actual)})
    Save-Audit
    if(-not $pass){throw ('In-memory source comparison failed: '+$Phase)}
    return $actual
}
function Read-Settings {
    Assert-Owner
    return [ordered]@{screenUpdating=[bool]$script:excel.ScreenUpdating;enableEvents=[bool]$script:excel.EnableEvents;interactive=[bool]$script:excel.Interactive;enableCancelKey=[int]$script:excel.EnableCancelKey;calculation=[int]$script:excel.Calculation;statusBar=$script:excel.StatusBar}
}
function Compare-FaultSettings($Expected,$Actual){
    # Compare each scalar and its type, independent of dictionary enumeration or
    # JSON property order. In particular Boolean false is not the text "False".
    $records=@();$passed=$true
    foreach($name in @('screenUpdating','enableEvents','interactive','enableCancelKey','calculation','statusBar')){
        $wanted=$Expected[$name];$observed=$Actual[$name]
        $wantedType=if($null -eq $wanted){$null}else{$wanted.GetType().FullName}
        $observedType=if($null -eq $observed){$null}else{$observed.GetType().FullName}
        $same=$wantedType -ceq $observedType -and
            (ConvertTo-Json -InputObject $wanted -Compress) -ceq (ConvertTo-Json -InputObject $observed -Compress)
        if(-not $same){$passed=$false}
        $records+=@([ordered]@{name=$name;expected=$wanted;actual=$observed;expectedType=$wantedType;actualType=$observedType;status=$(if($same){'PASS'}else{'FAIL'})})
    }
    return [ordered]@{passed=$passed;fields=$records}
}
function Restore-FaultStatus($Application,$Value){
    # Supply an explicitly boxed Boolean rather than relying on assignment
    # binding. This is a restoration attempt, not proof that Excel restored the
    # raw property type; Compare-FaultSettings remains authoritative afterward.
    $argument=if($Value -is [bool]){[bool]$false}else{$Value}
    $arguments=New-Object object[] 1;$arguments[0]=$argument
    [void]$Application.GetType().InvokeMember('StatusBar',[Reflection.BindingFlags]::SetProperty,$null,$Application,$arguments)
}
$script:excel=$null;$mutex=$null;$locked=$false;$securityPath=$null;$snapshotTaken=$false;$securityWritten=$false
$hostPath=Join-Path $output 'Synthetic-probe-host.xlsx'
$hostCreated=$false;$hostHash=$null;$settings=$null;$initialMain=$null;$exitCode=1
try{
    Save-Audit
    $mutex=New-Object Threading.Mutex($false,'Local\ExcelSmartListCompare-Setup')
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw (Candidate-Failure 'Another product setup/build/probe is running.' 'BLOCKED_ENV' 4)}
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw (Candidate-Failure 'Existing Excel prevents this isolated probe; nothing was changed.' 'BLOCKED_ENV' 3)}
    $key=[Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey('Excel.Application\CurVer')
    try{$progId=if($null -ne $key){[string]$key.GetValue('')}else{''}}finally{if($null -ne $key){$key.Close()}}
    if($progId -notmatch '^Excel\.Application\.(\d+)$'){throw 'Registered Excel version unavailable.'}
    $audit.officeVersion=$Matches[1]+'.0';$securityPath='Software\Microsoft\Office\'+$audit.officeVersion+'\Excel\Security'
    Assert-VbaPolicy $audit.officeVersion
    $audit.accessBefore=Read-AccessValue $securityPath;$snapshotTaken=$true
    if(-not $audit.accessBefore.keyPresent){throw (Candidate-Failure 'Existing Excel Security key is absent; no security key is created.' 'BLOCKED_POLICY' 5)}
    $alreadyEnabled=$audit.accessBefore.present -and $audit.accessBefore.kind -ceq 'DWord' -and $audit.accessBefore.value -eq 1
    if(-not $alreadyEnabled -and -not $ApprovedTemporaryVbaAccess){throw (Candidate-Failure 'Explicit temporary VBA access approval is required.' 'BLOCKED_POLICY' 5)}
    $journal=[ordered]@{keyPath=$securityPath;valueName='AccessVBOM';snapshot=$audit.accessBefore;temporaryValue=1;temporaryKind='DWord';approvedTemporaryVbaAccess=[bool]$ApprovedTemporaryVbaAccess;requiresExactOwnedExcelExitBeforeFinalRestore=$true}
    $stream=[IO.File]::Open((Join-Path $output 'access-before.private.json'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $writer=New-Object IO.StreamWriter($stream,$utf8)
    try{$writer.Write(($journal|ConvertTo-Json -Depth 8));$writer.Flush();$stream.Flush($true)}finally{$writer.Dispose()}
    Assert-VbaPolicy $audit.officeVersion
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Excel opened during preparation; no temporary setting was written.'}
    if(-not (Same-AccessValue $audit.accessBefore (Read-AccessValue $securityPath))){throw 'Access preference changed before the test; preserved.'}
    if(-not $alreadyEnabled){
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($securityPath,$true)
        try{
            if($null -eq $key -or -not (Same-AccessValue $audit.accessBefore (Read-AccessValue $securityPath))){throw 'Security preference changed before temporary write.'}
            $securityWritten=$true;$audit.temporaryAccessWriteAttempted=$true;$audit.phase='before-temporary-access';Save-Audit
            $key.SetValue('AccessVBOM',1,[Microsoft.Win32.RegistryValueKind]::DWord);$key.Flush()
            $audit.temporaryAccessWritten=$true
        }finally{if($null -ne $key){$key.Close()}}
    }
    $audit.phase='starting-owned-COM-Excel';Save-Audit
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Excel opened before COM activation; no application was attached.'}
    Add-Type 'using System;using System.Runtime.InteropServices;public static class SlcFaultOwner{[DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr hwnd,out uint pid);}'
    $startUtc=[DateTime]::UtcNow
    $script:excel=New-Object -ComObject Excel.Application
    [uint32]$pidValue=0;[void][SlcFaultOwner]::GetWindowThreadProcessId([IntPtr][long]$script:excel.Hwnd,[ref]$pidValue)
    $process=Get-Process -Id $pidValue -ErrorAction Stop
    try{
        if($process.ProcessName -ine 'EXCEL' -or $process.StartTime.ToUniversalTime() -lt $startUtc.AddSeconds(-1) -or $process.SessionId -ne [Diagnostics.Process]::GetCurrentProcess().SessionId){throw 'COM did not create a fresh Excel in this session; ownership not assumed.'}
        $audit.owner=[ordered]@{pid=$process.Id;startTicks=$process.StartTime.ToUniversalTime().Ticks;startedUtc=$process.StartTime.ToUniversalTime().ToString('o');hwnd=[long]$script:excel.Hwnd}
    }finally{$process.Dispose()}
    Save-Audit;Assert-Owner
    $script:excel.AutomationSecurity=2
    $script:excel.Visible=$false;$script:excel.UserControl=$false
    $books=$null;$book=$null
    try{
        $books=$script:excel.Workbooks
        for($index=1;$index -le $books.Count;$index++){
            $book=$books.Item($index)
            try{if([IO.Path]::GetFullPath([string]$book.FullName) -ine $installed -or -not [bool]$book.IsAddin){throw 'Unexpected startup workbook; preserved.'}}
            finally{Release-FaultCom $book;$book=$null}
        }
        try{$book=$books.Item('ExcelSmartListCompare.xlam')}catch{$book=$books.Open($installed)}
        if([IO.Path]::GetFullPath([string]$book.FullName) -ine $installed -or -not [bool]$book.IsAddin -or -not [bool]$book.Saved){throw 'Installed add-in identity or initial Saved state differs.'}
        Release-FaultCom $book;$book=$null
        $book=$books.Add(-4167);$book.SaveAs($hostPath,51);$hostCreated=$true
        $hostHash=Get-SharedReadSha256 $hostPath
    }finally{Release-FaultCom $book;$book=$null;Release-FaultCom $books;$books=$null}
    $audit.actualReleaseVersion=[string]$script:excel.Run("'ExcelSmartListCompare.xlam'!SLC_ReleaseVersion")
    if($audit.actualReleaseVersion -cne $ExpectedReleaseVersion){throw 'Loaded release version differs.'}
    $expectedText=[IO.File]::ReadAllText($mainSource,[Text.Encoding]::ASCII)
    $initialMain=Check-MainModule 'before-probes-vs-candidate-source' $expectedText
    [IO.File]::WriteAllText((Join-Path $output 'main-before.private.txt'),$initialMain,$utf8)
    $settings=Read-Settings;$audit.settingsBefore=$settings
    $audit.phase='status-checkpoint';Save-Audit
    $statusOutput=Join-Path $output 'status-checkpoint.private.json'
    & $statusProbe -Excel $script:excel -OutputPath $statusOutput | Out-File -LiteralPath (Join-Path $output 'status-checkpoint.stdout.private.log') -Encoding UTF8
    $null=Check-MainModule 'after-status-probe' $initialMain
    $afterStatus=Read-Settings;$audit.settingsAfterStatusProbe=$afterStatus
    $statusComparison=Compare-FaultSettings $settings $afterStatus
    $audit.settingsComparisons+=@([ordered]@{phase='after-status-probe';comparison=$statusComparison})
    Save-Audit
    if(-not $statusComparison.passed){throw 'Status/checkpoint probe did not restore initial Excel settings.'}
    $statusResult=Get-Content -LiteralPath $statusOutput -Raw -Encoding UTF8|ConvertFrom-Json
    if($statusResult.status -cne 'PASS' -or $statusResult.assertions -ne 4){throw 'Status/checkpoint report failed.'}
    $audit.probeReports+=@([ordered]@{name='status-checkpoint';status='PASS';assertions=4;path=$statusOutput})
    $audit.phase='cancellation-transactions';Save-Audit
    $transactionOutput=Join-Path $output 'cancellation-transactions.private.json'
    & $transactionProbe -Excel $script:excel -OwnedPid $audit.owner.pid -ExpectedAddinPath $installed -OutputPath $transactionOutput -ExpectedSourcePath $mainSource -CanonicalizeSource {param([string]$Text) Normalize-Vba $Text} | Out-File -LiteralPath (Join-Path $output 'cancellation-transactions.stdout.private.log') -Encoding UTF8
    $null=Check-MainModule 'after-transaction-probes' $initialMain
    $transactionResult=Get-Content -LiteralPath $transactionOutput -Raw -Encoding UTF8|ConvertFrom-Json
    $caseIds=@($transactionResult.checks|ForEach-Object{[string]$_.id})
    if($transactionResult.status -cne 'PASS' -or $caseIds.Count -ne $transactionCases.Count -or
        ($caseIds -join '|') -cne ($transactionCases -join '|') -or
        @($transactionResult.checks|Where-Object{$_.status -cne 'PASS' -or $_.assertions -le 0}).Count -or
        -not $transactionResult.originalModuleRestored -or -not $transactionResult.diskUnchanged){throw 'Transaction case contract, report or restoration failed.'}
    $audit.probeReports+=@([ordered]@{name='cancellation-transactions';status='PASS';assertions=$transactionResult.assertions;cases=$transactionCases.Count;path=$transactionOutput})
    $observed=Read-Settings;$audit.settingsAfterProbes=$observed
    $comparison=Compare-FaultSettings $settings $observed
    $audit.settingsComparisons+=@([ordered]@{phase='after-probes';comparison=$comparison})
    $audit.settingsRestored=$comparison.passed
    if(-not $audit.settingsRestored){throw 'Probes did not restore initial Excel settings.'}
    $audit.status='PASS';$exitCode=0
}catch{
    $audit.status='FAIL';$audit.primaryFailure=$_.Exception.Message;$audit.failureStack=$_.ScriptStackTrace
    if($_.Exception.Data.Contains('CandidateStatus')){$audit.status=[string]$_.Exception.Data['CandidateStatus']}
    if($_.Exception.Data.Contains('ExitCode')){$exitCode=[int]$_.Exception.Data['ExitCode']}
}finally{
    $audit.phase='cleanup'
    try{Save-Audit}catch{$audit.cleanupErrors+=@('Could not write intermediate audit: '+$_.Exception.Message)}
    if($null -ne $script:excel -and $null -ne $audit.owner){
        $books=$null;$book=$null
        try{
            Assert-Owner
            $books=$script:excel.Workbooks;$known=@($installed);if($hostCreated){$known+=$hostPath}
            for($index=1;$index -le $books.Count;$index++){
                $book=$books.Item($index)
                try{
                    $full=[IO.Path]::GetFullPath([string]$book.FullName)
                    if($known -notcontains $full -or ($full -ieq $hostPath -and -not [bool]$book.Saved)){$audit.preservedUnexpectedWorkbooks+=@($full)}
                }finally{Release-FaultCom $book;$book=$null}
            }
            if($audit.preservedUnexpectedWorkbooks.Count){throw 'Unknown or modified workbook is preserved; Quit was refused.'}
            if($null -ne $settings){
                # A failed probe may exit before its own settings cleanup. Restore
                # only this fresh, known-fixture Excel before normal Quit; this
                # cleanup does not turn a failed probe into a passing test.
                $audit.settingsBeforeHostCleanup=Read-Settings
                $script:excel.ScreenUpdating=$settings.screenUpdating
                $script:excel.Interactive=$settings.interactive
                $script:excel.Calculation=$settings.calculation
                Restore-FaultStatus $script:excel $settings.statusBar
                $script:excel.EnableEvents=$settings.enableEvents
                $script:excel.EnableCancelKey=$settings.enableCancelKey
                $cleanupSettings=Read-Settings;$audit.settingsAfterHostCleanup=$cleanupSettings
                $comparison=Compare-FaultSettings $settings $cleanupSettings
                $audit.settingsComparisons+=@([ordered]@{phase='after-host-cleanup';comparison=$comparison})
                $audit.cleanupSettingsRestored=$comparison.passed
                if(-not $audit.cleanupSettingsRestored){$audit.cleanupErrors+=@('Host cleanup did not restore the initial Excel settings.')}
            }
            # Reacquire by exact path after probes: their FinalReleaseComObject
            # calls may invalidate borrowed workbook RCWs retained by a caller.
            foreach($path in $known){
                try{$book=$books.Item([IO.Path]::GetFileName($path))}catch{$book=$null}
                if($null -ne $book){
                    try{if([IO.Path]::GetFullPath([string]$book.FullName) -ine $path){throw 'Cleanup workbook identity changed.'};$book.Close($false)}
                    finally{Release-FaultCom $book;$book=$null}
                }
            }
            Release-FaultCom $books;$books=$null
            $audit.quitAttempted=$true;$script:excel.Quit()
        }catch{$audit.cleanupErrors+=@($_.Exception.Message)}
        finally{Release-FaultCom $book;$book=$null;Release-FaultCom $books;$books=$null}
    }
    try{Release-FaultCom $script:excel}catch{$audit.cleanupErrors+=@($_.Exception.Message)};$script:excel=$null
    [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();[GC]::WaitForPendingFinalizers()
    if($null -ne $audit.owner){
        $clock=[Diagnostics.Stopwatch]::StartNew();$alive=$true
        do{
            $process=Get-Process -Id $audit.owner.pid -ErrorAction SilentlyContinue;$alive=$false
            if($null -ne $process){try{$alive=$process.StartTime.ToUniversalTime().Ticks -eq $audit.owner.startTicks}finally{$process.Dispose()}}
            if($alive){Start-Sleep -Milliseconds 100}
        }while($alive -and $clock.Elapsed.TotalSeconds -lt 15)
        $audit.excelExited=-not $alive;$audit.ownedExcelExitedBeforeAccessRestore=-not $alive
        $audit.requiresPostExitSecurityRecheck=$alive -and $securityWritten
    }
    # Restore the original value/type only if our temporary value still exists.
    # An external change is preserved and makes the audit fail. If Excel remains,
    # restore now but require another check after its eventual cached-settings exit.
    if($snapshotTaken){
        try{
            if($securityWritten -and @(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){$audit.requiresPostExitSecurityRecheck=$true}
            $now=Read-AccessValue $securityPath
            if($securityWritten -and -not (Same-AccessValue $audit.accessBefore $now)){
                if($now.keyPresent -and $now.present -and $now.kind -ceq 'DWord' -and $now.value -eq 1){
                    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($securityPath,$true)
                    try{if($audit.accessBefore.present){$key.SetValue('AccessVBOM',$audit.accessBefore.value,[Microsoft.Win32.RegistryValueKind]$audit.accessBefore.kind)}else{$key.DeleteValue('AccessVBOM',$false)};$key.Flush()}
                    finally{if($null -ne $key){$key.Close()}}
                }else{$audit.externalSecurityChangeDetected=$true}
            }
            $audit.accessAfter=Read-AccessValue $securityPath;$audit.accessRestored=Same-AccessValue $audit.accessBefore $audit.accessAfter
        }catch{$audit.accessRestored=$false;$audit.cleanupErrors+=@($_.Exception.Message)}
    }
    try{
        $audit.diskSha256After=Get-SharedReadSha256 $installed;$audit.diskUnchanged=$audit.diskSha256Before -ceq $audit.diskSha256After
        $audit.sourceUnchanged=$audit.sourceSha256 -ceq (Get-FileHash -LiteralPath $mainSource).Hash.ToLowerInvariant()
        if($hostCreated -and $hostHash -cne (Get-SharedReadSha256 $hostPath)){$audit.cleanupErrors+=@('Synthetic host workbook bytes changed.')}
        foreach($item in $audit.helperHashes){if($item.sha256 -cne (Get-FileHash -LiteralPath $item.path).Hash.ToLowerInvariant()){$audit.cleanupErrors+=@('A test helper changed during the run: '+$item.path)}}
    }catch{$audit.cleanupErrors+=@($_.Exception.Message)}
    $audit.observedExcelAtEnd=@(Get-Process EXCEL -ErrorAction SilentlyContinue|ForEach-Object{
        $started=$null;try{$started=$_.StartTime.ToUniversalTime().ToString('o')}catch{}
        [ordered]@{pid=$_.Id;startedUtc=$started}
    })
    if($audit.cleanupErrors.Count -or -not $audit.diskUnchanged -or -not $audit.sourceUnchanged -or $audit.requiresPostExitSecurityRecheck -or ($snapshotTaken -and -not $audit.accessRestored) -or ($null -ne $audit.owner -and -not $audit.excelExited)){$audit.status='FAIL';$exitCode=1}
    $audit.phase='finished';$audit.finishedUtc=[DateTime]::UtcNow.ToString('o')
    try{Save-Audit}finally{if($locked){$mutex.ReleaseMutex()};if($null -ne $mutex){$mutex.Dispose()}}
}
Write-Output ($audit.status+': '+$reportPath)
exit $exitCode
