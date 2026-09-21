Attribute VB_Name = "modSLCReport"
Option Explicit

Private Const OUTPUT_CHUNK As Long = 1024

' Private fault injection is armed only inside SLC_ReportTests.
' These deterministic faults do not simulate or verify a physical Esc key.
Private mTestAbortCode As Long
Private mTestWritesRemaining As Long
Private mTestAbortFired As Boolean

Public Function SLC_WriteUsabilityResults(ByVal a As CSLCList, ByVal b As CSLCList, _
                                         ByVal matched As Long, ByVal excessA As Long, ByVal excessB As Long) As Workbook
    Set SLC_WriteUsabilityResults = WriteReport(a, b, matched, excessA, excessB)
End Function

Public Function SLC_WriteSnapshotPreview(ByVal list As CSLCList) As Workbook
    Dim absent As CSLCList
    Set SLC_WriteSnapshotPreview = WriteReport(list, absent, 0, 0, 0)
End Function

Private Function WriteReport(ByVal a As CSLCList, ByVal b As CSLCList, _
                             ByVal matched As Long, ByVal excessA As Long, ByVal excessB As Long) As Workbook
    Dim wb As Workbook, oldBook As Workbook, summary As Worksheet, ws As Worksheet
    Dim oldScreen As Boolean, oldEvents As Boolean, setState As Boolean
    Dim errNo As Long, errText As String
    ' Equality returns before creating any workbook or changing Excel state.
    If Not b Is Nothing Then
        If excessA = 0 And excessB = 0 Then Exit Function
    End If
    On Error GoTo Failed
    oldScreen = Application.ScreenUpdating
    oldEvents = Application.EnableEvents
    Set oldBook = Application.ActiveWorkbook
    setState = True
    Application.EnableEvents = False
    Application.ScreenUpdating = False
    SLC_WorkStatus "확인할 내용 정리 중"
    SLC_WorkCheckpoint
    Set wb = Application.Workbooks.Add(xlWBATWorksheet)
    Set summary = wb.Worksheets(1)
    If b Is Nothing Then
        summary.Name = "요약"
        WriteSummary summary, a, b, matched, excessA, excessB
        SLC_WorkStatus "값과 셀 위치 정리 중"
        Set ws = AddSheet(wb, "값과 위치")
        WriteLocations ws, a, b
    Else
        summary.Name = "명단비교_결과"
        WriteDifferences summary, a, b
    End If
    summary.Activate
    summary.Range("A1").Select
    SLC_WorkCheckpoint
    ' All event dispatch is finished; do not admit Esc between commit and the owner return.
    ' RunSelection / Preview (and the test owner) restore their previous cancellation setting.
    Application.EnableCancelKey = xlDisabled
    ' Only this new, provisional workbook is owned by this operation.
    ' Leave Saved=False so the user can save or edit every completed result.
    Application.ScreenUpdating = oldScreen
    Application.EnableEvents = oldEvents
    DisarmTestAbort
    Set WriteReport = wb
    Exit Function
Failed:
    errNo = Err.Number
    errText = Err.Description
    DisarmTestAbort
    On Error Resume Next
    If Not wb Is Nothing Then wb.Close SaveChanges:=False
    If Not oldBook Is Nothing Then oldBook.Activate
    If setState Then
        Application.ScreenUpdating = oldScreen
        Application.EnableEvents = oldEvents
    End If
    On Error GoTo 0
    Err.Raise errNo, "SLC_WriteUsabilityResults", errText
End Function

Private Function AddSheet(ByVal wb As Workbook, ByVal sheetName As String) As Worksheet
    Dim ws As Worksheet
    Set ws = wb.Worksheets.Add(After:=wb.Worksheets(wb.Worksheets.Count))
    ws.Name = sheetName
    Set AddSheet = ws
End Function

