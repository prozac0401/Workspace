[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AddinPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string[]]$Case,
    [switch]$LegacyWording
)
# Actual Excel COM capacity evidence, not native input or normal-start evidence.
# Default: six 100/1,000/5,000-cell cases. Larger cases require an explicit -Case.
# No dialog responder is installed. Observe/answer native dialogs separately.
# Run under Invoke-BoundedTest.ps1: a blocked COM call has no in-process timeout.
# At most one synthetic source, one result and the target add-in coexist.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Windows desktop Excel is required.'}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run in a Windows PowerShell STA process.'}
$addin=[IO.Path]::GetFullPath($AddinPath)
if(-not (Test-Path -LiteralPath $addin -PathType Leaf) -or [IO.Path]::GetExtension($addin) -ine '.xlam'){
    throw 'AddinPath must identify an existing, already built XLAM.'
}
$output=[IO.Path]::GetFullPath($OutputDirectory)
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$artifactRoots=@(
    [IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts')),
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts'))
)
$insideArtifacts=$false
foreach($root in $artifactRoots){
    if($output.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){$insideArtifacts=$true}
}
if(-not $insideArtifacts){throw 'Use a new local evidence directory below repository artifacts or tool artifacts.'}
if(Test-Path -LiteralPath $output){throw 'Evidence directory already exists; prior fixtures are preserved.'}
$ancestor=Split-Path -Parent $output
while($ancestor){
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)){
        throw 'Evidence paths must not traverse a reparse point.'
    }
    $ancestor=Split-Path -Parent $ancestor
}

