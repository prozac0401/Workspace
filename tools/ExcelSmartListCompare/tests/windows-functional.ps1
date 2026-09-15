[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$AddinPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
# COM functional evidence only. Does not claim normal-start autoload or GUI coverage.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$output=[IO.Path]::GetFullPath($OutputDirectory)
[void](New-Item -ItemType Directory -Path $output -Force)
$addin=[IO.Path]::GetFullPath($AddinPath)
if(-not(Test-Path -LiteralPath $addin)){throw 'XLAM missing; build in an approved environment first.'}
if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Existing Excel detected; no application was attached or closed.'}
$results=New-Object System.Collections.Generic.List[object]
$excel=$null;$addbook=$null;$sourceA=$null;$sourceB=$null
function Release-Com($value){if($value -and [Runtime.InteropServices.Marshal]::IsComObject($value)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($value)}}
function Get-SharedHash([string]$path){
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{(Get-FileHash -InputStream $stream -Algorithm SHA256).Hash}finally{$stream.Dispose()}
}
function Check([string]$id,[bool]$condition,$actual,$expected){
    $results.Add([pscustomobject]@{id=$id;layer='Actual Excel COM';status=if($condition){'PASS'}else{'FAIL'};expected=$expected;actual=$actual})
    $results | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $output 'functional.json') -Encoding UTF8
    Write-Host ($id + ': ' + $condition)
    if(-not $condition){throw "Assertion failed: $id"}
}
function Run-Macro([string]$name){
    Write-Host ('Running '+$name)
    $qualified="'"+([IO.Path]::GetFileName($addin)).Replace("'","''")+"'!"+$name
    if($name -in @('SLC_Run','SLC_Clear','SLC_Replace')){$null=$excel.Run($qualified);Write-Host ('Finished '+$name);return}
    $value=[string]$excel.Run($qualified)
    Write-Host ('Finished '+$name)
    return $value
}
function Make-Book([string]$name,[object[]]$values,[bool]$horizontal){
    $book=$excel.Workbooks.Add(-4167)
    $sheet=$book.Worksheets.Item(1)
    $sheet.Name='Synthetic'
    for($i=0;$i -lt $values.Count;$i++){
        $row=if($horizontal){2}else{$i+2};$column=if($horizontal){$i+2}else{2}
        $cell=$sheet.Cells.Item($row,$column)
        if($values[$i] -is [string]){$cell.NumberFormat='@'}
        $null=$cell.GetType().InvokeMember('Value2',[Reflection.BindingFlags]::SetProperty,$null,$cell,@($values[$i]))
        Release-Com $cell
    }
    # An adjacent sentinel must never leak into the selected list.
    $sheet.Range('Z1').Value2='OUTSIDE_SELECTION'
    $path=Join-Path $output ($name+'.xlsx')
    if(Test-Path -LiteralPath $path){throw 'Use a new output directory; existing fixtures are preserved.'}
    $book.SaveAs($path,51)
    Release-Com $sheet
    return $book
}
try{
    $excel=New-Object -ComObject Excel.Application
    $excel.AutomationSecurity=2
    $owned=@(Get-Process EXCEL -ErrorAction SilentlyContinue)
    if($owned.Count -ne 1){throw 'Cannot uniquely identify newly created Excel.'}
    $owner=[ordered]@{pid=$owned[0].Id;hwnd=$excel.Hwnd;version=$excel.Version;build=$excel.Build;addinSha256=(Get-FileHash -LiteralPath $addin).Hash}
    $owner | ConvertTo-Json | Set-Content (Join-Path $output 'owner.json') -Encoding UTF8
    $addbook=$excel.Workbooks.Open($addin,0,$true)
    $version=[string](Run-Macro 'SLC_Version')
    Check 'COM-VERSION' ($version -eq '0.2.0') $version '0.2.0'
    $internal=[string](Run-Macro 'SLC_TestAll')
    Check 'COM-BUILTIN' ($internal.StartsWith('PASS:')) $internal 'PASS: normalization + Excel integration checks'
    # Expectations are literal, independent of the product normalization function.
    # Duplicate alice guarantees a result workbook, avoiding an unattended equal-list dialog.
    $sourceA=Make-Book '합성 기준 A' @('ALICE@example.invalid','alice@other.invalid','00123',[double]123,'=1+1') $true
    $sourceB=Make-Book '합성 비교 B' @('alice','00123','123.0','+2','bob') $false
    $paths=@($sourceA.FullName,$sourceB.FullName)
    $before=@($paths | ForEach-Object {Get-SharedHash $_})
    $excel.Visible=$true
    $sourceA.Activate();$sourceA.Worksheets.Item(1).Range('B2:F2').Select()
    $start=[Diagnostics.Stopwatch]::StartNew();$null=Run-Macro 'SLC_Run';$captureMs=$start.Elapsed.TotalMilliseconds
    $sourceA.Close($false);Release-Com $sourceA;$sourceA=$null
    $sourceB.Activate();$sourceB.Worksheets.Item(1).Range('B2:B6').Select()
    $start.Restart();$null=Run-Macro 'SLC_Run';$compareMs=$start.Elapsed.TotalMilliseconds
    $result=$excel.ActiveWorkbook
    Check 'PUBLIC-NEW-RESULT' ($result.FullName -ne $sourceB.FullName) $result.Name 'new result workbook'
    $sheet=$result.Worksheets.Item(1)
    Check 'PUBLIC-SNAPSHOT-A-CLOSED' ($sheet.Range('B4').Value2 -eq '첫 번째 목록: 5개 항목 / 두 번째 목록: 5개 항목 / 일치 3개 / 첫 번째 목록 잔여 2개 / 두 번째 목록 잔여 2개') $sheet.Range('B4').Value2 '첫 번째 목록: 5개 항목 / 두 번째 목록: 5개 항목 / 일치 3개 / 첫 번째 목록 잔여 2개 / 두 번째 목록 잔여 2개'
    Check 'PUBLIC-OUTPUT-NO-FORMULA' ($sheet.UsedRange.HasFormula -eq $false) $sheet.UsedRange.HasFormula $false
    $actual=@{}
    for($r=9;$r -le $sheet.UsedRange.Rows.Count;$r++){
        $key=[string]$sheet.Cells.Item($r,2).Value2
        $actual[$key]=@([int]$sheet.Cells.Item($r,4).Value2,[int]$sheet.Cells.Item($r,6).Value2)
    }
    Check 'PUBLIC-DUPLICATE-COUNTS' (($actual['alice'] -join ',') -eq '2,1') ($actual['alice'] -join ',') '2,1'
    Write-Host 'Saving comparison workbook'
    $resultPath=Join-Path $output 'actual-comparison.xlsx'
    $null=$result.GetType().InvokeMember('SaveAs',[Reflection.BindingFlags]::InvokeMethod,$null,$result,@([string]$resultPath,[int]51))
    Write-Host 'Saved comparison workbook'
    $after=@($paths | ForEach-Object {Get-SharedHash $_})
    Check 'PUBLIC-SOURCE-FILE-HASHES' (($before -join ',') -eq ($after -join ',')) $after $before
    [ordered]@{captureTotalMs=$captureMs;readCompareOutputTotalMs=$compareMs;phaseBreakdown='NOT_RUN';cellsPerList=5} | ConvertTo-Json | Set-Content (Join-Path $output 'performance.json') -Encoding UTF8
    Release-Com $sheet;Release-Com $result
}catch{
    $results.Add([pscustomobject]@{id='COM-EXECUTION';status='FAIL';actual=$_.Exception.Message;location=$_.ScriptStackTrace})
}finally{
    if($excel){
        # Every workbook in this uniquely owned instance was opened by this script.
        for($i=$excel.Workbooks.Count;$i -ge 1;$i--){$b=$excel.Workbooks.Item($i);$b.Close($false);Release-Com $b}
        $excel.Quit()
    }
    foreach($value in @($sourceA,$sourceB,$addbook,$excel)){Release-Com $value}
    $sourceA=$null;$sourceB=$null;$addbook=$null;$excel=$null
    [GC]::Collect();[GC]::WaitForPendingFinalizers()
    $results | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $output 'functional.json') -Encoding UTF8
}
if(@($results | Where-Object status -eq 'FAIL').Count){exit 1}