Private Sub WriteSummary(ByVal ws As Worksheet, ByVal a As CSLCList, ByVal b As CSLCList, _
                         ByVal matched As Long, ByVal excessA As Long, ByVal excessB As Long)
    Dim rows As New Collection, row As Variant, buffer() As Variant
    Dim fill As Long, outRow As Long, result As String
    If b Is Nothing Then
        result = "담아 둔 첫 번째 목록입니다. 아직 비교하지 않았습니다."
    ElseIf excessA = 0 And excessB = 0 Then
        result = "두 목록의 값과 개수가 같습니다."
    Else
        result = "두 목록의 값이나 개수가 다릅니다."
    End If
    rows.Add Array("확인 중인 목록", result)
    rows.Add Array("가져온 파일·시트·범위", a.Source)
    rows.Add Array("담은 시각", Format$(a.CapturedAt, "yyyy-mm-dd hh:nn:ss"))
    rows.Add Array("비교할 값의 개수", a.Total)
    rows.Add Array("중복을 뺀 값의 개수", a.Counts.Count)
    rows.Add Array("같은 값의 추가 개수", CStr(a.DuplicateExcess) & "개 (예: 같은 값이 3개이면 추가 개수는 2개)")
    rows.Add Array("비교에서 뺀 셀", ExclusionText(a))
    rows.Add Array("값과 셀 위치 표시", LocationSummary(a))
    rows.Add Array("오류 셀 위치 표시", ErrorSummary(a))
    rows.Add Array("일부만 표시하는 이유", "[값과 위치]에는 최대 1,200개, 같은 값은 5개, 오류는 200개까지 표시합니다. 비교할 때는 전체 개수를 셉니다.")
    rows.Add Array("비교 설정", SLC_RulesText(a.CompareFullEmail, a.IgnoreCase))
    rows.Add Array("비교에서 빠지는 셀", "숨긴 셀과 필터로 가려진 셀은 읽지 않으며 개수도 세지 않습니다. 일반 범위의 제목은 직접 빼고 선택하세요.")
    rows.Add Array("원본을 수정했다면", "수정한 범위를 다시 담으세요. 이 파일은 담았을 때의 내용이며 자동으로 바뀌지 않습니다.")
    rows.Add Array("저장하기", "이 확인용 파일은 필요할 때 직접 저장하세요. Excel을 완전히 종료하면 기억한 첫 목록은 사라집니다.")
    InitBuffer buffer, 2
    outRow = 2
    WriteHeaders ws, Array("확인할 내용", "담은 첫 번째 목록")
    For Each row In rows
        PutRow ws, buffer, fill, outRow, row
    Next row
    FlushRows ws, buffer, fill, outRow
    FormatTable ws, outRow - 1, 2, False
    ws.Columns("A").ColumnWidth = 25
    ws.Columns("B").ColumnWidth = 80
    ws.Range("A2:B" & CStr(outRow - 1)).Rows.AutoFit
    ws.Range("A2:B2").Interior.Color = RGB(232, 241, 248)
    ws.Range("A2:B2").Font.Bold = True
End Sub

Private Function SourceOf(ByVal list As CSLCList) As String
    If list Is Nothing Then SourceOf = "비교 전" Else SourceOf = list.Source
End Function

Private Function CapturedOf(ByVal list As CSLCList) As String
    If list Is Nothing Then CapturedOf = "비교 전" Else CapturedOf = Format$(list.CapturedAt, "yyyy-mm-dd hh:nn:ss")
End Function

Private Function MetricOf(ByVal list As CSLCList, ByVal metric As String) As Variant
    If list Is Nothing Then MetricOf = "비교 전": Exit Function
    Select Case metric
        Case "total": MetricOf = list.Total
        Case "unique": MetricOf = list.Counts.Count
        Case "duplicate": MetricOf = list.DuplicateExcess
        Case "blank": MetricOf = list.BlankCount
        Case "error": MetricOf = list.ErrorCount
        Case "metadata": MetricOf = list.MetadataCount
        Case "visible": MetricOf = list.VisibleCellCount
        Case "fragments": MetricOf = list.FragmentCount
    End Select
End Function

Private Function LocationSummary(ByVal list As CSLCList) As String
    If list Is Nothing Then LocationSummary = "비교 전": Exit Function
    LocationSummary = "표시 " & list.OccurrenceSamples.Count & "개 / 표시하지 않은 위치 " & list.OmittedOccurrences & "개"
End Function

Private Function ErrorSummary(ByVal list As CSLCList) As String
    If list Is Nothing Then ErrorSummary = "비교 전": Exit Function
    ErrorSummary = "표시 " & list.ErrorSamples.Count & "개 / 표시하지 않은 오류 " & list.OmittedErrors & "개"
End Function