$catalog=[ordered]@{}
function Add-CapacityCase([string]$Id,[int]$Count,[string]$Distribution,[int]$Length,[int]$Matched,[int]$Rows,[long]$RawChars){
    $catalog[$Id]=[pscustomobject][ordered]@{
        id=$Id;cellsPerList=$Count;distribution=$Distribution;charactersPerCell=$Length
        expectedMatched=$Matched;expectedRows=$Rows;expectedRawCharsPerList=$RawChars
        captureWarningExpected=($Count -ge 20000);compareWarningExpected=(2*$Count -ge 20000)
    }
}
foreach($count in @(100,1000,5000,10000,19999,20000,50000,100000)){
    Add-CapacityCase ('Duplicate'+$count) $count 'duplicate' 48 $count 1 (48L*$count)
    Add-CapacityCase ('Unique'+$count) $count 'disjoint' 48 0 (2*$count) (48L*$count)
}
Add-CapacityCase 'UniqueOverlap5000' 5000 'overlap' 48 2500 5000 240000
Add-CapacityCase 'UniqueShort10000' 10000 'disjoint' 16 0 20000 160000
Add-CapacityCase 'UniqueLong1000' 1000 'disjoint' 4096 0 2000 4096000
Add-CapacityCase 'DuplicateMaxChars1221' 1221 'maxchars' 0 1221 1 5000000
foreach($count in @(1000,5000,10000)){
    Add-CapacityCase ('NumericExpansion'+$count) $count 'numeric-expansion' 13 0 (2*$count) (13L*$count)
}
$caseIds=@($Case)
if($null -eq $Case -or $Case.Count -eq 0){
    $caseIds=@('Duplicate100','Unique100','Duplicate1000','Unique1000','Duplicate5000','Unique5000')
}
if(@($caseIds | Select-Object -Unique).Count -ne $caseIds.Count){throw 'Select each case at most once.'}
foreach($id in $caseIds){
    if(-not $catalog.Contains($id)){throw ('Unknown case '+$id+'. Available: '+($catalog.Keys -join ', '))}
}
if(@(Get-Process -Name EXCEL -ErrorAction SilentlyContinue).Count){throw 'Existing Excel detected; nothing was attached, opened or closed.'}
[void][IO.Directory]::CreateDirectory($output)
$utf8=New-Object Text.UTF8Encoding($false)
$checks=[Collections.Generic.List[object]]::new()
$caseResults=[Collections.Generic.List[object]]::new()
$ownedBooks=[Collections.Generic.List[object]]::new()
$excel=$null;$addbook=$null;$ownedPid=0;$ownedStartTicks=0L
$source=$null;$sheetA=$null;$sheetB=$null;$rangeA=$null;$rangeB=$null;$result=$null;$resultSheet=$null
$activeCase=$null;$failure=$null;$cleanupErrors=[Collections.Generic.List[string]]::new()
$qualified="'"+([IO.Path]::GetFileName($addin)).Replace("'","''")+"'!"
$addinHashBefore=(Get-FileHash -LiteralPath $addin -Algorithm SHA256).Hash.ToLowerInvariant()
$report=[ordered]@{
    schemaVersion=1;status='STARTED';startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null
    evidenceLayer='Actual Excel COM; operator handles native dialogs'
    testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    resultOwnershipScope='A new unsaved workbook, exact product sheet/title, and unchanged known workbook set are required. This cannot distinguish a third-party add-in deliberately producing an identical workbook.'
    selectedCases=$caseIds;caseDefinitions=@($caseIds | ForEach-Object {$catalog[$_]});legacyWording=[bool]$LegacyWording
    addinSha256Before=$addinHashBefore;addinSha256After=$null;owner=$null
    builtIn=$null;cases=@();checks=@();cleanupErrors=@();error=$null
    nativeEscVerified=$false;normalStartVerified=$false;maximumWorkbookCount=0
    timingScope='Public macro wall time includes native dialog waiting; setup and verification are separate. Phase breakdown is NOT_RUN.'
    resourceScope='Before/after process samples only. Peak working set is cumulative for the owned session. Use the bounded runner for periodic telemetry.'
}
function Save-Evidence {
    $report.cases=@($caseResults.ToArray())
    $report.checks=@($checks.ToArray())
    $report.cleanupErrors=@($cleanupErrors.ToArray())
    [IO.File]::WriteAllText((Join-Path $output 'capacity.json'),($report | ConvertTo-Json -Depth 14),$utf8)
}
function Release-Com($Value){
    if($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)){
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)
    }
}
function Check([string]$Id,[bool]$Passed,$Actual,$Expected,[switch]$Continue){
    $caseName=if($null -eq $activeCase){'SESSION'}else{$activeCase.id}
    $checks.Add([pscustomobject][ordered]@{case=$caseName;id=$Id;status=if($Passed){'PASS'}else{'FAIL'};actual=$Actual;expected=$Expected})
    Save-Evidence
    Write-Host ($caseName+' '+$Id+': '+$Passed)
    if(-not $Passed -and -not $Continue){throw ('Assertion failed: '+$caseName+' '+$Id)}
}
function Get-SharedHash([string]$Path){
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant()}finally{$stream.Dispose()}
}
function Get-Settings {
    return [ordered]@{
        screenUpdating=[bool]$excel.ScreenUpdating;enableEvents=[bool]$excel.EnableEvents
        interactive=[bool]$excel.Interactive;enableCancelKey=[int]$excel.EnableCancelKey
        calculation=[int]$excel.Calculation;displayAlerts=[bool]$excel.DisplayAlerts
        automationSecurity=[int]$excel.AutomationSecurity
    }
}
function Get-Resources {
    $process=Get-Process -Id $ownedPid -ErrorAction Stop
    try{
        if($process.StartTime.ToUniversalTime().Ticks -ne $ownedStartTicks){throw 'Owned process identity changed.'}
        return [ordered]@{
            atUtc=[DateTime]::UtcNow.ToString('o');privateBytes=$process.PrivateMemorySize64
            workingSetBytes=$process.WorkingSet64;sessionPeakWorkingSetBytes=$process.PeakWorkingSet64
            cpuMilliseconds=$process.TotalProcessorTime.TotalMilliseconds
        }
    }finally{$process.Dispose()}
}
function Get-Menu {
    return [string]$excel.Run(($qualified+'SLC_MenuXml'),'Cell')
}
function Assert-WorkbookBound {
    $count=[int]$excel.Workbooks.Count
    if($count -gt $report.maximumWorkbookCount){$report.maximumWorkbookCount=$count}
    Check 'workbook-bound' ($count -le 3) $count 'at most 3 including target add-in'
}
function Get-KnownWorkbookSnapshot {
    $known=@($ownedBooks | ForEach-Object {[pscustomobject]@{name=[string]$_.Name;fullName=[string]$_.FullName}})
    $snapshot=[Collections.Generic.List[object]]::new()
    for($index=1;$index -le [int]$excel.Workbooks.Count;$index++){
        # Collection lookups borrow workbook RCWs. Do not force-release aliases
        # while the owning references may still be used by this test.
        $book=$excel.Workbooks.Item($index)
        $name=[string]$book.Name;$fullName=[string]$book.FullName
        if(@($known | Where-Object {$_.name -ceq $name -and $_.fullName -ceq $fullName}).Count -ne 1){throw 'Unexpected workbook before the macro; preserving it and stopping the test.'}
        $snapshot.Add([pscustomobject]@{name=$name;fullName=$fullName})
    }
    return $snapshot.ToArray()
}
function Get-VerifiedNewResult([object[]]$Before){
    $after=[Collections.Generic.List[object]]::new()
    for($index=1;$index -le [int]$excel.Workbooks.Count;$index++){
        $book=$excel.Workbooks.Item($index)
        $after.Add([pscustomobject]@{name=[string]$book.Name;fullName=[string]$book.FullName})
    }
    if($after.Count -ne $Before.Count+1){throw 'Expected exactly one additional workbook; preserving unrecognized workbooks.'}
    foreach($entry in $Before){
        if(@($after | Where-Object {$_.name -ceq $entry.name -and $_.fullName -ceq $entry.fullName}).Count -ne 1){throw 'A previously known workbook changed or disappeared; preserving unrecognized workbooks.'}
    }
    $new=@($after | Where-Object {$Before.name -cnotcontains $_.name})
    if($new.Count -ne 1){throw 'New result identity is ambiguous; preserving unrecognized workbooks.'}
    $book=$excel.ActiveWorkbook;$resultTab=$null
    try{
        if([string]$book.Name -cne $new[0].name -or [string]$book.FullName -cne $new[0].fullName -or [string]$book.Path -cne '' -or [bool]$book.Saved){throw 'The active workbook is not the new unsaved result; preserving it.'}
        if([int]$book.Sheets.Count -ne 1 -or [int]$book.Worksheets.Count -ne 1){throw 'Unexpected result workbook shape; preserving it.'}
        $resultTab=$book.Worksheets.Item(1)
        if([string]$resultTab.Name -cne '명단비교_결과' -or (Cell-Text $resultTab 'A1') -cne '명단 비교 결과'){throw 'Result sheet or literal title mismatch; preserving the unrecognized workbook.'}
        return ,$book
    }finally{
        Release-Com $resultTab
        # Workbook ownership is recorded by the caller only after acceptance.
        # A rejected candidate is not closed or force-released by this probe.
    }
}
function Invoke-Public([string]$Phase,[bool]$WarningExpected){
    $activeCase.phase=$Phase
    $activeCase.workbooksBeforeInvoke=@(Get-KnownWorkbookSnapshot)
    $before=Get-Resources
    Save-Evidence
    if($WarningExpected){Write-Host ('WAITING_FOR_NATIVE_DIALOG '+$activeCase.id+' '+$Phase+'; observe the warning and choose Yes to measure completion.')}
    else{Write-Host ('RUN_PUBLIC_SELECTION '+$activeCase.id+' '+$Phase+'; any unexpected native dialog needs operator inspection.')}
    $timer=[Diagnostics.Stopwatch]::StartNew()
    try{$null=$excel.Run(($qualified+'SLC_Run'))}
    finally{
        $timer.Stop()
        $after=Get-Resources
        $activeCase.measurements+=@([ordered]@{
            phase=$Phase;wallMillisecondsIncludingDialogs=$timer.Elapsed.TotalMilliseconds
            excelCpuMilliseconds=($after.cpuMilliseconds-$before.cpuMilliseconds)
            warningExpected=$WarningExpected;before=$before;after=$after
        })
        Save-Evidence
    }
}
function Cell-Text($Sheet,[string]$Address){
    $cell=$Sheet.Range($Address)
    try{return [string]$cell.Value2}finally{Release-Com $cell}
}
function Make-Values($Sheet,$Definition,[bool]$Second){
    $count=$Definition.cellsPerList
    $range=$Sheet.Range('A1:A'+$count)
    try{
        switch($Definition.distribution){
            'duplicate' {$range.Value2=('shared_'+('x'*($Definition.charactersPerCell-7)))}
            'maxchars' {
                $large=$Sheet.Range('A1:A1220');$tail=$Sheet.Range('A1221')
                try{$large.Value2=('x'*4096);$tail.Value2=('y'*2880)}finally{Release-Com $tail;Release-Com $large}
            }
            'numeric-expansion' {
                $leading=if($Second){'2.'}else{'1.'}
                $range.FormulaR1C1='="'+$leading+'"&TEXT(ROW()-1,"000000")&"e1000"'
                $range.Calculate()
            }
            default {
                $prefix=if($Definition.distribution -eq 'overlap'){'v_'}elseif($Second){'b_'}else{'a_'}
                $offset=if($Definition.distribution -eq 'overlap' -and $Second){[int]($count/2)}else{0}
                $range.FormulaR1C1='="'+$prefix+'"&TEXT(ROW()-1+'+$offset+',"000000")&REPT("x",'+($Definition.charactersPerCell-8)+')'
                $range.Calculate()
            }
        }
        $sentinel=$Sheet.Range('Z1')
        try{$sentinel.Value2='OUTSIDE_SELECTED_LIST'}finally{Release-Com $sentinel}
        $first=Cell-Text $Sheet 'A1';$last=Cell-Text $Sheet ('A'+$count)
        if($Definition.distribution -eq 'maxchars'){
            Check 'fixture-maxchars' ($first.Length -eq 4096 -and $last.Length -eq 2880) @($first.Length,$last.Length) @(4096,2880)
        }else{
            Check 'fixture-lengths' ($first.Length -eq $Definition.charactersPerCell -and $last.Length -eq $Definition.charactersPerCell) @($first.Length,$last.Length) $Definition.charactersPerCell
        }
        if($Definition.distribution -in @('disjoint','overlap','numeric-expansion')){
            Check 'fixture-distinct-endpoints' ($first -cne $last) $true $true
        }
    }finally{Release-Com $range}
}
function Close-OwnedBook($Book){
    if($null -eq $Book){return}
    $Book.Close($false)
    [void]$ownedBooks.Remove($Book)
    Release-Com $Book
}
Save-Evidence
try{
    if(-not ('SlcCapacityIdentity' -as [type])){
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SlcCapacityIdentity {
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
}
'@
    }
    # Recheck immediately before creation; never attach to a user's existing Excel.
    $prior=@(Get-Process -Name EXCEL -ErrorAction SilentlyContinue | ForEach-Object Id)
    if($prior.Count){throw 'Excel started during preflight; no COM application was created.'}
    $creationUtc=[DateTime]::UtcNow
    $excel=New-Object -ComObject Excel.Application
    [uint32]$actualPid=0
    [void][SlcCapacityIdentity]::GetWindowThreadProcessId([IntPtr]$excel.Hwnd,[ref]$actualPid)
    if($actualPid -eq 0 -or $prior -contains $actualPid){throw 'COM process ownership is not established; do not quit this application.'}
    $process=Get-Process -Id $actualPid -ErrorAction Stop
    try{
        if($process.StartTime.ToUniversalTime() -lt $creationUtc.AddSeconds(-2)){throw 'Excel process predates this test; no application changes made.'}
        $ownedPid=[int]$actualPid;$ownedStartTicks=$process.StartTime.ToUniversalTime().Ticks
        $report.owner=[ordered]@{pid=$ownedPid;startedUtc=$process.StartTime.ToUniversalTime().ToString('o');hwnd=[long]$excel.Hwnd}
    }finally{$process.Dispose()}
    $excel.AutomationSecurity=2
    $excel.Visible=$true
    $report.owner['version']=[string]$excel.Version
    $report.owner['build']=[string]$excel.Build
    $report.owner['operatingSystem']=[string]$excel.OperatingSystem
    Save-Evidence
    # A normally configured COM session may already contain this exact add-in.
    # Any other workbook is preserved, and the test refuses to proceed.
    if([int]$excel.Workbooks.Count -eq 1){
        $existing=$excel.Workbooks.Item(1)
        if([IO.Path]::GetFullPath([string]$existing.FullName) -ieq $addin -and [bool]$existing.IsAddin){
            $addbook=$existing;$ownedBooks.Add($addbook)
        }else{Release-Com $existing;throw 'Unexpected auto-opened workbook; no test workbooks were created.'}
    }elseif([int]$excel.Workbooks.Count -ne 0){
        throw 'Unexpected auto-opened workbooks; no test workbooks were created.'
    }else{
        $addbook=$excel.Workbooks.Open($addin,0,$true)
        $ownedBooks.Add($addbook)
    }
    Check 'loaded-exact-path' ([IO.Path]::GetFullPath([string]$addbook.FullName) -ieq $addin) ([string]$addbook.FullName) $addin
    Check 'automation-security' ([int]$excel.AutomationSecurity -eq 2) ([int]$excel.AutomationSecurity) 2
    $report['version']=[string]$excel.Run(($qualified+'SLC_Version'))
    $report['releaseVersion']=[string]$excel.Run(($qualified+'SLC_ReleaseVersion'))
    $report.builtIn=[string]$excel.Run(($qualified+'SLC_TestAll'))
    Check 'built-in-integration' ($report.builtIn.StartsWith('PASS:')) $report.builtIn 'PASS: normalization + Excel integration checks'
    Assert-WorkbookBound
    foreach($id in $caseIds){
        $definition=$catalog[$id]
        $activeCase=[ordered]@{
            id=$id;status='STARTED';phase='prepare';startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null
            definition=$definition;measurements=@();sourceSha256Before=$null;sourceSha256After=$null
            originalSavedBefore=$null;originalSavedAfter=$null;settingsBefore=$null;settingsAfter=$null
            menuBefore=$null;menuAfterCapture=$null;menuAfter=$null;actualSummary=$null;actualOutputRows=$null;error=$null
            workbooksBeforeInvoke=@()
        }
        $caseResults.Add($activeCase)
        Save-Evidence
        $sourcePath=Join-Path $output ($id+'-source.xlsx')
        try{
            $null=$excel.Run(($qualified+'SLC_Clear'))
            $activeCase.menuBefore=Get-Menu
            Check 'initial-capture-menu' ($activeCase.menuBefore -match 'slc68CellCapture' -and $activeCase.menuBefore -notmatch 'slc68CellCompare') $activeCase.menuBefore 'capture command only'
            $source=$excel.Workbooks.Add(-4167);$ownedBooks.Add($source)
            $sheetA=$source.Worksheets.Item(1);$sheetA.Name='SyntheticA'
            $sheetB=$source.Worksheets.Add();$sheetB.Name='SyntheticB'
            Make-Values $sheetA $definition $false
            Make-Values $sheetB $definition $true
            $null=$source.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$source,@([string]$sourcePath,[int]51))
            $activeCase.sourceSha256Before=Get-SharedHash $sourcePath
            $activeCase.originalSavedBefore=[bool]$source.Saved
            $activeCase.settingsBefore=Get-Settings
            $rangeA=$sheetA.Range('A1:A'+$definition.cellsPerList)
            $rangeB=$sheetB.Range('A1:A'+$definition.cellsPerList)
            $sheetA.Activate();$rangeA.Select()
            Assert-WorkbookBound
            Invoke-Public 'capture' $definition.captureWarningExpected
            $activeCase.menuAfterCapture=Get-Menu
            $expectedCount=$definition.cellsPerList.ToString('#,##0')
            Check 'captured-menu-count' ($activeCase.menuAfterCapture -match 'slc68CellCompare' -and $activeCase.menuAfterCapture.Contains($expectedCount+'개 항목')) $activeCase.menuAfterCapture ($expectedCount+' items and compare command')
            Check 'capture-settings-restored' (((Get-Settings) | ConvertTo-Json -Compress) -ceq ($activeCase.settingsBefore | ConvertTo-Json -Compress)) (Get-Settings) $activeCase.settingsBefore
            $sheetB.Activate();$rangeB.Select()
            Invoke-Public 'read-compare-output' $definition.compareWarningExpected
            $result=Get-VerifiedNewResult $activeCase.workbooksBeforeInvoke
            $ownedBooks.Add($result)
            Check 'new-result' $true 'one new unsaved workbook with exact product sheet/title; prior known set preserved' $true
            Assert-WorkbookBound
            $resultSheet=$result.Worksheets.Item(1)
            $activeCase.actualSummary=Cell-Text $resultSheet 'B4'
            $count=$definition.cellsPerList;$matched=$definition.expectedMatched;$excess=$count-$matched
            $remainingLabel=if($LegacyWording){'잔여'}else{'남은 항목'}
            $expected='첫 번째 목록: '+$count+'개 항목 / 두 번째 목록: '+$count+'개 항목 / 일치 '+$matched+'개 / 첫 번째 목록 '+$remainingLabel+' '+$excess+'개 / 두 번째 목록 '+$remainingLabel+' '+$excess+'개'
            Check 'literal-summary' ($activeCase.actualSummary -ceq $expected) $activeCase.actualSummary $expected
            $used=$resultSheet.UsedRange
            try{
                $activeCase.actualOutputRows=[int]$used.Rows.Count-8
                Check 'literal-output-rows' ($activeCase.actualOutputRows -eq $definition.expectedRows) $activeCase.actualOutputRows $definition.expectedRows
                Check 'no-output-formulas' ($used.HasFormula -eq $false) $used.HasFormula $false
            }finally{Release-Com $used}
            $activeCase.menuAfter=Get-Menu
            Check 'menu-reset' ($activeCase.menuAfter -ceq $activeCase.menuBefore) $activeCase.menuAfter $activeCase.menuBefore
            $activeCase.status='PASS'
        }catch{
            $activeCase.status='FAIL';$activeCase.error=$_.Exception.Message
            throw
        }finally{
            $activeCase.phase='verification-and-cleanup'
            if($null -ne $source -and $null -ne $activeCase.sourceSha256Before){
                try{
                    $activeCase.sourceSha256After=Get-SharedHash $sourcePath
                    Check 'source-file-hash' ($activeCase.sourceSha256After -ceq $activeCase.sourceSha256Before) $activeCase.sourceSha256After $activeCase.sourceSha256Before -Continue
                    $activeCase.originalSavedAfter=[bool]$source.Saved
                    Check 'source-saved-state' ($activeCase.originalSavedAfter -eq $activeCase.originalSavedBefore) $activeCase.originalSavedAfter $activeCase.originalSavedBefore -Continue
                    $activeCase.settingsAfter=Get-Settings
                    Check 'final-settings-restored' (($activeCase.settingsAfter | ConvertTo-Json -Compress) -ceq ($activeCase.settingsBefore | ConvertTo-Json -Compress)) $activeCase.settingsAfter $activeCase.settingsBefore -Continue
                    $activeCase.menuAfter=Get-Menu
                }catch{$cleanupErrors.Add($id+' verification: '+$_.Exception.Message);$activeCase.status='FAIL'}
            }
            foreach($value in @($resultSheet,$rangeA,$rangeB,$sheetA,$sheetB)){try{Release-Com $value}catch{$cleanupErrors.Add($id+' COM release: '+$_.Exception.Message)}}
            $resultSheet=$null;$rangeA=$null;$rangeB=$null;$sheetA=$null;$sheetB=$null
            foreach($book in @($result,$source)){try{Close-OwnedBook $book}catch{$cleanupErrors.Add($id+' workbook cleanup: '+$_.Exception.Message);$activeCase.status='FAIL'}}
            $result=$null;$source=$null
            if(@($checks | Where-Object {$_.case -eq $id -and $_.status -eq 'FAIL'}).Count){$activeCase.status='FAIL'}
            $activeCase.phase='complete';$activeCase.finishedUtc=[DateTime]::UtcNow.ToString('o')
            Save-Evidence
            [GC]::Collect();[GC]::WaitForPendingFinalizers()
        }
        if($activeCase.status -ne 'PASS'){throw ('Case failed: '+$id)}
    }
}catch{
    $failure=$_.Exception.Message;$report.error=$failure
}finally{
    $activeCase=$null
    for($i=$ownedBooks.Count-1;$i -ge 0;$i--){
        $book=$ownedBooks[$i]
        try{Close-OwnedBook $book}catch{$cleanupErrors.Add('Final workbook cleanup: '+$_.Exception.Message)}
    }
    $addbook=$null
    if($ownedPid -ne 0 -and $null -ne $excel){
        try{
            $process=Get-Process -Id $ownedPid -ErrorAction SilentlyContinue
            if($null -ne $process){
                try{if($process.StartTime.ToUniversalTime().Ticks -ne $ownedStartTicks){throw 'Process identity changed; Quit refused.'}}finally{$process.Dispose()}
                if([int]$excel.Workbooks.Count -ne 0){throw 'Unexpected workbook remains; Quit refused to preserve it.'}
                $excel.Quit()
            }
        }catch{$cleanupErrors.Add($_.Exception.Message)}
    }
    try{Release-Com $excel}catch{$cleanupErrors.Add('Application COM release: '+$_.Exception.Message)}
    $excel=$null
    [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
    if($ownedPid -ne 0){
        $exitTimer=[Diagnostics.Stopwatch]::StartNew()
        do{
            $remaining=Get-Process -Id $ownedPid -ErrorAction SilentlyContinue
            $sameProcess=$false
            if($null -ne $remaining){try{$sameProcess=($remaining.StartTime.ToUniversalTime().Ticks -eq $ownedStartTicks)}finally{$remaining.Dispose()}}
            if(-not $sameProcess){break}
            Start-Sleep -Milliseconds 100
        }while($exitTimer.Elapsed.TotalSeconds -lt 3)
        $report['ownedExcelExited']=(-not $sameProcess)
        if($sameProcess){$cleanupErrors.Add('Owned Excel is still running after normal Quit; no process was killed.')}
    }
    try{
        $report.addinSha256After=(Get-FileHash -LiteralPath $addin -Algorithm SHA256).Hash.ToLowerInvariant()
        Check 'addin-file-unchanged' ($report.addinSha256After -ceq $addinHashBefore) $report.addinSha256After $addinHashBefore -Continue
    }catch{$cleanupErrors.Add('Add-in hash verification: '+$_.Exception.Message)}
    $hasFailure=($null -ne $failure -or $cleanupErrors.Count -gt 0 -or @($checks | Where-Object status -eq 'FAIL').Count -gt 0 -or $caseResults.Count -ne $caseIds.Count)
    $report.status=if($hasFailure){'FAIL'}else{'PASS'}
    $report.finishedUtc=[DateTime]::UtcNow.ToString('o')
    Save-Evidence
}
Write-Output ('Capacity matrix '+$report.status+': '+$caseResults.Count+' / '+$caseIds.Count+' cases. '+(Join-Path $output 'capacity.json'))
if($report.status -ne 'PASS'){exit 1}
