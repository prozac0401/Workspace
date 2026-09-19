[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [switch]$ApprovedTemporaryVbaAccess
)
# Build-only developer helper. The switch represents separately granted approval;
# it never bypasses organization policy. No installation or VBA tests are run.
# Hard process termination cannot run finally: the caller must recover from the
# immutable access-before.private.json if its supervisor forcibly stops this host.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$toolRoot=Split-Path -Parent $PSScriptRoot
$artifactsRoot=[IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts'))
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not $output.StartsWith(($artifactsRoot.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){
    throw 'OutputDirectory must be a fresh directory below this repository artifacts directory.'
}
if(Test-Path -LiteralPath $output){throw 'OutputDirectory already exists; preserve it and choose a fresh directory.'}
$ancestor=$output
while($ancestor -and $ancestor.Length -ge $artifactsRoot.Length){
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)){
        throw 'OutputDirectory cannot pass through a reparse point.'
    }
    $ancestor=Split-Path -Parent $ancestor
}
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Use native Windows PowerShell 5.1 through Invoke-BoundedTest.ps1.'}
[void][IO.Directory]::CreateDirectory($output)
$evidence=Join-Path $output 'build.private'
[void][IO.Directory]::CreateDirectory($evidence)
$sourceSnapshot=Join-Path $evidence 'source'
[void][IO.Directory]::CreateDirectory($sourceSnapshot)
$utf8=New-Object Text.UTF8Encoding($false)
$audit=[ordered]@{
    schemaVersion=1;status='NOT_RUN';phase='preflight';reason=$null;startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null
    primaryFailure=$null;failurePhase=$null;failureStack=$null
    approvedTemporaryVbaAccess=[bool]$ApprovedTemporaryVbaAccess;securityValueChanged=$false
    accessBefore=$null;accessAfter=$null;accessRestored=$null;externalSecurityChangeDetected=$false
    officeVersion=$null;owner=$null;excelExited=$null;observedExcelAtEnd=@();cleanupErrors=@()
    postQuitObservationSeconds=$null;ownedExcelExitedBeforeAccessRestore=$null
    candidateSaved=$false;candidateSha256=$null;sourceAudit=@();inputHashes=@();payloadHashes=@()
    inMemoryImportAudit='NOT_RUN';serializedSourceAudit='NOT_RUN';runtimeTests='NOT_RUN';installedTests='NOT_RUN'
    requiresInstalledTesting=$true;releaseApproved=$false
}
$mutex=$null;$locked=$false;$exitCode=1;$securityPath=$null;$securityWritten=$false
$workbooks=$null;$book=$null;$project=$null;$components=$null;$component=$null;$codeModule=$null
$script:Excel=$null;$script:ExcelVersion=$null;$script:ExcelProcess=$null;$script:ExcelBootstrap=$null;$script:ExcelSessionBook=$null
$functionsLoaded=$false;$securitySnapshotTaken=$false
function Save-CandidateAudit {
    $destination=Join-Path $evidence 'build-result.private.json'
    $temporary=Join-Path $evidence 'build-result.private.writing'
    [IO.File]::WriteAllText($temporary,($audit | ConvertTo-Json -Depth 14),$utf8)
    # PS5 converts $null to an empty path for a string argument; pass a real null.
    if([IO.File]::Exists($destination)){[IO.File]::Replace($temporary,$destination,[NullString]::Value)}
    else{[IO.File]::Move($temporary,$destination)}
}
function Candidate-Failure([string]$Message,[string]$Status='FAIL',[int]$Code=1){
    $exception=New-Object InvalidOperationException($Message)
    $exception.Data['CandidateStatus']=$Status;$exception.Data['ExitCode']=$Code
    return $exception
}
function Read-AccessValue([string]$Path){
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path)
    try{
        if($null -eq $key){return [ordered]@{keyPresent=$false;present=$false;kind=$null;value=$null}}
        $present=$key.GetValueNames() -contains 'AccessVBOM'
        return [ordered]@{keyPresent=$true;present=$present;kind=$(if($present){[string]$key.GetValueKind('AccessVBOM')}else{$null});value=$(if($present){$key.GetValue('AccessVBOM',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}else{$null})}
    }finally{if($null -ne $key){$key.Close()}}
}
function Same-AccessValue($Left,$Right){
    return ($Left.keyPresent -eq $Right.keyPresent -and $Left.present -eq $Right.present -and $Left.kind -ceq $Right.kind -and
        (ConvertTo-Json -InputObject $Left.value -Compress) -ceq (ConvertTo-Json -InputObject $Right.value -Compress))
}
function Assert-NoExistingInstallation {
    foreach($directory in @('ExcelSmartListCompare','ExcelSmartListCompare.Setup')){
        if(Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA $directory)){
            throw (Candidate-Failure 'An existing product or installer-manager directory prevents this isolated build.' 'BLOCKED_ENV' 3)
        }
    }
    foreach($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryHive]::LocalMachine)){
        foreach($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)){
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
            try{
                $apps=$base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Uninstall\ExcelSmartListCompare.OneFile_is1')
                if($null -ne $apps){$apps.Close();throw (Candidate-Failure 'An existing product Apps registration prevents this isolated build.' 'BLOCKED_ENV' 3)}
                $office=$base.OpenSubKey('Software\Microsoft\Office')
                if($null -eq $office){continue}
                try{
                    foreach($version in @($office.GetSubKeyNames() | Where-Object {$_ -match '^\d+\.\d+$'})){
                        foreach($suffix in @('Excel\Options','Excel\Add-in Manager')){
                            $registration=$office.OpenSubKey($version+'\'+$suffix)
                            if($null -eq $registration){continue}
                            try{
                                foreach($name in $registration.GetValueNames()){
                                    if(($suffix -eq 'Excel\Options' -and $name -match '^OPEN\d*$' -and [string]$registration.GetValue($name) -match 'ExcelSmartListCompare') -or
                                       ($suffix -eq 'Excel\Add-in Manager' -and $name -match 'ExcelSmartListCompare')){
                                        throw (Candidate-Failure 'An existing product Excel registration prevents this isolated build.' 'BLOCKED_ENV' 3)
                                    }
                                }
                            }finally{$registration.Close()}
                        }
                    }
                }finally{$office.Close()}
            }finally{$base.Close()}
        }
    }
}
function Assert-VbaPolicy([string]$Version){
    foreach($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryHive]::LocalMachine)){
        foreach($view in @([Microsoft.Win32.RegistryView]::Registry64,[Microsoft.Win32.RegistryView]::Registry32)){
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hive,$view)
            try{
                foreach($prefix in @('Software\Policies\Microsoft\Office\','Software\Policies\Microsoft\Cloud\Office\')){
                    $key=$base.OpenSubKey($prefix+$Version+'\Excel\Security')
                    if($null -eq $key){continue}
                    try{
                        if($key.GetValueNames() -contains 'AccessVBOM'){
                            if($key.GetValueKind('AccessVBOM') -ne [Microsoft.Win32.RegistryValueKind]::DWord -or $key.GetValue('AccessVBOM') -ne 1){
                                throw (Candidate-Failure 'Organization policy does not allow VBA project access; no security preference was changed.' 'BLOCKED_POLICY' 5)
                            }
                        }
                    }finally{$key.Close()}
                }
            }finally{$base.Close()}
        }
    }
}
function Normalize-Vba([string]$Text){
    $lines=$Text.Replace("`r`n","`n").Replace("`r","`n").Split("`n")
    $first=-1
    for($index=0;$index -lt $lines.Length;$index++){if($lines[$index].Trim() -ceq 'Option Explicit'){$first=$index;break}}
    if($first -lt 0){throw 'VBA source is missing its expected Option Explicit boundary.'}
    $normalized=@($lines[$first..($lines.Length-1)] | Where-Object {$_ -notmatch '^Attribute VB_'} | ForEach-Object {$_.TrimEnd()})
    # VBE rewrites identifier/member capitalization on import. Fold only code
    # identifiers; preserve string literals (including escaped quotes), comments,
    # numbers and punctuation so this cannot hide an executable source change.
    $codeTokens=[regex]'"(?:[^"]|"")*"|''.*|[A-Za-z_][A-Za-z0-9_]*'
    $normalized=@($normalized | ForEach-Object {
        $codeTokens.Replace($_,[Text.RegularExpressions.MatchEvaluator]{param($match)
            if($match.Value.StartsWith('"') -or $match.Value.StartsWith("'")){return $match.Value}
            return $match.Value.ToLowerInvariant()
        })
    })
    return ($normalized -join "`n").TrimEnd("`n")
}
function Record-SourceAudit([string]$Name,[string]$Expected,[string]$Actual){
    $wanted=Normalize-Vba $Expected;$observed=Normalize-Vba $Actual
    $record=[ordered]@{component=$Name;status=$(if($wanted -ceq $observed){'PASS'}else{'FAIL'});sourceNormalizedSha256=(Bytes-Sha256 ([Text.Encoding]::UTF8.GetBytes($wanted))).ToLowerInvariant();importedNormalizedSha256=(Bytes-Sha256 ([Text.Encoding]::UTF8.GetBytes($observed))).ToLowerInvariant()}
    $audit.sourceAudit+=@($record)
    if($record.status -ne 'PASS'){
        [IO.File]::WriteAllText((Join-Path $evidence ($Name+'.expected.txt')),$wanted,$utf8)
        [IO.File]::WriteAllText((Join-Path $evidence ($Name+'.imported.txt')),$observed,$utf8)
        throw ('Imported VBA source differs before SaveAs: '+$Name)
    }
}
function Invoke-CandidateComBuild {
    # All document/VBE references leave scope before application Quit and GC.
    $workbooks=$null;$book=$null;$project=$null;$components=$null;$component=$null;$codeModule=$null
    try{
        $script:Excel.EnableEvents=$false
        $workbooks=$script:Excel.Workbooks
        if([int]$workbooks.Count -ne 0){throw 'Unexpected workbook before candidate creation; preserving it.'}
        $book=$workbooks.Add(-4167)
        try{$project=$book.GetType().InvokeMember('VBProject',[Reflection.BindingFlags]::GetProperty,$null,$book,$null)}
        catch{throw (Candidate-Failure ('Excel still blocked VBA project access: '+$_.Exception.Message) 'BLOCKED_POLICY' 5)}
        $components=$project.VBComponents
        foreach($name in $imports){
            $component=$components.Import((Join-Path $sourceSnapshot $name));$codeModule=$component.CodeModule
            Record-SourceAudit ([string]$component.Name) ([IO.File]::ReadAllText((Join-Path $sourceSnapshot $name),[Text.Encoding]::ASCII)) ([string]$codeModule.Lines(1,$codeModule.CountOfLines))
            Release-Com $codeModule;$codeModule=$null;Release-Com $component;$component=$null
        }
        $component=$components.Item([string]$book.CodeName);$codeModule=$component.CodeModule
        if($codeModule.CountOfLines -gt 0){$codeModule.DeleteLines(1,$codeModule.CountOfLines)}
        $eventSource=[IO.File]::ReadAllText((Join-Path $sourceSnapshot 'ThisWorkbook_events.txt'),[Text.Encoding]::ASCII)
        $codeModule.AddFromString($eventSource)
        Record-SourceAudit 'ThisWorkbook' $eventSource ([string]$codeModule.Lines(1,$codeModule.CountOfLines))
        Release-Com $codeModule;$codeModule=$null;Release-Com $component;$component=$null
        $audit.inMemoryImportAudit='PASS';$project.Name='SLC2026'
        Release-Com $components;$components=$null;Release-Com $project;$project=$null
        $book.IsAddin=$true
        $candidatePath=Join-Path $output 'ExcelSmartListCompare.xlam'
        $book.SaveAs($candidatePath,55)
        $book.Close($false);Release-Com $book;$book=$null
        return $candidatePath
    }finally{
        foreach($value in @($codeModule,$component,$components,$project)){try{Release-Com $value}catch{$audit.cleanupErrors+=@($_.Exception.Message)}}
        $value=$null;$codeModule=$null;$component=$null;$components=$null;$project=$null
        if($null -ne $book){try{$book.Close($false)}catch{$audit.cleanupErrors+=@($_.Exception.Message)}finally{Release-Com $book;$book=$null}}
        try{Release-Com $workbooks}catch{$audit.cleanupErrors+=@($_.Exception.Message)}
        $workbooks=$null
    }
}
function Wait-CandidateExcelExit([int]$Seconds=15){
    [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();[GC]::WaitForPendingFinalizers()
    if($null -eq $audit.owner){return}
    $timer=[Diagnostics.Stopwatch]::StartNew();$sameProcess=$false
    do{
        $process=Get-Process -Id $audit.owner.pid -ErrorAction SilentlyContinue
        $sameProcess=$false
        if($null -ne $process){
            try{$sameProcess=$process.StartTime.ToUniversalTime().Ticks -eq $audit.owner.startTimeUtcTicks}
            finally{$process.Dispose()}
        }
        if(-not $sameProcess){break}
        Start-Sleep -Milliseconds 100
    }while($timer.Elapsed.TotalSeconds -lt $Seconds)
    $audit.postQuitObservationSeconds=$timer.Elapsed.TotalSeconds
    $audit.ownedExcelExitedBeforeAccessRestore=(-not $sameProcess)
    if($sameProcess){$audit.cleanupErrors+=@('Owned Excel did not exit within the post-Quit observation window; no process was killed.')}
}
try{
    $mutex=New-Object Threading.Mutex($false,'Local\ExcelSmartListCompare-Setup')
    try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
    if(-not $locked){throw (Candidate-Failure 'Another product build/install/remove operation is running.' 'BLOCKED_ENV' 4)}
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw (Candidate-Failure 'Excel is already running; no Excel or security setting was changed.' 'BLOCKED_ENV' 3)}
    Assert-NoExistingInstallation
    $curVer=[Microsoft.Win32.Registry]::ClassesRoot.OpenSubKey('Excel.Application\CurVer')
    try{$progId=if($null -ne $curVer){[string]$curVer.GetValue('')}else{''}}finally{if($null -ne $curVer){$curVer.Close()}}
    if($progId -notmatch '^Excel\.Application\.(\d+)$'){throw (Candidate-Failure 'The registered Excel version could not be determined.' 'BLOCKED_ENV' 3)}
    $audit.officeVersion=$Matches[1]+'.0';$securityPath='Software\Microsoft\Office\'+$audit.officeVersion+'\Excel\Security'
    Assert-VbaPolicy $audit.officeVersion
    $audit.accessBefore=Read-AccessValue $securityPath;$securitySnapshotTaken=$true
    $alreadyEnabled=$audit.accessBefore.present -and $audit.accessBefore.kind -ceq 'DWord' -and $audit.accessBefore.value -eq 1
    if(-not $alreadyEnabled -and -not $ApprovedTemporaryVbaAccess){
        throw (Candidate-Failure 'VBA project access is disabled. Separate approval is required before using ApprovedTemporaryVbaAccess; nothing was changed.' 'BLOCKED_POLICY' 5)
    }
    if(-not $audit.accessBefore.keyPresent){throw (Candidate-Failure 'The existing Excel security key is absent; this helper does not create security keys.' 'BLOCKED_POLICY' 5)}
    # Snapshot the exact build inputs; never export over or edit repository sources.
    $imports=@('CSLCList.cls','CSLCAppEvents.cls','modSLCNormalize.bas','modSLCMain.bas','modSLCReport.bas')
    foreach($name in ($imports+@('ThisWorkbook_events.txt','customUI14.xml'))){
        Copy-Item -LiteralPath (Join-Path $toolRoot ('src/'+$name)) -Destination (Join-Path $sourceSnapshot $name)
    }
    foreach($name in @('Setup.ps1','Install.cmd','Uninstall.cmd','Test_Excel.cmd')){
        Copy-Item -LiteralPath (Join-Path $toolRoot $name) -Destination (Join-Path $output $name)
    }
    Copy-Item -LiteralPath (Join-Path $toolRoot 'docs/RELEASE_README.md') -Destination (Join-Path $output 'README.md')
    $parseErrors=$null;$tokens=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $output 'Setup.ps1'),[ref]$tokens,[ref]$parseErrors)
    if($parseErrors.Count){throw 'Copied Setup.ps1 failed parsing.'}
    $needed=@('Setup-Failure','Release-Com','New-SessionBootstrap','Bytes-Sha256','Read-ZipText','Write-ZipText','Write-PackageMetadata','Start-OwnExcel','Stop-OwnExcel')
    foreach($name in $needed){
        $definitions=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$false))
        if($definitions.Count -ne 1){throw ('Expected exactly one Setup helper: '+$name)}
        . ([scriptblock]::Create($definitions[0].Extent.Text))
    }
    $functionsLoaded=$true
    foreach($name in ($imports+@('ThisWorkbook_events.txt'))){
        if(@([IO.File]::ReadAllBytes((Join-Path $sourceSnapshot $name)) | Where-Object {$_ -gt 127}).Count){throw ('VBA import is not ASCII: '+$name)}
    }
    foreach($file in @(Get-ChildItem -LiteralPath $sourceSnapshot -File)){
        $audit.inputHashes+=@([ordered]@{name=$file.Name;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()})
    }
    Assert-VbaPolicy $audit.officeVersion
    Assert-NoExistingInstallation
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw (Candidate-Failure 'Excel opened during preparation; no security setting was changed.' 'BLOCKED_ENV' 3)}
    if(-not (Same-AccessValue $audit.accessBefore (Read-AccessValue $securityPath))){throw 'VBA access preference changed during preparation; nothing was overwritten.'}
    if(-not $alreadyEnabled){
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($securityPath,$true)
        try{
            if($null -eq $key){throw 'Excel security key disappeared; no key was created.'}
            if(-not (Same-AccessValue $audit.accessBefore (Read-AccessValue $securityPath))){throw 'VBA access preference changed before the temporary write; nothing was overwritten.'}
            # This immutable journal survives a wrapper timeout or host crash.
            $prior=[ordered]@{keyPath=$securityPath;valueName='AccessVBOM';snapshot=$audit.accessBefore;temporaryValue=1;temporaryKind='DWord';approvedTemporaryVbaAccess=$true}
            $stream=[IO.File]::Open((Join-Path $evidence 'access-before.private.json'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
            $writer=New-Object IO.StreamWriter($stream,$utf8)
            try{$writer.Write(($prior | ConvertTo-Json -Depth 8));$writer.Flush();$stream.Flush($true)}finally{$writer.Dispose()}
            $audit.phase='before-temporary-access';Save-CandidateAudit
            # Mark the restoration obligation before the single potentially mutating call.
            $securityWritten=$true;$audit.securityValueChanged=$true
            $key.SetValue('AccessVBOM',1,[Microsoft.Win32.RegistryValueKind]::DWord);$key.Flush()
            $audit.phase='temporary-access-enabled';Save-CandidateAudit
        }finally{if($null -ne $key){$key.Close()}}
    }
    Start-OwnExcel -NormalStart
    $audit.owner=[ordered]@{pid=$script:ExcelProcess.Id;startedUtc=$script:ExcelProcess.StartTime.ToUniversalTime().ToString('o');startTimeUtcTicks=$script:ExcelProcess.StartTime.ToUniversalTime().Ticks}
    $audit.excelVersion=$script:ExcelVersion
    $audit.phase='excel-started';Save-CandidateAudit
    $candidate=Invoke-CandidateComBuild
    [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
    Write-PackageMetadata $candidate (Join-Path $sourceSnapshot 'customUI14.xml')
    $audit.candidateSaved=$true;$audit.candidateSha256=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    $audit.phase='candidate-saved';Save-CandidateAudit
    foreach($name in @('ExcelSmartListCompare.xlam','Setup.ps1','Install.cmd','Uninstall.cmd','Test_Excel.cmd','README.md')){
        $audit.payloadHashes+=@([ordered]@{name=$name;sha256=(Get-FileHash -LiteralPath (Join-Path $output $name) -Algorithm SHA256).Hash.ToLowerInvariant()})
    }
    $audit.status='PASS';$audit.reason='Build-only candidate saved; compiled, serialized-source and installed testing are still required.';$exitCode=0
}catch{
    $audit.primaryFailure=$_.Exception.Message;$audit.failurePhase=$audit.phase;$audit.failureStack=$_.ScriptStackTrace
    $audit.status='FAIL';$exitCode=1
    if($_.Exception.Data.Contains('CandidateStatus')){$audit.status=[string]$_.Exception.Data['CandidateStatus']}
    if($_.Exception.Data.Contains('ExitCode')){$exitCode=[int]$_.Exception.Data['ExitCode']}
    $audit.reason=$_.Exception.Message
}finally{
    if($functionsLoaded){
        foreach($value in @($codeModule,$component,$components,$project)){try{Release-Com $value}catch{$audit.cleanupErrors+=@($_.Exception.Message)}}
        $codeModule=$null;$component=$null;$components=$null;$project=$null
        if($null -ne $book){try{$book.Close($false)}catch{$audit.cleanupErrors+=@($_.Exception.Message)}finally{Release-Com $book;$book=$null}}
        try{Release-Com $workbooks}catch{$audit.cleanupErrors+=@($_.Exception.Message)}
        $workbooks=$null
        [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
        if($null -eq $audit.owner -and $null -ne $script:ExcelProcess){
            try{$audit.owner=[ordered]@{pid=$script:ExcelProcess.Id;startedUtc=$script:ExcelProcess.StartTime.ToUniversalTime().ToString('o');startTimeUtcTicks=$script:ExcelProcess.StartTime.ToUniversalTime().Ticks}}catch{$audit.cleanupErrors+=@($_.Exception.Message)}
        }
        try{
            $quitBooks=$null
            try{
                if($null -ne $script:Excel){
                    $quitBooks=$script:Excel.Workbooks
                    if([int]$quitBooks.Count -ne 0){throw 'Unexpected workbook remains; Quit refused to preserve it.'}
                }
            }finally{Release-Com $quitBooks;$quitBooks=$null}
            Stop-OwnExcel
        }catch{
            $audit.cleanupErrors+=@($_.Exception.Message)
            # Never use Quit to dispose of an unrecognized workbook.
            try{Release-Com $script:Excel}catch{$audit.cleanupErrors+=@($_.Exception.Message)}
            $script:Excel=$null
        }
        try{Wait-CandidateExcelExit -Seconds 15}catch{$audit.cleanupErrors+=@($_.Exception.Message)}
    }
    # Restoration happens after Quit/COM release so Excel cannot immediately
    # persist its cached preference over the restored value during normal exit.
    if($securitySnapshotTaken){
        try{
            $now=Read-AccessValue $securityPath
            if($securityWritten -and -not (Same-AccessValue $audit.accessBefore $now)){
                if($now.keyPresent -and $now.present -and $now.kind -ceq 'DWord' -and $now.value -eq 1){
                    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($securityPath,$true)
                    try{
                        if($audit.accessBefore.present){$key.SetValue('AccessVBOM',$audit.accessBefore.value,[Microsoft.Win32.RegistryValueKind]$audit.accessBefore.kind)}
                        else{$key.DeleteValue('AccessVBOM',$false)}
                        $key.Flush()
                    }finally{if($null -ne $key){$key.Close()}}
                }else{$audit.externalSecurityChangeDetected=$true}
            }
            $audit.accessAfter=Read-AccessValue $securityPath
            $audit.accessRestored=Same-AccessValue $audit.accessBefore $audit.accessAfter
        }catch{$audit.accessRestored=$false;$audit.cleanupErrors+=@($_.Exception.Message)}
    }
    $audit.observedExcelAtEnd=@(Get-Process EXCEL -ErrorAction SilentlyContinue | ForEach-Object {
        $start=$null;try{$start=$_.StartTime.ToUniversalTime().ToString('o')}catch{}
        [ordered]@{pid=$_.Id;startedUtc=$start}
    })
    if($null -ne $audit.owner){
        $audit.excelExited=@($audit.observedExcelAtEnd | Where-Object {$_.pid -eq $audit.owner.pid -and ($null -eq $_.startedUtc -or $_.startedUtc -eq $audit.owner.startedUtc)}).Count -eq 0
    }
    if($audit.cleanupErrors.Count -gt 0 -or ($securitySnapshotTaken -and -not $audit.accessRestored) -or ($null -ne $audit.owner -and -not $audit.excelExited)){
        $audit.status='FAIL';$audit.reason='Build cleanup or security-value restoration could not be verified. Inspect the private audit; no Excel process was killed.';$exitCode=1
    }
    $audit.finishedUtc=[DateTime]::UtcNow.ToString('o')
    $audit.phase='finished'
    try{Save-CandidateAudit}
    finally{if($locked){$mutex.ReleaseMutex()};if($null -ne $mutex){$mutex.Dispose()}}
}
Write-Output ($audit.status+': '+$audit.reason)
Write-Output ('Local build audit: '+(Join-Path $evidence 'build-result.private.json'))
exit $exitCode
