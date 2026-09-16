[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$ExpectedXlamSha256,
    [string]$SetupPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Setup.ps1')
)
# Uses synthetic files in an owned Excel process. Requires an installed XLAM.
# Workbook.Activate fires real application events; no UI clicks are simulated.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$run=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $run){throw 'Use a fresh evidence directory.'}
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Existing Excel; no process changed.'}
$installed=Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare/ExcelSmartListCompare.xlam'
if((Get-FileHash -LiteralPath $installed).Hash -ine $ExpectedXlamSha256){throw 'Installed XLAM differs from the requested test subject.'}
[void](New-Item -ItemType Directory -Path $run)
$Root=Split-Path -Parent ([IO.Path]::GetFullPath($SetupPath))
$ast=[Management.Automation.Language.Parser]::ParseFile($SetupPath,[ref]$null,[ref]$null)
foreach($f in $ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)){
    . ([scriptblock]::Create($f.Extent.Text))
}
$script:Excel=$null;$script:ExcelVersion=$null;$script:ExcelProcess=$null
$script:ExcelBootstrap=$null;$script:ExcelSessionBook=$null
$records=New-Object 'System.Collections.Generic.List[object]'
function Check([string]$name,[bool]$ok){
    $records.Add([ordered]@{id=$name;status=$(if($ok){'PASS'}else{'FAIL'})})
    $records.ToArray()|ConvertTo-Json -Depth 6|Set-Content (Join-Path $run 'window-state.json') -Encoding UTF8
    if(-not $ok){throw ('Window-state assertion failed: '+$name)}
}
function Check-Controls($controls,[int]$count){
    $expected=if($count){'두 번째 목록 담아 비교'}else{'첫 번째 목록 담기'}
    $pending=if($count){'첫 번째 목록: '+$count+'개 항목'}else{''}
    $ok=($controls.Count -eq 5 -and
        [string]$controls.Item(1).Caption -ceq $expected -and
        [string]$controls.Item(2).Caption -ceq $pending -and
        [bool]$controls.Item(2).Visible -eq [bool]$count -and
        -not [bool]$controls.Item(2).Enabled -and
        [string]$controls.Item(3).Caption -ceq '첫 번째 목록 비우기' -and
        [string]$controls.Item(4).Caption -ceq '첫 번째 목록 바꾸기')
    if(-not $ok){
        $details=@(for($j=1;$j -le $controls.Count;$j++){
            $control=$controls.Item($j)
            [ordered]@{caption=[string]$control.Caption;tag=[string]$control.Tag;visible=[bool]$control.Visible;enabled=[bool]$control.Enabled}
            Release-Com $control
        })
        [ordered]@{expectedAction=$expected;expectedPending=$pending;actual=$details}|ConvertTo-Json -Depth 5|
            Set-Content (Join-Path $run 'mismatch.json') -Encoding UTF8
    }
    return $ok
}
function Check-Window([string]$phase,[int]$count){
    $barCount=0;$toolbarOk=$false
    for($i=1;$i -le $script:Excel.CommandBars.Count;$i++){
        $bar=$script:Excel.CommandBars.Item($i)
        if([string]$bar.Name -ceq 'SLC_68A45C44_Toolbar'){
            $barCount++;$toolbarOk=Check-Controls $bar.Controls $count
        }
        Release-Com $bar
    }
    [ordered]@{phase=$phase;toolbarCount=$barCount;toolbarStateMatches=$toolbarOk}|ConvertTo-Json|Set-Content (Join-Path $run 'latest-window.json') -Encoding UTF8
    Check ($phase+'/Toolbar') ($barCount -eq 1 -and $toolbarOk)
    foreach($name in @('Cell','Row','Column')){
        $bar=$script:Excel.CommandBars.Item($name);$found=0;$popupOk=$false
        for($i=1;$i -le $bar.Controls.Count;$i++){
            $popup=$bar.Controls.Item($i)
            if([string]$popup.Tag -ceq 'SLC_68A45C44_2026'){
                $found++;$popupOk=Check-Controls $popup.Controls $count
            }
            Release-Com $popup
        }
        Release-Com $bar
        Check ($phase+'/'+$name) ($found -eq 1 -and $popupOk)
    }
}
function Invoke-Menu([int]$command){
    $bar=$script:Excel.CommandBars.Item('Cell')
    try{
        for($i=1;$i -le $bar.Controls.Count;$i++){
            $popup=$bar.Controls.Item($i)
            try{
                if([string]$popup.Tag -ceq 'SLC_68A45C44_2026'){
                    $button=$popup.Controls.Item($command)
                    try{$button.Execute()}finally{Release-Com $button}
                    return
                }
            }finally{Release-Com $popup}
        }
        throw 'Product context menu missing.'
    }finally{Release-Com $bar}
}
$a=$null;$b=$null;$c=$null;$result=$null;$extraWindow=$null;$holding=$null
try{
    Start-OwnExcel -NormalStart
    [ordered]@{pid=$script:ExcelProcess.Id;started=$script:ExcelProcess.StartTime.ToString('o')}|
        ConvertTo-Json|Set-Content (Join-Path $run 'owner.private.json') -Encoding UTF8
    $e=$script:Excel;$e.Visible=$true;$q="'ExcelSmartListCompare.xlam'!"
    $a=$e.Workbooks.Add(-4167)
    $builtIn=[string]$e.Run($q+'SLC_TestAll')
    $builtIn|Set-Content (Join-Path $run 'built-in.txt') -Encoding UTF8
    Check 'installed binary integration checks' ($builtIn.StartsWith('PASS:'))
    $a.Worksheets.Item(1).Range('A1:A42').Value2='alpha'
    $a.SaveAs((Join-Path $run 'First.xlsx'),51)
    $b=$e.Workbooks.Add(-4167)
    $b.Worksheets.Item(1).Range('A1:A2').Value2='beta'
    $b.Worksheets.Item(1).Range('B1:B4').Value2='gamma'
    $b.SaveAs((Join-Path $run 'Second.xlsx'),51)
    # Keep a workbook open while preparing the on-disk fixtures.
    $holding=$e.Workbooks.Add(-4167)
    $a.Close($false);Release-Com $a;$a=$null
    $b.Close($false);Release-Com $b;$b=$null
    $sourceHashes=@((Get-FileHash (Join-Path $run 'First.xlsx')).Hash,(Get-FileHash (Join-Path $run 'Second.xlsx')).Hash)
    $a=$e.Workbooks.Open((Join-Path $run 'First.xlsx'))
    $b=$e.Workbooks.Open((Join-Path $run 'Second.xlsx'))
    $holding.Close($false);Release-Com $holding;$holding=$null
    Check-Window 'second file initially' 0
    $a.Activate();Check-Window 'first file initially' 0
    $a.Worksheets.Item(1).Range('A1:A42').Select();Invoke-Menu 1
    Check-Window 'first file captured' 42
    $b.Activate();$b.Worksheets.Item(1).Range('A1:A2').Select()
    Check-Window 'second file after switch' 42
    Invoke-Menu 3;Check-Window 'cleared from second file' 0
    $a.Activate();Check-Window 'first file after remote clear' 0
    $a.Worksheets.Item(1).Range('A1:A42').Select();Invoke-Menu 1
    $b.Activate();$b.Worksheets.Item(1).Range('B1:B4').Select();Invoke-Menu 4
    Check-Window 'replaced from second file' 4
    $a.Activate();Check-Window 'first file after remote replace' 4
    $c=$e.Workbooks.Add(-4167);Check-Window 'new file after capture' 4
    $a.Activate();$extraWindow=$a.NewWindow()
    Check-Window 'second window of same workbook' 4
    $a.Windows.Item(1).Activate();Check-Window 'original window of same workbook' 4
    $extraWindow.Close($false);Release-Com $extraWindow;$extraWindow=$null
    $b.Close($false);Release-Com $b;$b=$null
    $a.Activate();Check-Window 'source file closed snapshot retained' 4
    $a.Worksheets.Item(1).Range('A1:A3').Select();Invoke-Menu 1
    $result=$e.ActiveWorkbook
    Check 'comparison uses replacement snapshot' ($result.Worksheets.Item(1).Range('B4').Value2 -ceq '첫 번째 목록: 4개 항목 / 두 번째 목록: 3개 항목 / 일치 0개 / 첫 번째 목록 남은 항목 4개 / 두 번째 목록 남은 항목 3개')
    Check 'result contains no formulas' ($result.Worksheets.Item(1).UsedRange.HasFormula -eq $false)
    Check-Window 'result window after comparison' 0
    $a.Activate();Check-Window 'first file after comparison' 0
    $c.Activate();Check-Window 'other file after comparison' 0
    $null=$e.Run($q+'SLC_AttachUI');$null=$e.Run($q+'SLC_AttachUI')
    Check-Window 'repeated attach has one menu set' 0
    Check 'window refresh preserves active workbook' ($e.ActiveWorkbook.Name -ceq $c.Name)
    Check 'events remain enabled' ([bool]$e.EnableEvents)
}finally{
    if($null -ne $extraWindow){try{$extraWindow.Close($false)}catch{};Release-Com $extraWindow}
    foreach($book in @($result,$c,$b,$a,$holding)){
        if($null -ne $book){try{$book.Close($false)}catch{};Release-Com $book}
    }
    Stop-OwnExcel
}
Check 'source file bytes unchanged' ($sourceHashes[0] -ceq (Get-FileHash (Join-Path $run 'First.xlsx')).Hash -and $sourceHashes[1] -ceq (Get-FileHash (Join-Path $run 'Second.xlsx')).Hash)
Write-Output ('PASS: '+$records.Count+' window-state and integration assertions.')
