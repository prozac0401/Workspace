[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AddinPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateSet('Compare','Replace')][string]$Operation='Compare',
    [switch]$LegacyWording
)
# Owns synthetic Excel fixtures only. No keyboard/dialog responder, VBA injection,
# policy changes or forced process termination. An external native observer must
# supply warning/Esc/dialog interaction and classify cancellation separately.
# Run under an external bounded supervisor: COM calls may wait for user dialogs.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){
    throw 'Run on Windows in a Windows PowerShell STA process.'
}
$addin=[IO.Path]::GetFullPath($AddinPath)
if(-not (Test-Path -LiteralPath $addin -PathType Leaf) -or [IO.Path]::GetExtension($addin) -ine '.xlam'){
    throw 'An existing built XLAM is required.'
}
$output=[IO.Path]::GetFullPath($OutputDirectory)
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$roots=@([IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts')),[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../artifacts')))
$inside=$false
foreach($root in $roots){if($output.StartsWith($root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){$inside=$true}}
if(-not $inside){throw 'Keep private evidence below repository artifacts or tool artifacts.'}
if(Test-Path -LiteralPath $output){throw 'Use a new evidence directory; existing evidence is preserved.'}
$ancestor=Split-Path -Parent $output
while($ancestor){
    if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor).Attributes -band [IO.FileAttributes]::ReparsePoint)){
        throw 'Evidence paths must not traverse a reparse point.'
    }
    $ancestor=Split-Path -Parent $ancestor
}
if(@(Get-Process -Name EXCEL -ErrorAction SilentlyContinue).Count){throw 'Existing Excel detected; nothing was attached or closed.'}
[void][IO.Directory]::CreateDirectory($output)
$signal=Join-Path $output 'processing.signal'
# The external driver creates this ONLY after accepting the native warning.
if(Test-Path -LiteralPath $signal){throw 'processing.signal must be absent before observation starts.'}
$utf8=New-Object Text.UTF8Encoding($false)
$qualified="'"+([IO.Path]::GetFileName($addin)).Replace("'","''")+"'!"
$checks=[Collections.Generic.List[object]]::new()
$ownedBooks=[Collections.Generic.List[object]]::new()
$cleanupErrors=[Collections.Generic.List[string]]::new()
$excel=$null;$addbook=$null;$source=$null;$sheet=$null;$baseline=$null;$large=$null
$priorResult=$null;$followup=$null;$largeResult=$null;$ownedPid=0;$ownedStartTicks=0L
$failure=$null;$sourcePath=Join-Path $output 'Synthetic-Esc-Source.xlsx'
$report=[ordered]@{
    schemaVersion=1;status='STARTED';phase='preflight';operation=$Operation;legacyWording=[bool]$LegacyWording
    testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    resultOwnershipScope='A new unsaved workbook, exact product sheet/title, and unchanged known workbook set are required. This cannot distinguish a third-party add-in deliberately producing an identical workbook.'
    startedUtc=[DateTime]::UtcNow.ToString('o');finishedUtc=$null;owner=$null;version=$null;releaseVersion=$null
    addinSha256Before=(Get-FileHash -LiteralPath $addin -Algorithm SHA256).Hash.ToLowerInvariant();addinSha256After=$null
    sourcePath=$sourcePath;sourceHashBefore=$null;sourceHashAfter=$null;sourceSavedBefore=$null;sourceSavedAfter=$null
    menuBefore=$null;menuAfter=$null;settingsBefore=$null;settingsAfter=$null
    booksBefore=$null;booksAfter=$null;previousResultName=$null;previousResultSentinelBefore=$null
    workbooksBeforeLargeOperation=@()
    previousResultSentinelAfter=$null;previousResultSavedBefore=$null;previousResultSavedAfter=$null
    largeOperationStartedUtc=$null;largeOperationReturnedUtc=$null;largeOperationWallMillisecondsIncludingDialogs=$null
    processingSignalRemoved=$false;macroError=$null;outcome='NOT_RETURNED';pendingAfter=$null
    resultSummary=$null;resultRows=$null;followupBaselineResult=$null
    nativeEscVerified=$false;cancellationVerdict='NOT_CLASSIFIED_BY_HELPER'
    observerRequired='Combine outcome with independently observed warning acceptance, in-progress Esc delivery and native response dialog.'
    checks=@();cleanupErrors=@();error=$null
}
function Save-Evidence {
    $report.checks=@($checks.ToArray());$report.cleanupErrors=@($cleanupErrors.ToArray())
    [IO.File]::WriteAllText((Join-Path $output 'esc.json'),($report | ConvertTo-Json -Depth 12),$utf8)
}
function Release-Com($Value){
    if($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)){
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)
    }
}
function Check([string]$Id,[bool]$Passed,$Actual,$Expected){
    $checks.Add([pscustomobject][ordered]@{id=$Id;status=if($Passed){'PASS'}else{'FAIL'};actual=$Actual;expected=$Expected})
    Save-Evidence
    Write-Host ($Id+': '+$Passed)
    if(-not $Passed){throw ('Assertion failed: '+$Id)}
}
function Shared-Hash([string]$Path){
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try{return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant()}finally{$stream.Dispose()}
}
function Settings {
    return [ordered]@{
        screenUpdating=[bool]$excel.ScreenUpdating;enableEvents=[bool]$excel.EnableEvents;interactive=[bool]$excel.Interactive
        enableCancelKey=[int]$excel.EnableCancelKey;calculation=[int]$excel.Calculation;displayAlerts=[bool]$excel.DisplayAlerts
        automationSecurity=[int]$excel.AutomationSecurity
    }
}
function Menu {return [string]$excel.Run(($qualified+'SLC_MenuXml'),'Cell')}
function Cell-Text($Sheet,[string]$Address){
    $cell=$Sheet.Range($Address)
    try{return [string]$cell.Value2}finally{Release-Com $cell}
}
function Baseline-Summary {
    $label=if($LegacyWording){'잔여'}else{'남은 항목'}
    return ('첫 번째 목록: 42개 항목 / 두 번째 목록: 42개 항목 / 일치 42개 / 첫 번째 목록 '+$label+' 0개 / 두 번째 목록 '+$label+' 0개')
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
function Own-NewResult([string]$Label,[object[]]$Before){
    $after=[Collections.Generic.List[object]]::new()
    for($index=1;$index -le [int]$excel.Workbooks.Count;$index++){
        $book=$excel.Workbooks.Item($index)
        $after.Add([pscustomobject]@{name=[string]$book.Name;fullName=[string]$book.FullName})
    }
    if($after.Count -ne $Before.Count+1){throw ($Label+': expected exactly one additional workbook; preserving unrecognized workbooks.')}
    foreach($entry in $Before){
        if(@($after | Where-Object {$_.name -ceq $entry.name -and $_.fullName -ceq $entry.fullName}).Count -ne 1){throw ($Label+': a previously known workbook changed or disappeared; preserving unrecognized workbooks.')}
    }
    $new=@($after | Where-Object {$Before.name -cnotcontains $_.name})
    if($new.Count -ne 1){throw ($Label+': ambiguous new workbook; preserving unrecognized workbooks.')}
    $book=$excel.ActiveWorkbook;$resultSheet=$null
    try{
        if([string]$book.Name -cne $new[0].name -or [string]$book.FullName -cne $new[0].fullName -or [string]$book.Path -cne '' -or [bool]$book.Saved){throw ($Label+': active workbook is not the new unsaved result; preserving it.')}
        if([int]$book.Sheets.Count -ne 1 -or [int]$book.Worksheets.Count -ne 1){throw ($Label+': unexpected result workbook shape; preserving it.')}
        $resultSheet=$book.Worksheets.Item(1)
        if([string]$resultSheet.Name -cne '명단비교_결과' -or (Cell-Text $resultSheet 'A1') -cne '명단 비교 결과'){throw ($Label+': result sheet or literal title mismatch; preserving the unrecognized workbook.')}
        $ownedBooks.Add($book)
        return ,$book
    }finally{
        Release-Com $resultSheet
        # The candidate remains borrowed unless accepted above. An unrecognized
        # workbook is never closed or force-released by this read-only probe.
    }
}
function Check-Preservation {
    if($null -eq $source -or $null -eq $report.sourceHashBefore){return}
    $report.sourceHashAfter=Shared-Hash $sourcePath
    $report.sourceSavedAfter=[bool]$source.Saved
    $report.settingsAfter=Settings
    $priorSheet=$priorResult.Worksheets.Item(1)
    try{$report.previousResultSentinelAfter=Cell-Text $priorSheet 'T1'}finally{Release-Com $priorSheet}
    $report.previousResultSavedAfter=[bool]$priorResult.Saved
    # Record every preservation assertion before throwing, so one mismatch does
    # not hide the state of the other independent protections.
    $observations=@(
        @('source-file-hash',($report.sourceHashAfter -ceq $report.sourceHashBefore),$report.sourceHashAfter,$report.sourceHashBefore),
        @('source-saved-state',($report.sourceSavedAfter -eq $report.sourceSavedBefore),$report.sourceSavedAfter,$report.sourceSavedBefore),
        @('previous-result-sentinel',($report.previousResultSentinelAfter -ceq 'USER_EDIT_SENTINEL'),$report.previousResultSentinelAfter,'USER_EDIT_SENTINEL'),
        @('previous-result-unsaved',($report.previousResultSavedAfter -eq $report.previousResultSavedBefore),$report.previousResultSavedAfter,$report.previousResultSavedBefore),
        @('settings-restored',(($report.settingsAfter | ConvertTo-Json -Compress) -ceq ($report.settingsBefore | ConvertTo-Json -Compress)),$report.settingsAfter,$report.settingsBefore)
    )
    foreach($observation in $observations){
        $checks.Add([pscustomobject][ordered]@{id=$observation[0];status=if($observation[1]){'PASS'}else{'FAIL'};actual=$observation[2];expected=$observation[3]})
    }
    Save-Evidence
    if(@($checks | Where-Object status -eq 'FAIL').Count){throw 'One or more preservation assertions failed.'}
}
function Close-OwnedBook($Book){
    if($null -eq $Book){return}
    $Book.Close($false);[void]$ownedBooks.Remove($Book);Release-Com $Book
}
Save-Evidence
try{
    if(-not ('SlcEscIdentity' -as [type])){
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SlcEscIdentity {
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
}
'@
    }
    $priorPids=@(Get-Process -Name EXCEL -ErrorAction SilentlyContinue | ForEach-Object Id)
    if($priorPids.Count){throw 'Excel started during preflight; no COM application was created.'}
    $creationUtc=[DateTime]::UtcNow
    $excel=New-Object -ComObject Excel.Application
    [uint32]$actualPid=0
    [void][SlcEscIdentity]::GetWindowThreadProcessId([IntPtr]$excel.Hwnd,[ref]$actualPid)
    if($actualPid -eq 0 -or $priorPids -contains $actualPid){throw 'New Excel ownership is not established; Quit refused.'}
    $process=Get-Process -Id $actualPid -ErrorAction Stop
    try{
        if($process.StartTime.ToUniversalTime() -lt $creationUtc.AddSeconds(-2)){throw 'Excel predates this test; no application changes made.'}
        $ownedPid=[int]$actualPid;$ownedStartTicks=$process.StartTime.ToUniversalTime().Ticks
        $report.owner=[ordered]@{pid=$ownedPid;startTicks=$ownedStartTicks;startedUtc=$process.StartTime.ToUniversalTime().ToString('o');hwnd=[long]$excel.Hwnd}
    }finally{$process.Dispose()}
    $excel.AutomationSecurity=2;$excel.Visible=$true
    $report.owner['version']=[string]$excel.Version;$report.owner['build']=[string]$excel.Build
    if([int]$excel.Workbooks.Count -eq 1){
        $existing=$excel.Workbooks.Item(1)
        if([IO.Path]::GetFullPath([string]$existing.FullName) -ieq $addin -and [bool]$existing.IsAddin){
            $addbook=$existing;$ownedBooks.Add($addbook)
        }else{Release-Com $existing;throw 'Unexpected auto-opened workbook; preserving it.'}
    }elseif([int]$excel.Workbooks.Count -ne 0){throw 'Unexpected auto-opened workbooks; preserving them.'}
    else{$addbook=$excel.Workbooks.Open($addin,0,$true);$ownedBooks.Add($addbook)}
    Check 'exact-addin-path' ([IO.Path]::GetFullPath([string]$addbook.FullName) -ieq $addin) ([string]$addbook.FullName) $addin
    $report.version=[string]$excel.Run(($qualified+'SLC_Version'))
    $report.releaseVersion=[string]$excel.Run(($qualified+'SLC_ReleaseVersion'))
    $report.phase='prepare-synthetic-fixtures';Save-Evidence
    $source=$excel.Workbooks.Add(-4167);$ownedBooks.Add($source)
    $sheet=$source.Worksheets.Item(1);$sheet.Name='SyntheticEsc'
    $baseline=$sheet.Range('A1:A42');$baseline.Value2='baseline'
    $large=$sheet.Range('C1:C100000')
    $large.FormulaR1C1='="candidate_"&TEXT(ROW()-1,"000000")&REPT("x",32)'
    $large.Calculate()
    $first=Cell-Text $sheet 'C1';$last=Cell-Text $sheet 'C100000'
    Check 'large-fixture-first' ($first -ceq ('candidate_000000'+('x'*32))) $first ('candidate_000000'+('x'*32))
    Check 'large-fixture-last' ($last -ceq ('candidate_099999'+('x'*32))) $last ('candidate_099999'+('x'*32))
    Check 'large-fixture-length' ($first.Length -eq 48 -and $last.Length -eq 48) @($first.Length,$last.Length) @(48,48)
    $null=$source.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$source,@([string]$sourcePath,[int]51))
    $null=$excel.Run(($qualified+'SLC_Clear'))
    $source.Activate();$baseline.Select();$null=$excel.Run(($qualified+'SLC_Run'))
    $initialResultBefore=@(Get-KnownWorkbookSnapshot)
    $null=$excel.Run(($qualified+'SLC_Run'))
    $priorResult=Own-NewResult 'initial duplicate comparison' $initialResultBefore
    $priorSheet=$priorResult.Worksheets.Item(1)
    try{
        $priorSummary=Cell-Text $priorSheet 'B4'
        Check 'prior-result-literal-summary' ($priorSummary -ceq (Baseline-Summary)) $priorSummary (Baseline-Summary)
        $sentinel=$priorSheet.Range('T1')
        try{$sentinel.Value2='USER_EDIT_SENTINEL'}finally{Release-Com $sentinel}
        $report.previousResultSentinelBefore=Cell-Text $priorSheet 'T1'
    }finally{Release-Com $priorSheet}
    $report.previousResultName=[string]$priorResult.Name
    $report.previousResultSavedBefore=[bool]$priorResult.Saved
    Check 'prior-result-unsaved-before' (-not $report.previousResultSavedBefore) $report.previousResultSavedBefore $false
    $source.Activate();$baseline.Select();$null=$excel.Run(($qualified+'SLC_Run'))
    $report.menuBefore=Menu
    Check 'baseline-42-captured' ($report.menuBefore -match 'slc68CellCompare' -and $report.menuBefore.Contains('42개 항목')) $report.menuBefore '42-item pending snapshot'
    $report.settingsBefore=Settings;$report.sourceHashBefore=Shared-Hash $sourcePath
    $report.sourceSavedBefore=[bool]$source.Saved;$report.booksBefore=[int]$excel.Workbooks.Count
    $report.workbooksBeforeLargeOperation=@(Get-KnownWorkbookSnapshot)
    $large.Select()
    $report.phase='waiting-large-operation';$report.largeOperationStartedUtc=[DateTime]::UtcNow.ToString('o')
    Save-Evidence
    Write-Host ('WAITING_FOR_NATIVE_DIALOG '+$Operation+' 100000 unique 48-character cells; external observer owns warning acceptance and Esc input.')
    $timer=[Diagnostics.Stopwatch]::StartNew()
    try{
        $macro=if($Operation -eq 'Replace'){'SLC_Replace'}else{'SLC_Run'}
        $null=$excel.Run(($qualified+$macro))
    }catch{$report.macroError=$_.Exception.Message}
    finally{
        # This exact trial signal is the only file removed by the helper. It is
        # created by the observer after native warning acceptance, never here.
        if(Test-Path -LiteralPath $signal -PathType Leaf){Remove-Item -LiteralPath $signal -Force;$report.processingSignalRemoved=$true}
        $timer.Stop();$report.largeOperationReturnedUtc=[DateTime]::UtcNow.ToString('o')
        $report.largeOperationWallMillisecondsIncludingDialogs=$timer.Elapsed.TotalMilliseconds
        $report.phase='large-operation-returned';Save-Evidence
    }
    $report.phase='reading-menu-after-large-operation';Save-Evidence
    $report.menuAfter=Menu
    $report.phase='reading-workbook-count-after-large-operation';Save-Evidence
    $report.booksAfter=[int]$excel.Workbooks.Count
    $report.phase='classifying-large-operation';Save-Evidence
    if($report.menuAfter -ceq $report.menuBefore){
        $report.phase='reading-preserved-workbook-snapshot';Save-Evidence
        $null=@(Get-KnownWorkbookSnapshot)
        $report.phase='preserved-workbook-snapshot-read';Save-Evidence
        $report.outcome='BASELINE_42_PRESERVED';$report.pendingAfter=42
        Check 'no-new-workbook-after-preservation' ($report.booksAfter -eq $report.booksBefore) $report.booksAfter $report.booksBefore
    }elseif($Operation -eq 'Replace' -and $report.menuAfter -match 'slc68CellCompare' -and $report.menuAfter.Contains('100,000개 항목')){
        $report.phase='reading-replacement-workbook-snapshot';Save-Evidence
        $null=@(Get-KnownWorkbookSnapshot)
        $report.phase='replacement-workbook-snapshot-read';Save-Evidence
        $report.outcome='REPLACEMENT_100000_COMPLETED';$report.pendingAfter=100000
        Check 'replacement-book-count' ($report.booksAfter -eq $report.booksBefore) $report.booksAfter $report.booksBefore
    }elseif($Operation -eq 'Compare' -and $report.menuAfter -match 'slc68CellCapture' -and $report.menuAfter -notmatch 'slc68CellCompare'){
        $report.phase='verifying-large-comparison-workbook';Save-Evidence
        $largeResult=Own-NewResult 'large comparison' $report.workbooksBeforeLargeOperation
        $report.phase='large-comparison-workbook-verified';Save-Evidence
        $report.outcome='COMPARISON_COMPLETED';$report.pendingAfter=0
        $resultSheet=$largeResult.Worksheets.Item(1)
        try{
            $report.resultSummary=Cell-Text $resultSheet 'B4'
            $used=$resultSheet.UsedRange
            try{$report.resultRows=[int]$used.Rows.Count-8;Check 'large-result-no-formulas' ($used.HasFormula -eq $false) $used.HasFormula $false}finally{Release-Com $used}
            $label=if($LegacyWording){'잔여'}else{'남은 항목'}
            $expected='첫 번째 목록: 42개 항목 / 두 번째 목록: 100000개 항목 / 일치 0개 / 첫 번째 목록 '+$label+' 42개 / 두 번째 목록 '+$label+' 100000개'
            Check 'large-result-literal-summary' ($report.resultSummary -ceq $expected) $report.resultSummary $expected
            Check 'large-result-row-count' ($report.resultRows -eq 100001) $report.resultRows 100001
        }finally{Release-Com $resultSheet}
        Check 'comparison-book-count' ($report.booksAfter -eq $report.booksBefore+1) $report.booksAfter ($report.booksBefore+1)
    }else{$report.outcome='UNCLASSIFIED_STATE';throw 'Returned macro state did not match preserved baseline, completed replacement or completed comparison.'}
    Check-Preservation
    if($report.outcome -eq 'BASELINE_42_PRESERVED'){
        $report.phase='verify-preserved-baseline';Save-Evidence
        $source.Activate();$baseline.Select();$followupBefore=@(Get-KnownWorkbookSnapshot)
        $null=$excel.Run(($qualified+'SLC_Run'))
        $followup=Own-NewResult 'preserved baseline follow-up' $followupBefore
        $followSheet=$followup.Worksheets.Item(1)
        try{
            $report.followupBaselineResult=Cell-Text $followSheet 'B4'
            Check 'preserved-baseline-literal-result' ($report.followupBaselineResult -ceq (Baseline-Summary)) $report.followupBaselineResult (Baseline-Summary)
            $used=$followSheet.UsedRange
            try{Check 'followup-no-formulas' ($used.HasFormula -eq $false) $used.HasFormula $false}finally{Release-Com $used}
        }finally{Release-Com $followSheet}
        Check-Preservation
    }
    if($null -ne $report.macroError){throw ('Large macro COM error: '+$report.macroError)}
}catch{$failure=$_.Exception.Message;$report.error=$failure}
finally{
    $report.phase='cleanup';Save-Evidence
    foreach($value in @($baseline,$large,$sheet)){try{Release-Com $value}catch{$cleanupErrors.Add('COM release: '+$_.Exception.Message)}}
    $baseline=$null;$large=$null;$sheet=$null
    for($i=$ownedBooks.Count-1;$i -ge 0;$i--){
        $book=$ownedBooks[$i]
        try{Close-OwnedBook $book}catch{$cleanupErrors.Add('Owned workbook cleanup: '+$_.Exception.Message)}
    }
    $addbook=$null;$source=$null;$priorResult=$null;$followup=$null;$largeResult=$null
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
    $excel=$null;[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
    if($ownedPid -ne 0){
        $exitTimer=[Diagnostics.Stopwatch]::StartNew()
        do{
            $remaining=Get-Process -Id $ownedPid -ErrorAction SilentlyContinue;$sameProcess=$false
            if($null -ne $remaining){try{$sameProcess=($remaining.StartTime.ToUniversalTime().Ticks -eq $ownedStartTicks)}finally{$remaining.Dispose()}}
            if(-not $sameProcess){break}
            Start-Sleep -Milliseconds 100
        }while($exitTimer.Elapsed.TotalSeconds -lt 10)
        $report['ownedExcelExitObservationSeconds']=$exitTimer.Elapsed.TotalSeconds
        $report['ownedExcelExited']=(-not $sameProcess)
        if($sameProcess){$cleanupErrors.Add('Owned Excel remains after normal Quit; no process was killed.')}
    }
    try{
        $report.addinSha256After=(Get-FileHash -LiteralPath $addin -Algorithm SHA256).Hash.ToLowerInvariant()
        if($report.addinSha256After -cne $report.addinSha256Before){$cleanupErrors.Add('Add-in file hash changed.')}
        if($null -ne $report.sourceHashBefore){
            $report.sourceHashAfter=Shared-Hash $sourcePath
            if($report.sourceHashAfter -cne $report.sourceHashBefore){$cleanupErrors.Add('Saved synthetic source file hash changed after cleanup.')}
        }
    }catch{$cleanupErrors.Add('Final file hash verification: '+$_.Exception.Message)}
    $report.status=if($null -ne $failure -or $cleanupErrors.Count -gt 0 -or @($checks | Where-Object status -eq 'FAIL').Count){'FAIL'}else{'OBSERVED'}
    $report.phase='complete';$report.finishedUtc=[DateTime]::UtcNow.ToString('o');Save-Evidence
}
Write-Output ('Esc retest '+$report.status+': '+$report.outcome+'. Cancellation requires independent native observer evidence. '+(Join-Path $output 'esc.json'))
if($report.status -eq 'FAIL'){exit 1}