Private Sub WriteDifferences(ByVal ws As Worksheet, ByVal a As CSLCList, ByVal b As CSLCList)
    Dim keys As Variant, k As Variant, buffer() As Variant, fill As Long, outRow As Long, tick As Long
    InitBuffer buffer, 10
    outRow = 1
    PutRow ws, buffer, fill, outRow, Array("두 목록의 차이", "값이나 개수가 다른 항목만 표시합니다.")
    PutRow ws, buffer, fill, outRow, Array("첫 번째 목록", a.Source)
    PutRow ws, buffer, fill, outRow, Array("두 번째 목록", b.Source)
    PutRow ws, buffer, fill, outRow, Array("담은 시각", "첫 목록: " & Format$(a.CapturedAt, "yyyy-mm-dd hh:nn:ss"), "둘째 목록: " & Format$(b.CapturedAt, "yyyy-mm-dd hh:nn:ss"))
    PutRow ws, buffer, fill, outRow, Array("비교한 값의 개수", "첫 목록: " & CStr(a.Total) & "개", "둘째 목록: " & CStr(b.Total) & "개", "원본 값은 처음 발견한 셀의 예입니다.")
    PutRow ws, buffer, fill, outRow, Array("비교에서 뺀 셀", "첫 목록: " & ExclusionText(a), "둘째 목록: " & ExclusionText(b), "숨긴 셀·필터로 가려진 셀은 제외합니다. 오류 셀은 비교하지 못했습니다.")
    PutRow ws, buffer, fill, outRow, Array("비교 설정", SLC_RulesText(a.CompareFullEmail, a.IgnoreCase), "더 많은 개수와 원본 셀 위치: F~K열 선택 → 우클릭 → 숨기기 취소")
    FlushRows ws, buffer, fill, outRow
    WriteHeaders ws, Array("차이", "비교한 값", "첫 목록 원본 값 (예)", "첫 목록 개수", _
        "둘째 목록 원본 값 (예)", "둘째 목록 개수", "첫 목록이 더 많은 개수", "둘째 목록이 더 많은 개수", "첫 목록 원본 셀 (예)", "둘째 목록 원본 셀 (예)"), 8
    outRow = 9
    keys = a.Counts.Keys
    For Each k In keys
        AddDifference ws, buffer, fill, outRow, a, b, CStr(k)
        tick = tick + 1
        If tick Mod 128 = 0 Then SLC_WorkCheckpoint
    Next k
    keys = b.Counts.Keys
    For Each k In keys
        If Not a.Counts.Exists(CStr(k)) Then AddDifference ws, buffer, fill, outRow, a, b, CStr(k)
        tick = tick + 1
        If tick Mod 128 = 0 Then SLC_WorkCheckpoint
    Next k
    FlushRows ws, buffer, fill, outRow
    FormatTable ws, outRow - 1, 10, True, 8
    ws.Columns("A").ColumnWidth = 20
    ws.Columns("B").ColumnWidth = 32
    ws.Columns("C").ColumnWidth = 26
    ws.Columns("E").ColumnWidth = 26
    ws.Columns("D").ColumnWidth = 13
    ws.Columns("F:H").ColumnWidth = 13
    ws.Columns("G:H").ColumnWidth = 18
    ws.Columns("I:J").ColumnWidth = 18
    ws.Range("D9:D" & CStr(outRow - 1)).NumberFormat = "0"
    ws.Range("F9:H" & CStr(outRow - 1)).NumberFormat = "0"
    ws.Columns("G:J").Hidden = True
    ws.Range("B1:F1").Merge
    ws.Range("B2:F2").Merge
    ws.Range("B3:F3").Merge
    ws.Range("D5:F5").Merge
    ws.Range("D6:F6").Merge
    ws.Range("C7:F7").Merge
    ws.Rows(4).RowHeight = 42
    ws.Rows(6).RowHeight = 52
    ws.Rows(7).RowHeight = 48
    ws.Range("A1:J1").Font.Bold = True
End Sub

Private Function ExclusionText(ByVal list As CSLCList) As String
    ExclusionText = "빈칸 " & CStr(list.BlankCount) & "개 / 오류 " & CStr(list.ErrorCount) & "개 / 표 제목·합계 " & CStr(list.MetadataCount) & "개"
End Function


