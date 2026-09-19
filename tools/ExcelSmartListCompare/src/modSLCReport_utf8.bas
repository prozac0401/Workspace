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
    On Error GoTo Failed
    oldScreen = Application.ScreenUpdating
    oldEvents = Application.EnableEvents
    Set oldBook = Application.ActiveWorkbook
    setState = True
    Application.EnableEvents = False
    Application.ScreenUpdating = False
    SLC_WorkStatus "요약 작성 중"
    SLC_WorkCheckpoint
    Set wb = Application.Workbooks.Add(xlWBATWorksheet)
    Set summary = wb.Worksheets(1)
    summary.Name = "요약"
    WriteSummary summary, a, b, matched, excessA, excessB
    If Not b Is Nothing Then
        SLC_WorkStatus "차이·중복 작성 중"
        Set ws = AddSheet(wb, "차이·중복")
        WriteDifferences ws, a, b
    End If
    SLC_WorkStatus "제외·발생위치 작성 중"
    Set ws = AddSheet(wb, "제외·발생위치")
    WriteLocations ws, a, b
    SLC_WorkStatus "규칙으로 같아진 값 작성 중"
    Set ws = AddSheet(wb, "규칙으로 같아진 값")
    WriteVariants ws, a, b
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
        result = "담은 첫 번째 목록 확인 (비교 전)"
    ElseIf excessA = 0 And excessB = 0 Then
        result = "비교 대상 값·개수 일치"
    Else
        result = "비교 대상 값 또는 개수에 차이 있음"
    End If
    rows.Add Array("확인 결과", result, "선택한 원본 전체의 동일성을 뜻하지 않습니다.")
    rows.Add Array("위치 / 선택 범위", a.Source, SourceOf(b))
    rows.Add Array("담은 시각", Format$(a.CapturedAt, "yyyy-mm-dd hh:nn:ss"), CapturedOf(b))
    rows.Add Array("비교 대상 항목", a.Total, MetricOf(b, "total"))
    rows.Add Array("서로 다른 비교값", a.Counts.Count, MetricOf(b, "unique"))
    rows.Add Array("중복 (두 번째 발생부터)", a.DuplicateExcess, MetricOf(b, "duplicate"))
    If Not b Is Nothing Then
        rows.Add Array("짝지어진 항목", matched, matched)
        rows.Add Array("남은 항목", excessA, excessB)
    End If
    rows.Add Array("제외: 빈칸·공백·빈문자", a.BlankCount, MetricOf(b, "blank"))
    rows.Add Array("제외: 오류", a.ErrorCount, MetricOf(b, "error"))
    rows.Add Array("제외: 제목·합계", a.MetadataCount, MetricOf(b, "metadata"))
    rows.Add Array("읽은 가시 셀 (제외 전)", a.VisibleCellCount, MetricOf(b, "visible"))
    rows.Add Array("읽은 가시 영역", a.FragmentCount, MetricOf(b, "fragments"))
    rows.Add Array("숨김·필터 제외", "숨긴 셀과 필터로 가려진 셀은 읽지 않습니다. 제외 개수는 별도로 집계하지 않습니다.", "일반 범위의 제목은 자동으로 제외하지 않습니다.")
    rows.Add Array("오류가 있는 경우", "오류 셀을 뺀 결과이므로 원본 전체가 같다고 볼 수 없습니다.", "제외·발생위치 시트에서 오류 종류와 위치 표본을 확인하세요.")
    rows.Add Array("발생위치 표본 / 생략", LocationSummary(a), LocationSummary(b))
    rows.Add Array("오류 표본 / 생략", ErrorSummary(a), ErrorSummary(b))
    rows.Add Array("원문 변형 표본 / 생략", VariantSummary(a), VariantSummary(b))
    rows.Add Array("표본 한도 (각 목록)", "발생위치 1,200개 / 원문 변형 600개 / 오류 200개. 발생·변형은 비교값당 5개까지.", "생략된 원문 변형 후보는 미저장 발생 수이며 서로 다른 원문의 정확한 수가 아닙니다.")
    rows.Add Array("비교 규칙", "순서를 무시하고 같은 값의 개수를 비교합니다. 이메일은 @ 앞부분만 비교합니다.", "숫자 표기·영문 대소문자·전각 영숫자·일부 공백 차이는 무시합니다. 텍스트 00123과 숫자 123은 다릅니다.")
    rows.Add Array("원문·위치 읽기", "대표 값과 대표 주소는 처음 발견한 셀입니다. 위치 표본은 특정 셀이 잘못됐다는 뜻이 아닙니다.", "긴 원문은 셀을 선택한 뒤 수식 입력줄에서 확인하세요. 셀은 수식이 아닌 텍스트로 기록합니다.")
    rows.Add Array("첫 번째 목록 상태", "첫 번째 목록은 계속 보관 중입니다. 바꾸기/비우기로 새 비교를 시작하세요.", "원본을 고쳐도 담은 값은 바뀌지 않습니다. 수정한 원본은 다시 담으세요.")
    rows.Add Array("보관과 저장", "원본과 이전 결과는 바꾸지 않습니다. 이 결과는 원하는 위치에 직접 저장하세요.", "결과는 담은 시점의 기록입니다. Excel을 종료하면 기억한 목록은 사라집니다.")
    InitBuffer buffer, 3
    outRow = 2
    WriteHeaders ws, Array("항목", "첫 번째 목록 / 설명", "두 번째 목록 / 설명")
    For Each row In rows
        PutRow ws, buffer, fill, outRow, row
    Next row
    FlushRows ws, buffer, fill, outRow
    FormatTable ws, outRow - 1, 3, False
    ws.Columns("A").ColumnWidth = 29
    ws.Columns("B:C").ColumnWidth = 52
    ws.Range("A2:C" & CStr(outRow - 1)).Rows.AutoFit
    ws.Range("A2:C2").Interior.Color = RGB(232, 241, 248)
    ws.Range("A2:C2").Font.Bold = True
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
    LocationSummary = "저장 " & list.OccurrenceSamples.Count & "개 / 생략 " & list.OmittedOccurrences & "개"
