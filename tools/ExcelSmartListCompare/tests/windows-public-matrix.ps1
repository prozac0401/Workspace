[CmdletBinding()]
param([Parameter(Mandatory=$true)][int]$OwnedPid,[Parameter(Mandatory=$true)][string]$OutputDirectory,[string]$AddinPath=(Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare\ExcelSmartListCompare.xlam'))
# Public SLC_Run selections; literal expectations are independent of VBA helpers.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Use a new evidence directory.'}
[void](New-Item -ItemType Directory -Path $output)
Add-Type 'using System;using System.Runtime.InteropServices;public class SlcMatrixOwner { [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p); }'
$e=[Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application');[uint32]$p=0;[void][SlcMatrixOwner]::GetWindowThreadProcessId([IntPtr]$e.Hwnd,[ref]$p)
if($p -ne $OwnedPid){throw 'Different Excel; no workbook changes.'}
$results=[Collections.Generic.List[object]]::new()
$q="'ExcelSmartListCompare.xlam'!"
$ownedBooks=[Collections.Generic.List[object]]::new()
$previous=$null;$addbook=$null
$addin=[IO.Path]::GetFullPath($AddinPath)
function Release-Com($v){if($null -ne $v -and [Runtime.InteropServices.Marshal]::IsComObject($v)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($v)}}
function Get-KnownWorkbookSnapshot {
    $knownBooks=[Collections.Generic.List[object]]::new()
    foreach($knownBook in $ownedBooks){$knownBooks.Add($knownBook)}
    if($null -ne $addbook){$knownBooks.Add($addbook)}
    $known=@($knownBooks | ForEach-Object {[pscustomobject]@{name=[string]$_.Name;fullName=[string]$_.FullName}})
    $snapshot=[Collections.Generic.List[object]]::new()
    for($index=1;$index -le [int]$e.Workbooks.Count;$index++){
        # Borrowed workbook aliases remain usable until explicit owned cleanup.
        $book=$e.Workbooks.Item($index)
        $name=[string]$book.Name;$fullName=[string]$book.FullName
        if(@($known | Where-Object {$_.name -ceq $name -and $_.fullName -ceq $fullName}).Count -ne 1){throw 'Unexpected workbook; preserving it and stopping the test.'}
        $snapshot.Add([pscustomobject]@{name=$name;fullName=$fullName})
    }
    return $snapshot.ToArray()
}
function Get-VerifiedNewResult([object[]]$Before){
    $after=[Collections.Generic.List[object]]::new()
    for($index=1;$index -le [int]$e.Workbooks.Count;$index++){
        $book=$e.Workbooks.Item($index)
        $after.Add([pscustomobject]@{name=[string]$book.Name;fullName=[string]$book.FullName})
    }
    if($after.Count -ne $Before.Count+1){throw 'Expected exactly one additional workbook; preserving unrecognized workbooks.'}
    foreach($entry in $Before){
        if(@($after | Where-Object {$_.name -ceq $entry.name -and $_.fullName -ceq $entry.fullName}).Count -ne 1){throw 'A known workbook changed or disappeared; preserving unrecognized workbooks.'}
    }
    $beforeNames=@($Before | ForEach-Object {$_.name})
    $new=@($after | Where-Object {$beforeNames -cnotcontains $_.name})
    if($new.Count -ne 1){throw 'New result identity is ambiguous; preserving unrecognized workbooks.'}
    $book=$e.ActiveWorkbook;$tab=$null;$title=$null
    try{
        if([string]$book.Name -cne $new[0].name -or [string]$book.FullName -cne $new[0].fullName -or [string]$book.Path -cne '' -or [bool]$book.Saved){throw 'Active workbook is not the additional unsaved result; preserving it.'}
        if([int]$book.Sheets.Count -ne 1 -or [int]$book.Worksheets.Count -ne 1){throw 'Unexpected result workbook shape; preserving it.'}
        $tab=$book.Worksheets.Item(1);$title=$tab.Range('A1')
        if([string]$tab.Name -cne '명단비교_결과' -or [string]$title.Value2 -cne '명단 비교 결과'){throw 'Result sheet or title mismatch; preserving it.'}
        return ,$book
    }finally{
        Release-Com $title;Release-Com $tab
        # Candidate workbook aliases are never force-released by this probe.
    }
}
function Close-OwnedBook($v){
    if($null -eq $v){return}
    if(-not $ownedBooks.Contains($v)){throw 'Workbook ownership was not recorded; close refused.'}
    $v.Close($false)
    [void]$ownedBooks.Remove($v)
    Release-Com $v
}
function Fill($s,[string[]]$addresses,[string[]]$values){for($i=0;$i -lt $addresses.Count;$i++){$c=$s.Range($addresses[$i]);$c.NumberFormat='@';$c.Value2=$values[$i];Release-Com $c}}
try {
    $addbook=$e.Workbooks.Item('ExcelSmartListCompare.xlam')
    if([IO.Path]::GetFullPath([string]$addbook.FullName) -ine $addin -or -not [bool]$addbook.IsAddin){throw 'Loaded add-in differs from the exact requested XLAM; no macro was run.'}
    $null=@(Get-KnownWorkbookSnapshot)
    $caseNames=@('HORIZONTAL-VERTICAL','VERTICAL-HORIZONTAL','RECTANGLE-LINE','SINGLE-ONLY','MULTI-AREA','OVERLAP','WHOLE-ROW','WHOLE-COLUMN','HIDDEN-ROW','HIDDEN-COLUMN','AUTOFILTER-HEADER','TABLE-FILTER-TOTALS','MANUAL-CALCULATION','SAME-RANGE-SNAPSHOT')
    foreach($id in $caseNames){
        $null=@(Get-KnownWorkbookSnapshot)
        $null=$e.Run($q+'SLC_Clear')
        $null=@(Get-KnownWorkbookSnapshot)
        $book=$e.Workbooks.Add(-4167);$ownedBooks.Add($book)
        $a=$book.Worksheets.Item(1);$a.Name='A';$b=$book.Worksheets.Add();$b.Name='B'
        Fill $a @('A1','A2','A3','A4') @('one','one','two','three')
        Fill $b @('H1','H2','H3','H4') @('one','two','three','four')
        $ra=$a.Range('A1:A4');$rb=$b.Range('H1:H4');$expected='첫 번째 목록: 4개 항목 / 두 번째 목록: 4개 항목 / 일치 3개 / 첫 번째 목록 남은 항목 1개 / 두 번째 목록 남은 항목 1개'
        switch($id){
            'HORIZONTAL-VERTICAL' {$a.Cells.Clear();Fill $a @('A1','B1','C1','D1') @('one','one','two','three');$ra=$a.Range('A1:D1')}
            'VERTICAL-HORIZONTAL' {$b.Cells.Clear();Fill $b @('H1','I1','J1','K1') @('one','two','three','four');$rb=$b.Range('H1:K1')}
            'RECTANGLE-LINE' {$a.Cells.Clear();Fill $a @('A1','B1','A2','B2') @('one','one','two','three');$ra=$a.Range('A1:B2')}
            'SINGLE-ONLY' {$ra=$a.Range('A1');$rb=$b.Range('H2');$expected='첫 번째 목록: 1개 항목 / 두 번째 목록: 1개 항목 / 일치 0개 / 첫 번째 목록 남은 항목 1개 / 두 번째 목록 남은 항목 1개'}
            'MULTI-AREA' {$a.Cells.Clear();Fill $a @('A1','A2','C1','C2') @('one','one','two','three');$ra=$e.Union($a.Range('A1:A2'),$a.Range('C1:C2'))}
            'OVERLAP' {$ra=$e.Union($a.Range('A1:A3'),$a.Range('A2:A4'))}
            'WHOLE-ROW' {$a.Cells.Clear();Fill $a @('A1','B1','C1','D1') @('one','one','two','three');$ra=$a.Rows.Item(1)}
            'WHOLE-COLUMN' {$ra=$a.Columns.Item(1)}
            'HIDDEN-ROW' {$a.Rows.Item(3).Hidden=$true;$expected='첫 번째 목록: 3개 항목 / 두 번째 목록: 4개 항목 / 일치 2개 / 첫 번째 목록 남은 항목 1개 / 두 번째 목록 남은 항목 2개'}
            'HIDDEN-COLUMN' {$a.Cells.Clear();Fill $a @('A1','B1','C1','D1') @('one','one','two','three');$a.Columns.Item(3).Hidden=$true;$ra=$a.Range('A1:D1');$expected='첫 번째 목록: 3개 항목 / 두 번째 목록: 4개 항목 / 일치 2개 / 첫 번째 목록 남은 항목 1개 / 두 번째 목록 남은 항목 2개'}
            'AUTOFILTER-HEADER' {$a.Cells.Clear();Fill $a @('A1','A2','A3','A4','A5') @('heading','one','one','two','three');$null=$a.Range('A1:A5').AutoFilter(1,'<>two');$ra=$a.Range('A1:A5');$expected='첫 번째 목록: 3개 항목 / 두 번째 목록: 4개 항목 / 일치 2개 / 첫 번째 목록 남은 항목 1개 / 두 번째 목록 남은 항목 2개'}
            'TABLE-FILTER-TOTALS' {$a.Cells.Clear();Fill $a @('A1','A2','A3','A4','A5') @('heading','one','one','two','three');$lo=$a.ListObjects.Add(1,$a.Range('A1:A5'),[Type]::Missing,1);$lo.ShowTotals=$true;$null=$lo.Range.AutoFilter(1,'<>two');$ra=$lo.Range;$expected='첫 번째 목록: 3개 항목 / 두 번째 목록: 4개 항목 / 일치 2개 / 첫 번째 목록 남은 항목 1개 / 두 번째 목록 남은 항목 2개';Release-Com $lo}
        }
        $file=Join-Path $output ($id+'.xlsx')
        $null=$book.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$book,@([string]$file,[int]51))
        $oldCalculation=$e.Calculation
        if($id -eq 'MANUAL-CALCULATION'){$e.Calculation=-4135}
        $settings=@($e.ScreenUpdating,$e.EnableEvents,$e.Interactive,$e.EnableCancelKey,$e.Calculation)
        $a.Activate();$ra.Select();$null=@(Get-KnownWorkbookSnapshot);$null=$e.Run($q+'SLC_Run')
        if($id -eq 'SAME-RANGE-SNAPSHOT'){$a.Range('A4').Value2='changed';$rb=$ra;$b=$a;$expected='첫 번째 목록: 4개 항목 / 두 번째 목록: 4개 항목 / 일치 3개 / 첫 번째 목록 남은 항목 1개 / 두 번째 목록 남은 항목 1개'}
        $b.Activate();$rb.Select();$beforeCompare=@(Get-KnownWorkbookSnapshot);$null=$e.Run($q+'SLC_Run')
        $result=Get-VerifiedNewResult $beforeCompare
        if([string]$result.Name -eq [string]$book.Name){throw 'Expected a new result workbook.'}
        $ownedBooks.Add($result);$rs=$result.Worksheets.Item(1)
        $summary=[string]$rs.Range('B4').Value2;$noFormula=$rs.UsedRange.HasFormula -eq $false
        $settingsAfter=@($e.ScreenUpdating,$e.EnableEvents,$e.Interactive,$e.EnableCancelKey,$e.Calculation)
        $preserved=$true
        if($null -ne $previous){$preserved=[string]$previous.Worksheets.Item(1).Range('T1').Value2 -ceq 'USER_EDIT_SENTINEL'}
        $pass=$summary -ceq $expected -and $noFormula -and (($settings -join ',') -ceq ($settingsAfter -join ',')) -and $preserved
        $results.Add([ordered]@{id=$id;status=if($pass){'PASS'}else{'FAIL'};expected=$expected;actual=$summary;hasFormula=(-not $noFormula);settingsRestored=(($settings -join ',') -ceq ($settingsAfter -join ','));previousEditedResultPreserved=$preserved})
        $results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'public-matrix.json') -Encoding UTF8
        Write-Host ($id+': '+$pass)
        $e.Calculation=$oldCalculation
        $rs.Range('T1').Value2='USER_EDIT_SENTINEL'
        Release-Com $rs
        if(-not $pass){throw ('Public selection failed: '+$id)}
        # Keep one edited result for the NEXT operation's preservation check.
        # At most three synthetic books coexist, independent of case count.
        $sameRange=[object]::ReferenceEquals($ra,$rb)
        $sameSheet=[object]::ReferenceEquals($a,$b)
        Release-Com $ra
        if(-not $sameRange){Release-Com $rb}
        Release-Com $a
        if(-not $sameSheet){Release-Com $b}
        $ra=$null;$rb=$null;$a=$null;$b=$null;$rs=$null
        Close-OwnedBook $book
        $book=$null
        Close-OwnedBook $previous
        $previous=$result
        $results[$results.Count-1]['retainedOwnedBooks']=$ownedBooks.Count
        if($ownedBooks.Count -ne 1){throw 'Synthetic workbook retention exceeded the single-result bound.'}
        # Release temporary property RCWs after each small case, not 14 cases later.
        [GC]::Collect();[GC]::WaitForPendingFinalizers()
        $results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'public-matrix.json') -Encoding UTF8
    }
} catch {
    $results.Add([ordered]@{id='PUBLIC-EXECUTION';status='FAIL';actual=$_.Exception.Message;location=$_.ScriptStackTrace})
    throw
} finally {
    if($null -ne (Get-Variable oldCalculation -ErrorAction SilentlyContinue)){$e.Calculation=$oldCalculation}
    for($i=$ownedBooks.Count-1;$i -ge 0;$i--){
        $ownedBook=$ownedBooks[$i]
        try{Close-OwnedBook $ownedBook}
        catch{$results.Add([ordered]@{id='PUBLIC-CLEANUP';status='FAIL';actual=$_.Exception.Message});Release-Com $ownedBook}
    }
    # The add-in was already open in the supplied instance; never close it or Quit.
    Release-Com $addbook
    Release-Com $e
    $addbook=$null;$e=$null;$book=$null;$result=$null;$previous=$null
    [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
    $results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $output 'public-matrix.json') -Encoding UTF8
}