Private Sub AddDifference(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, _
                          ByRef outRow As Long, ByVal a As CSLCList, ByVal b As CSLCList, ByVal key As String)
    Dim ca As Long, cb As Long, leftA As Long, leftB As Long, status As String
    ca = CountOf(a, key)
    cb = CountOf(b, key)
    If ca = cb Then Exit Sub
    If ca = 0 Then
        status = "둘째 목록에만 있음"
    ElseIf cb = 0 Then
        status = "첫 목록에만 있음"
    ElseIf ca <> cb Then
        status = "개수가 다름"
    Else
        status = "중복 (개수 일치)"
    End If
    If ca > cb Then leftA = ca - cb Else leftB = cb - ca
    PutRow ws, buffer, fill, outRow, Array(status, Mid$(key, 4), DictText(a.Examples, key), ca, DictText(b.Examples, key), cb, _
        leftA, leftB, DictText(a.Addresses, key), DictText(b.Addresses, key))
End Sub

Private Sub WriteLocations(ByVal ws As Worksheet, ByVal a As CSLCList, ByVal b As CSLCList)
    Dim buffer() As Variant, fill As Long, outRow As Long
    WriteHeaders ws, Array("구분", "목록", "비교한 값", "원본 값 / 오류", "원본 셀 위치", "안내")
    InitBuffer buffer, 6
    outRow = 2
    AddErrorRows ws, buffer, fill, outRow, a, "첫 번째"
    If Not b Is Nothing Then AddErrorRows ws, buffer, fill, outRow, b, "두 번째"
    AddLocationRows ws, buffer, fill, outRow, a, "첫 번째"
    If Not b Is Nothing Then AddLocationRows ws, buffer, fill, outRow, b, "두 번째"
    FlushRows ws, buffer, fill, outRow
    FormatTable ws, outRow - 1, 6, True
    ws.Columns("A").ColumnWidth = 18
    ws.Columns("B").ColumnWidth = 12
    ws.Columns("B").Hidden = True
    ws.Columns("C").ColumnWidth = 25
    ws.Columns("D").ColumnWidth = 38
    ws.Columns("E").ColumnWidth = 16
    ws.Columns("F").ColumnWidth = 38
End Sub

Private Sub AddErrorRows(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, _
                         ByRef outRow As Long, ByVal list As CSLCList, ByVal label As String)
    Dim sample As Variant
    If list.ErrorSamples.Count = 0 Then
        PutRow ws, buffer, fill, outRow, Array("오류 안내", label, "", "표시할 오류 없음", "", ErrorSummary(list))
    Else
        For Each sample In list.ErrorSamples
            PutRow ws, buffer, fill, outRow, Array("비교에서 뺀 오류", label, "", sample(1), sample(0), "원본에서 오류를 확인하세요.")
        Next sample
    End If
    If list.OmittedErrors > 0 Then
        PutRow ws, buffer, fill, outRow, Array("추가 오류", label, "", "", "", CStr(list.OmittedErrors) & "개는 표시 한도를 넘어 위치를 표시하지 않았습니다.")
    End If
End Sub

Private Sub AddLocationRows(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, _
                            ByRef outRow As Long, ByVal list As CSLCList, ByVal label As String)
    Dim sample As Variant
    PutRow ws, buffer, fill, outRow, Array("위치 안내", label, "", "원본 파일·시트는 [요약]에서 확인하세요.", "", LocationSummary(list))
    For Each sample In list.OccurrenceSamples
        PutRow ws, buffer, fill, outRow, Array("담은 값", label, Mid$(CStr(sample(0)), 4), sample(1), sample(2), "")
    Next sample
End Sub

Private Function CountOf(ByVal list As CSLCList, ByVal key As String) As Long
    If list.Counts.Exists(key) Then CountOf = CLng(list.Counts(key))
End Function

Private Function DictText(ByVal dict As Object, ByVal key As String) As String
    If dict.Exists(key) Then DictText = CStr(dict(key))
End Function

Private Function SafeText(ByVal value As String) As String
    If Len(value) > 0 Then
        Select Case Left$(value, 1)
            Case "=", "+", "-", "@", "'": value = "'" & value
        End Select
    End If
    SafeText = value
End Function

Private Sub InitBuffer(ByRef buffer() As Variant, ByVal columns As Long)
    ReDim buffer(1 To OUTPUT_CHUNK, 1 To columns)
End Sub