End Function

Private Function ErrorSummary(ByVal list As CSLCList) As String
    If list Is Nothing Then ErrorSummary = "비교 전": Exit Function
    ErrorSummary = "저장 " & list.ErrorSamples.Count & "개 / 생략 " & list.OmittedErrors & "개"
End Function

Private Function VariantSummary(ByVal list As CSLCList) As String
    If list Is Nothing Then VariantSummary = "비교 전": Exit Function
    VariantSummary = "저장 " & list.VariantSamples.Count & "개 / 미저장 변형 발생 " & list.OmittedVariantCandidates & "개"
End Function

Private Sub WriteDifferences(ByVal ws As Worksheet, ByVal a As CSLCList, ByVal b As CSLCList)
    Dim keys As Variant, k As Variant, buffer() As Variant, fill As Long, outRow As Long, tick As Long
    WriteHeaders ws, Array("상태", "비교에 쓴 값", "첫 목록 남은 수", "둘째 목록 남은 수", _
        "첫 목록 개수", "둘째 목록 개수", "첫 목록 원래 값 (예)", "둘째 목록 원래 값 (예)", "첫 목록 대표 주소", "둘째 목록 대표 주소")
    InitBuffer buffer, 10
    outRow = 2
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
    If outRow = 2 And fill = 0 Then
        PutRow ws, buffer, fill, outRow, Array("차이·중복 없음", "비교 대상 값·개수는 같습니다. 제외 집계는 요약에서 확인하세요.")
    End If
    FlushRows ws, buffer, fill, outRow
    FormatTable ws, outRow - 1, 10, True
    ws.Columns("A").ColumnWidth = 24
    ws.Columns("B").ColumnWidth = 25
    ws.Columns("C:F").ColumnWidth = 13
    ws.Columns("G:H").ColumnWidth = 32
    ws.Columns("I:J").ColumnWidth = 18
    ws.Range("C2:F" & CStr(outRow - 1)).NumberFormat = "0"
