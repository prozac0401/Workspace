param([string]$OutputDirectory = (Join-Path $PSScriptRoot '../../../artifacts/calendar'))
$ErrorActionPreference = 'Stop'
$outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
$sourcePath = Join-Path $outputRoot 'calendar_2027.xlsx'
$inputPath = Join-Path $outputRoot 'excel-test-input.xlsx'
$copyPath = Join-Path $outputRoot 'excel-edit-roundtrip.xlsx'
$pdfPath = Join-Path $outputRoot 'excel-print.pdf'
$resultPath = Join-Path $outputRoot 'excel-results.json'
# Only a generated fixture copy is opened; no running user's workbook is selected.
Copy-Item -LiteralPath $sourcePath -Destination $inputPath
$excelApp = $null
$book = $null
$sheet = $null
$ownedInstance = $false
$report = [ordered]@{status='FAIL'; engine='Microsoft Excel desktop via isolated COM'; datasetKind='fixture'; physicalPrint='NOT RUN'}
try {
    $excelApp = New-Object -ComObject Excel.Application
    if ($excelApp.Workbooks.Count -ne 0) { throw 'Isolation failed: instance already has a workbook; no workbook was changed' }
    $ownedInstance = $true
    $excelApp.Visible = $false
    $excelApp.DisplayAlerts = $false
    $excelApp.AutomationSecurity = 3
    $report.version = $excelApp.Version
    $report.build = $excelApp.Build
    $book = $excelApp.Workbooks.Open($inputPath, 0, $false)
    $sheet = $book.Worksheets.Item(1)
    if ($book.Worksheets.Count -ne 1) { throw 'Expected exactly one worksheet' }
    if ($sheet.Range('F7').Value2 -notmatch '^1(?: \(\d{2}\.\d{2}\))?\r?\n') { throw 'F7 date text mismatch' }
    if ($null -ne $sheet.Range('F8').Value2) { throw 'F8 must be empty' }
    if ($sheet.Range('F8').MergeCells) { throw 'Writing cell must be independent' }
    if ($sheet.ProtectContents) { throw 'Worksheet must be unprotected' }
    $report.open = 'PASS'
    $report.printArea = $sheet.PageSetup.PrintArea
    if ($report.printArea -notmatch '^\$A\$5:\$G\$\d+$') { throw 'Print area must start at the January heading in A5' }
    $januaryHeading = '2027' + [char]0xB144 + ' 1' + [char]0xC6D4
    if ($sheet.Range('A5').Value2 -ne $januaryHeading) { throw 'First printed heading must be January' }
    for ($leadingRow = 1; $leadingRow -le 4; $leadingRow++) {
        if (-not $sheet.Rows.Item($leadingRow).Hidden) { throw 'Unused leading rows must be hidden' }
        if ($null -ne $sheet.Cells.Item($leadingRow, 1).Value2) { throw 'Unnecessary annual header or metadata remains in the worksheet' }
    }
    foreach ($header in @($sheet.PageSetup.LeftHeader, $sheet.PageSetup.CenterHeader, $sheet.PageSetup.RightHeader)) {
        if ($header) { throw 'Unexpected printed header' }
    }
    $report.januaryStartsAtMonthHeading = 'PASS'
    $report.fitToWidth = $sheet.PageSetup.FitToPagesWide
    $report.fitToHeight = $sheet.PageSetup.FitToPagesTall
    $report.horizontalBreaks = $sheet.HPageBreaks.Count
    $book.ExportAsFixedFormat(0, $pdfPath)
    $report.pdfExport = 'PASS'
    $sheet.Range('F8').Value2 = 'LOCAL_EDIT_TEST'
    $sheet.Range('F9').Value2 = 'SECOND_ROW_TEST'
    $book.SaveAs($copyPath, 51)
    $book.Close($false)
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($sheet); $sheet = $null
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($book); $book = $null
    $book = $excelApp.Workbooks.Open($copyPath, 0, $true)
    $sheet = $book.Worksheets.Item(1)
    if ($sheet.Range('F8').Value2 -ne 'LOCAL_EDIT_TEST' -or $sheet.Range('F9').Value2 -ne 'SECOND_ROW_TEST') { throw 'Edit/save/reopen failed' }
    if ($null -ne $sheet.Range('F10').Value2) { throw 'Third blank writing row changed' }
    $report.editSaveReopen = 'PASS'
    $report.status = 'PASS'
} catch {
    $report.error = $_.Exception.Message
} finally {
    if ($null -ne $book) { $book.Close($false) }
    if ($ownedInstance -and $null -ne $excelApp) { $excelApp.Quit() }
    foreach ($obj in @($sheet, $book, $excelApp)) { if ($null -ne $obj) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($obj) } }
    [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    $json = $report | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($resultPath, $json, [Text.UTF8Encoding]::new($false))
    Write-Output $json
}
if ($report.status -ne 'PASS') { exit 1 }