Private Sub PutRow(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, _
                   ByRef outRow As Long, ByVal values As Variant)
    Dim c As Long, value As Variant
    fill = fill + 1
    For c = 1 To UBound(buffer, 2)
        buffer(fill, c) = Empty
        If c - 1 <= UBound(values) Then
            value = values(c - 1)
            If VarType(value) = vbString Then value = SafeText(CStr(value))
            buffer(fill, c) = value
        End If
    Next c
    If fill = OUTPUT_CHUNK Then FlushRows ws, buffer, fill, outRow
End Sub

Private Sub FlushRows(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, ByRef outRow As Long)
    Dim target As Range, small() As Variant, r As Long, c As Long, columns As Long
    If fill = 0 Then Exit Sub
    SLC_WorkCheckpoint
    columns = UBound(buffer, 2)
    Set target = ws.Cells(outRow, 1).Resize(fill, columns)
    target.NumberFormat = "@"
    If fill = OUTPUT_CHUNK Then
        target.Value2 = buffer
    Else
        ReDim small(1 To fill, 1 To columns)
        For r = 1 To fill
            For c = 1 To columns
                small(r, c) = buffer(r, c)
            Next c
        Next r
        target.Value2 = small
    End If
    TestAfterOutputWrite
    outRow = outRow + fill
    fill = 0
    SLC_WorkCheckpoint
End Sub

Private Sub WriteHeaders(ByVal ws As Worksheet, ByVal labels As Variant, Optional ByVal headerRow As Long = 1)
    Dim values() As Variant, i As Long
    ReDim values(1 To 1, 1 To UBound(labels) + 1)
    For i = 0 To UBound(labels)
        values(1, i + 1) = labels(i)
    Next i
    ws.Cells(headerRow, 1).Resize(1, UBound(labels) + 1).NumberFormat = "@"
    ws.Cells(headerRow, 1).Resize(1, UBound(labels) + 1).Value2 = values
End Sub

Private Sub FormatTable(ByVal ws As Worksheet, ByVal lastRow As Long, ByVal columns As Long, ByVal filter As Boolean, Optional ByVal headerRow As Long = 1)
    Dim used As Range
    SLC_WorkCheckpoint
    Set used = ws.Cells(1, 1).Resize(lastRow, columns)
    used.Font.Name = "맑은 고딕"
    used.Font.Size = 10
    used.VerticalAlignment = xlTop
    used.WrapText = True
    used.RowHeight = 32
    With ws.Cells(headerRow, 1).Resize(1, columns)
        .Interior.Color = RGB(30, 65, 92)
        .Font.Color = RGB(255, 255, 255)
        .Font.Bold = True
        .RowHeight = 36
    End With
    If filter Then ws.Cells(headerRow, 1).Resize(lastRow - headerRow + 1, columns).AutoFilter
    ws.Activate
    With ws.Parent.Windows(1)
        .FreezePanes = False
        .SplitColumn = 0
        .SplitRow = headerRow
        .FreezePanes = True
    End With
    ws.Range("A1").Select
    SLC_WorkCheckpoint
End Sub