End Sub

Private Sub AddDifference(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, _
                          ByRef outRow As Long, ByVal a As CSLCList, ByVal b As CSLCList, ByVal key As String)
    Dim ca As Long, cb As Long, leftA As Long, leftB As Long, status As String
    ca = CountOf(a, key)
    cb = CountOf(b, key)
    If ca = cb And ca < 2 Then Exit Sub
    If ca = 0 Then
        status = "두 번째 목록에만 있음"
    ElseIf cb = 0 Then
        status = "첫 번째 목록에만 있음"
    ElseIf ca <> cb Then
        status = "개수가 다름"
    Else
        status = "중복 (개수 일치)"
    End If
    If ca > cb Then leftA = ca - cb Else leftB = cb - ca
    PutRow ws, buffer, fill, outRow, Array(status, Mid$(key, 4), leftA, leftB, ca, cb, _
        DictText(a.Examples, key), DictText(b.Examples, key), DictText(a.Addresses, key), DictText(b.Addresses, key))
End Sub

Private Sub WriteLocations(ByVal ws As Worksheet, ByVal a As CSLCList, ByVal b As CSLCList)
    Dim buffer() As Variant, fill As Long, outRow As Long
    WriteHeaders ws, Array("구분", "목록", "비교에 쓴 값", "원래 값 / 오류 종류", "셀 주소", "읽는 방법 / 생략")
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
    ws.Columns("C").ColumnWidth = 25
    ws.Columns("D").ColumnWidth = 38
    ws.Columns("E").ColumnWidth = 16
    ws.Columns("F").ColumnWidth = 55
End Sub

Private Sub AddErrorRows(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, _
                         ByRef outRow As Long, ByVal list As CSLCList, ByVal label As String)
    Dim sample As Variant
    If list.ErrorSamples.Count = 0 Then
        PutRow ws, buffer, fill, outRow, Array("오류 안내", label, "", "저장된 오류 표본 없음", "", ErrorSummary(list))
    Else
        For Each sample In list.ErrorSamples
            PutRow ws, buffer, fill, outRow, Array("제외한 오류", label, "", sample(1), sample(0), "담은 시점의 오류입니다. 원본은 변경하지 않습니다.")
        Next sample
    End If
    If list.OmittedErrors > 0 Then
        PutRow ws, buffer, fill, outRow, Array("오류 표본 생략", label, "", "", "", CStr(list.OmittedErrors) & "개는 표본 한도로 위치를 저장하지 않았습니다.")
    End If
End Sub

Private Sub AddLocationRows(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, _
                            ByRef outRow As Long, ByVal list As CSLCList, ByVal label As String)
    Dim sample As Variant
    PutRow ws, buffer, fill, outRow, Array("발생위치 안내", label, "", "", "", LocationSummary(list) & "; 특정 셀이 잘못되었다는 뜻이 아닙니다.")
    For Each sample In list.OccurrenceSamples
        PutRow ws, buffer, fill, outRow, Array("발생위치 표본", label, Mid$(CStr(sample(0)), 4), sample(1), sample(2), "목록의 원본 위치는 요약을 확인하세요.")
    Next sample
End Sub

