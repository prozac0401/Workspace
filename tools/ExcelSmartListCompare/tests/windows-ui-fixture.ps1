[CmdletBinding()]
param([int]$OwnedPid=0,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class SlcUiOwner {
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
}
'@
$created=$OwnedPid -eq 0
if($created){
    if(@(Get-Process EXCEL -ErrorAction SilentlyContinue).Count){throw 'Existing Excel detected.'}
    $excel=New-Object -ComObject Excel.Application
    $excel.AutomationSecurity=2
}else{$excel=[Runtime.InteropServices.Marshal]::GetActiveObject('Excel.Application')}
[uint32]$actual=0
[void][SlcUiOwner]::GetWindowThreadProcessId([IntPtr]$excel.Hwnd,[ref]$actual)
if(-not $created -and $actual -ne $OwnedPid){throw 'ROT is not the specifically launched test process.'}
if($excel.Workbooks.Count -gt 0){throw 'Unexpected workbook; no workbook was inspected or modified.'}
try {
$dir=[IO.Path]::GetFullPath($OutputDirectory)
[void](New-Item -ItemType Directory -Path $dir -Force)
$books=@()
foreach($side in @('A','B')){
    $book=$excel.Workbooks.Add(-4167)
    $sheet=$book.Worksheets.Item(1)
    $sheet.Name='Synthetic'
    $sheet.Range('A1:D10').NumberFormat='@'
    $sheet.Range('A1').Value2='SLC E2E - synthetic data only'
    $sheet.Range('A3').Value2='alice@example.invalid'
    $sheet.Range('A4').Value2='00123'
    $sheet.Range('A5').Value2=if($side -eq 'A'){'alpha'}else{'beta'}
    $sheet.Range('A1:D1').Font.Bold=$true
    $sheet.Columns.Item(1).ColumnWidth=40
    $file=Join-Path $dir ('Synthetic-'+$side+'.xlsx')
    if(Test-Path -LiteralPath $file){throw 'Fixture already exists; use a new directory.'}
    $book.SaveAs($file,51)
    $book.Close($false)
    $books+=@{file=$file;sha256=(Get-FileHash -LiteralPath $file).Hash}
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($sheet)
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($book)
}
@{pid=$actual;hwnd=$excel.Hwnd;books=$books;startedNormally=(-not $created);comparisonExecuted=$false} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $dir 'fixture.json') -Encoding UTF8
} finally {
    if($created){
        for($i=$excel.Workbooks.Count;$i -ge 1;$i--){$b=$excel.Workbooks.Item($i);$b.Close($false);[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($b)}
        $excel.Quit()
    }
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($excel)
}