' Called by SLC_UsabilityTests after the owner initializes its operation clock.
' Synthetic values only. Every workbook closed below is returned by WriteReport.
Public Function SLC_ReportTests() As String
    Dim a As CSLCList, b As CSLCList, sample As CSLCList, absent As CSLCList
    Dim testBook As Workbook, oldBook As Workbook, ws As Worksheet
    Dim oldCancel As XlEnableCancelKey, i As Long, key As String, formulaState As Variant
    Dim errNo As Long, errText As String
    On Error GoTo Failed
    Set oldBook = Application.ActiveWorkbook
    oldCancel = Application.EnableCancelKey
    Set sample = New CSLCList
    sample.IgnoreCase = True
    AddTestValue sample, "case", "A1"
    For i = 1 To 7
        AddTestValue sample, String$(i, " ") & "CASE", "A" & CStr(i + 1)
    Next i
    AssertReport sample.Total = 8 And sample.Counts.Count = 1, "Samples changed comparison counts"
    AssertReport sample.OccurrenceSamples.Count = 5 And sample.OmittedOccurrences = 3, "Per-key occurrence bound"
    Set sample = New CSLCList
    For i = 1 To 1300
        AddTestValue sample, "item-" & CStr(i), "A" & CStr(i)
    Next i
    AssertReport sample.OccurrenceSamples.Count = 1200 And sample.OmittedOccurrences = 100, "Global occurrence bound"
    AssertReport sample.Total = 1300 And sample.Counts.Count = 1300, "Occurrence truncation changed counts"
    For i = 1 To 201
        sample.ErrorCount = sample.ErrorCount + 1
        sample.AddError "C" & CStr(i), "#N/A"
    Next i
    AssertReport sample.ErrorSamples.Count = 200 And sample.OmittedErrors = 1, "Error bound"
    Set a = New CSLCList
    Set b = New CSLCList
    a.IgnoreCase = True: b.IgnoreCase = True
    a.Source = "=1+1"
    b.Source = "+1+1"
    a.CapturedAt = Now
    b.CapturedAt = Now
    AddTestValue a, "USER@A.COM", "A1"
    AddTestValue a, "abc", "A2"
    AddTestValue a, " ABC ", "A3"
    AddTestValue a, "=1+1", "A4"
    AddTestValue a, "+1+1", "A5"
    AddTestValue a, "-1+1", "A6"
    AddTestValue a, "@SUM(1)", "A7"
    AddTestValue a, "'quoted", "A8"
    a.ErrorCount = 1
    a.AddError "A9", "#N/A"
    AddTestValue b, "user@b.com", "B1"
    AddTestValue b, "abc", "B2"
    AddTestValue b, "=1+1", "B3"
    Set testBook = WriteReport(a, b, 3, 5, 0)
    AssertReport testBook.Worksheets.Count = 1, "Comparison sheet count"
    AssertReport testBook.Worksheets(1).Name = "명단비교_결과", "RC9 compatible sheet name"
    AssertReport testBook.Worksheets(1).Cells(8, 3).Value2 = "첫 목록 원본 값 (예)", "RC9 compatible columns"
    AssertReport InStr(CStr(testBook.Worksheets(1).Cells(6, 2).Value2), "오류 1") > 0, "Excluded errors disclosed"
    For Each ws In testBook.Worksheets
        formulaState = ws.UsedRange.HasFormula
        AssertReport Not IsNull(formulaState), "Mixed formulas in report"
        AssertReport Not CBool(formulaState), "Formula activated in report"
        ws.Activate
        AssertReport testBook.Windows(1).FreezePanes And testBook.Windows(1).SplitRow = 8, "Comparison header must be frozen at row 8"
    Next ws
    AssertReport Not testBook.Saved, "Result should remain unsaved"
    testBook.Worksheets(1).Range("B1").Value2 = "report rollback sentinel"
    testBook.Activate
    For i = 1 To 2
        mTestAbortFired = False
        If i = 1 Then mTestAbortCode = vbObjectError + 2104 Else mTestAbortCode = vbObjectError + 2296
        mTestWritesRemaining = i
        VerifyInjectedRollback testBook, a, b, mTestAbortCode
    Next i
    testBook.Close SaveChanges:=False
    Set testBook = Nothing
    Set a = New CSLCList
    Set b = New CSLCList
    a.Source = "synthetic A"
    b.Source = "synthetic B"
    a.CapturedAt = Now
    b.CapturedAt = Now
    AddTestValue a, "same", "A1"
    AddTestValue b, "same", "B1"
    a.BlankCount = 1
    Set testBook = WriteReport(a, b, 1, 0, 0)
    AssertReport testBook Is Nothing, "Equal values must not create a result"
    Set testBook = WriteReport(a, absent, 0, 0, 0)
    AssertReport testBook.Worksheets.Count = 2, "Preview sheet count"
    AssertReport CStr(testBook.Worksheets(1).Cells(2, 2).Value2) = "담아 둔 첫 번째 목록입니다. 아직 비교하지 않았습니다.", "Preview heading"
    testBook.Close SaveChanges:=False
    Set testBook = Nothing
    If Not oldBook Is Nothing Then oldBook.Activate
    Application.EnableCancelKey = oldCancel
    DisarmTestAbort
    mTestAbortFired = False
    SLC_ReportTests = "PASS: injected cancellation/failure output rollback (not physical Esc); bounded samples, error locations, single-sheet differences, no identical report, 2-sheet preview, formula safety, header freeze"
    Exit Function