Private Sub WriteVariants(ByVal ws As Worksheet, ByVal a As CSLCList, ByVal b As CSLCList)
    Dim keys As Variant, k As Variant, rawA As String, rawB As String, tick As Long
    Dim buffer() As Variant, fill As Long, outRow As Long
    WriteHeaders ws, Array("구분", "비교에 쓴 값", "기준 원문", "같은 값으로 묶인 원문", "목록", "기준 주소", "다른 원문 주소")
    InitBuffer buffer, 7
    outRow = 2
    If Not b Is Nothing Then
        keys = a.Counts.Keys
        For Each k In keys
            If b.Counts.Exists(CStr(k)) Then
                rawA = DictText(a.Examples, CStr(k))
                rawB = DictText(b.Examples, CStr(k))
                If StrComp(rawA, rawB, vbBinaryCompare) <> 0 Then
                    PutRow ws, buffer, fill, outRow, Array("두 목록 대표 원문 차이", Mid$(CStr(k), 4), rawA, rawB, _
                        "첫 번째 / 두 번째", DictText(a.Addresses, CStr(k)), DictText(b.Addresses, CStr(k)))
                End If
            End If
            tick = tick + 1
            If tick Mod 128 = 0 Then SLC_WorkCheckpoint
        Next k
    End If
    AddVariantRows ws, buffer, fill, outRow, a, "첫 번째"
    If Not b Is Nothing Then AddVariantRows ws, buffer, fill, outRow, b, "두 번째"
    If outRow = 2 And fill = 0 Then
        PutRow ws, buffer, fill, outRow, Array("저장된 원문 차이 없음", "표본에 없는 원문 차이는 확인할 수 없습니다. 요약의 표본 한도·생략 수를 확인하세요.")
    End If
    PutRow ws, buffer, fill, outRow, Array("읽는 방법", "이 시트는 같은 비교값으로 묶인 원문을 보여줍니다. 목록 전체의 값·개수 일치 판정은 요약을 확인하세요.")
    FlushRows ws, buffer, fill, outRow
    FormatTable ws, outRow - 1, 7, True
    ws.Columns("A").ColumnWidth = 25
    ws.Columns("B").ColumnWidth = 28
    ws.Columns("C:D").ColumnWidth = 38
    ws.Columns("E").ColumnWidth = 22
    ws.Columns("F:G").ColumnWidth = 18
End Sub

Private Sub AddVariantRows(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, _
                           ByRef outRow As Long, ByVal list As CSLCList, ByVal label As String)
    Dim sample As Variant, key As String
    For Each sample In list.VariantSamples
        key = CStr(sample(0))
        PutRow ws, buffer, fill, outRow, Array("목록 안의 원문 변형", Mid$(key, 4), DictText(list.Examples, key), _
            sample(1), label, DictText(list.Addresses, key), sample(2))
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

Private Sub WriteHeaders(ByVal ws As Worksheet, ByVal labels As Variant)
    Dim values() As Variant, i As Long
    ReDim values(1 To 1, 1 To UBound(labels) + 1)
    For i = 0 To UBound(labels)
        values(1, i + 1) = labels(i)
    Next i
    ws.Cells(1, 1).Resize(1, UBound(labels) + 1).NumberFormat = "@"
    ws.Cells(1, 1).Resize(1, UBound(labels) + 1).Value2 = values
End Sub