Failed:
    errNo = Err.Number
    errText = Err.Description
    DisarmTestAbort
    mTestAbortFired = False
    On Error Resume Next
    If Not testBook Is Nothing Then testBook.Close SaveChanges:=False
    If Not oldBook Is Nothing Then oldBook.Activate
    Application.EnableCancelKey = oldCancel
    On Error GoTo 0
    Err.Raise errNo, "SLC_ReportTests", errText
End Function

Private Sub AddTestValue(ByVal list As CSLCList, ByVal raw As String, ByVal address As String)
    Dim key As String
    key = SLC_Normalize(raw, list.CompareFullEmail, list.IgnoreCase)
    list.Total = list.Total + 1
    list.VisibleCellCount = list.VisibleCellCount + 1
    If list.Counts.Exists(key) Then
        list.Counts(key) = CLng(list.Counts(key)) + 1
        list.DuplicateExcess = list.DuplicateExcess + 1
    Else
        list.Counts.Add key, 1
        list.Examples.Add key, raw
        list.Addresses.Add key, address
    End If
    list.AddOccurrence key, raw, address
End Sub

Private Sub AssertReport(ByVal condition As Boolean, ByVal label As String)
    If Not condition Then Err.Raise vbObjectError + 2295, "SLC_ReportTests", label
End Sub


Private Sub DisarmTestAbort()
    mTestAbortCode = 0
    mTestWritesRemaining = 0
End Sub

Private Sub TestAfterOutputWrite()
    Dim injected As Long
    If mTestAbortCode = 0 Then Exit Sub
    mTestWritesRemaining = mTestWritesRemaining - 1
    If mTestWritesRemaining > 0 Then Exit Sub
    injected = mTestAbortCode
    mTestAbortFired = True
    DisarmTestAbort
    Err.Raise injected, "SLC_ReportTests", "Injected fault after an output batch; not a physical Esc test"
End Sub

Private Sub VerifyInjectedRollback(ByVal previousResult As Workbook, ByVal a As CSLCList, _
                                   ByVal b As CSLCList, ByVal expectedError As Long)
    Dim unexpectedResult As Workbook, expectedBookCount As Long, actualError As Long
    Dim oldScreen As Boolean, oldEvents As Boolean, oldInteractive As Boolean
    Dim oldCalculation As XlCalculation, oldCancel As XlEnableCancelKey
    Dim oldTotalA As Long, oldTotalB As Long, fired As Boolean
    expectedBookCount = Application.Workbooks.Count
    oldScreen = Application.ScreenUpdating
    oldEvents = Application.EnableEvents
    oldInteractive = Application.Interactive
    oldCalculation = Application.Calculation
    oldCancel = Application.EnableCancelKey
    oldTotalA = a.Total
    oldTotalB = b.Total
    On Error Resume Next
    Err.Clear
    Set unexpectedResult = WriteReport(a, b, 3, 5, 0)
    actualError = Err.Number
    Err.Clear
    On Error GoTo 0
    fired = mTestAbortFired
    DisarmTestAbort
    mTestAbortFired = False
    ' The caller owns cancellation settings, just as RunSelection / Preview do.
    Application.EnableCancelKey = oldCancel
    ' If injection unexpectedly did not fire, still close only a returned owned workbook.
    If Not unexpectedResult Is Nothing Then unexpectedResult.Close SaveChanges:=False
    AssertReport fired, "Output fault did not reach the after-write hook"
    AssertReport actualError = expectedError, "Injected output error was not propagated"
    AssertReport Application.Workbooks.Count = expectedBookCount, "Incomplete output workbook leaked"
    AssertReport (Application.ActiveWorkbook Is previousResult), "Previous workbook was not reactivated"
    AssertReport previousResult.Worksheets(1).Range("B1").Value2 = "report rollback sentinel", "Previous result was edited"
    AssertReport Not previousResult.Saved, "Previous edited result lost unsaved state"
    AssertReport Application.ScreenUpdating = oldScreen, "ScreenUpdating was not restored after output fault"
    AssertReport Application.EnableEvents = oldEvents, "EnableEvents was not restored after output fault"
    AssertReport Application.Interactive = oldInteractive, "Interactive changed during output fault"
    AssertReport oldCalculation = Application.Calculation, "Calculation changed during output fault"
    AssertReport a.Total = oldTotalA And b.Total = oldTotalB, "Output fault changed snapshot counts"
End Sub