Private Sub FormatTable(ByVal ws As Worksheet, ByVal lastRow As Long, ByVal columns As Long, ByVal filter As Boolean)
    Dim used As Range
    SLC_WorkCheckpoint
    Set used = ws.Cells(1, 1).Resize(lastRow, columns)
    used.Font.Name = "맑은 고딕"
    used.Font.Size = 10
    used.VerticalAlignment = xlTop
    used.WrapText = True
    used.RowHeight = 32
    With ws.Cells(1, 1).Resize(1, columns)
        .Interior.Color = RGB(30, 65, 92)
        .Font.Color = RGB(255, 255, 255)
        .Font.Bold = True
        .RowHeight = 36
    End With
    If filter Then used.AutoFilter
    ws.Activate
    With ws.Parent.Windows(1)
        .FreezePanes = False
        .SplitColumn = 0
        .SplitRow = 1
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
    AddTestValue sample, "case", "A1"
    For i = 1 To 7
        AddTestValue sample, String$(i, " ") & "CASE", "A" & CStr(i + 1)
    Next i
    AssertReport sample.Total = 8 And sample.Counts.Count = 1, "Samples changed comparison counts"
    AssertReport sample.OccurrenceSamples.Count = 5 And sample.OmittedOccurrences = 3, "Per-key occurrence bound"
    AssertReport sample.VariantSamples.Count = 5 And sample.OmittedVariantCandidates = 2, "Per-key variant bound"
    AddTestValue sample, " CASE", "A9"
    AssertReport sample.VariantSamples.Count = 5 And sample.OmittedVariantCandidates = 2, "Known variants should not count as omitted"
    Set sample = New CSLCList
    For i = 1 To 1300
        AddTestValue sample, "item-" & CStr(i), "A" & CStr(i)
    Next i
    AssertReport sample.OccurrenceSamples.Count = 1200 And sample.OmittedOccurrences = 100, "Global occurrence bound"
    AssertReport sample.Total = 1300 And sample.Counts.Count = 1300, "Occurrence truncation changed counts"
    Set sample = New CSLCList
    For i = 1 To 605
        AddTestValue sample, "key-" & CStr(i), "A" & CStr(i)
        AddTestValue sample, " KEY-" & CStr(i) & " ", "B" & CStr(i)
    Next i
    AssertReport sample.VariantSamples.Count = 600 And sample.OmittedVariantCandidates = 5, "Global variant bound"
    AssertReport sample.Total = 1210 And sample.Counts.Count = 605, "Variant truncation changed counts"
    For i = 1 To 201
        sample.ErrorCount = sample.ErrorCount + 1
        sample.AddError "C" & CStr(i), "#N/A"
    Next i
    AssertReport sample.ErrorSamples.Count = 200 And sample.OmittedErrors = 1, "Error bound"
    Set a = New CSLCList
    Set b = New CSLCList
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
    AssertReport testBook.Worksheets.Count = 4, "Comparison sheet count"
    AssertReport testBook.Worksheets(1).Name = "요약", "Summary sheet"
    AssertReport testBook.Worksheets(2).Name = "차이·중복", "Differences sheet"
    AssertReport testBook.Worksheets(3).Name = "제외·발생위치", "Locations sheet"
    AssertReport testBook.Worksheets(4).Name = "규칙으로 같아진 값", "Variants sheet"
    AssertReport CStr(testBook.Worksheets(3).Cells(2, 4).Value2) = "#N/A", "Error label"
    AssertReport CStr(testBook.Worksheets(3).Cells(2, 5).Value2) = "A9", "Error address"
    AssertReport CStr(testBook.Worksheets(4).Cells(2, 1).Value2) = "두 목록 대표 원문 차이", "Cross-list normalization evidence"
    AssertReport CStr(testBook.Worksheets(4).Cells(3, 1).Value2) = "목록 안의 원문 변형", "Within-list normalization evidence"
    For Each ws In testBook.Worksheets
        formulaState = ws.UsedRange.HasFormula
        AssertReport Not IsNull(formulaState), "Mixed formulas in report"
        AssertReport Not CBool(formulaState), "Formula activated in report"
        ws.Activate
        AssertReport testBook.Windows(1).FreezePanes And testBook.Windows(1).SplitRow = 1, "Only header row must be frozen"
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
    AssertReport testBook.Worksheets.Count = 4, "Identical inputs must have a report"
    AssertReport CStr(testBook.Worksheets(2).Cells(2, 1).Value2) = "차이·중복 없음", "Empty differences explanation"
    AssertReport CLng(testBook.Worksheets(1).Cells(10, 2).Value2) = 1, "Identical result must preserve exclusions"
    testBook.Close SaveChanges:=False
    Set testBook = Nothing
    Set testBook = WriteReport(a, absent, 0, 0, 0)
    AssertReport testBook.Worksheets.Count = 3, "Preview sheet count"
    AssertReport CStr(testBook.Worksheets(1).Cells(2, 2).Value2) = "담은 첫 번째 목록 확인 (비교 전)", "Preview heading"
    testBook.Close SaveChanges:=False
    Set testBook = Nothing
    If Not oldBook Is Nothing Then oldBook.Activate
    Application.EnableCancelKey = oldCancel
    DisarmTestAbort
    mTestAbortFired = False
    SLC_ReportTests = "PASS: injected cancellation/failure output rollback (not physical Esc); bounded samples, error locations, normalization evidence, 4-sheet comparison, identical report, 3-sheet preview, formula safety, header freeze"
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
    key = SLC_Normalize(raw)
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
