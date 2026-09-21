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
    SLC_WorkStatus SLC_U("D655 C778 D560 0020 B0B4 C6A9 0020 C815 B9AC 0020 C911")
    SLC_WorkCheckpoint
    Set wb = Application.Workbooks.Add(xlWBATWorksheet)
    Set summary = wb.Worksheets(1)
    If b Is Nothing Then
        summary.Name = SLC_U("C694 C57D")
        WriteSummary summary, a, b, matched, excessA, excessB
        SLC_WorkStatus SLC_U("AC12 ACFC 0020 C140 0020 C704 CE58 0020 C815 B9AC 0020 C911")
        Set ws = AddSheet(wb, SLC_U("AC12 ACFC 0020 C704 CE58"))
        WriteLocations ws, a, b
    Else
        summary.Name = SLC_U("BA85 B2E8 BE44 AD50 005F ACB0 ACFC")
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
        result = SLC_U("B2F4 C544 0020 B454 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D C785 B2C8 B2E4 002E 0020 C544 C9C1 0020 BE44 AD50 D558 C9C0 0020 C54A C558 C2B5 B2C8 B2E4 002E")
    ElseIf excessA = 0 And excessB = 0 Then
        result = SLC_U("B450 0020 BAA9 B85D C758 0020 AC12 ACFC 0020 AC1C C218 AC00 0020 AC19 C2B5 B2C8 B2E4 002E")
    Else
        result = SLC_U("B450 0020 BAA9 B85D C758 0020 AC12 C774 B098 0020 AC1C C218 AC00 0020 B2E4 B985 B2C8 B2E4 002E")
    End If
    rows.Add Array(SLC_U("D655 C778 0020 C911 C778 0020 BAA9 B85D"), result)
    rows.Add Array(SLC_U("AC00 C838 C628 0020 D30C C77C 00B7 C2DC D2B8 00B7 BC94 C704"), a.Source)
    rows.Add Array(SLC_U("B2F4 C740 0020 C2DC AC01"), Format$(a.CapturedAt, "yyyy-mm-dd hh:nn:ss"))
    rows.Add Array(SLC_U("BE44 AD50 D560 0020 AC12 C758 0020 AC1C C218"), a.Total)
    rows.Add Array(SLC_U("C911 BCF5 C744 0020 BE80 0020 AC12 C758 0020 AC1C C218"), a.Counts.Count)
    rows.Add Array(SLC_U("AC19 C740 0020 AC12 C758 0020 CD94 AC00 0020 AC1C C218"), CStr(a.DuplicateExcess) & SLC_U("AC1C 0020 0028 C608 003A 0020 AC19 C740 0020 AC12 C774 0020 0033 AC1C C774 BA74 0020 CD94 AC00 0020 AC1C C218 B294 0020 0032 AC1C 0029"))
    rows.Add Array(SLC_U("BE44 AD50 C5D0 C11C 0020 BE80 0020 C140"), ExclusionText(a))
    rows.Add Array(SLC_U("AC12 ACFC 0020 C140 0020 C704 CE58 0020 D45C C2DC"), LocationSummary(a))
    rows.Add Array(SLC_U("C624 B958 0020 C140 0020 C704 CE58 0020 D45C C2DC"), ErrorSummary(a))
    rows.Add Array(SLC_U("C77C BD80 B9CC 0020 D45C C2DC D558 B294 0020 C774 C720"), SLC_U("005B AC12 ACFC 0020 C704 CE58 005D C5D0 B294 0020 CD5C B300 0020 0031 002C 0032 0030 0030 AC1C 002C 0020 AC19 C740 0020 AC12 C740 0020 0035 AC1C 002C 0020 C624 B958 B294 0020 0032 0030 0030 AC1C AE4C C9C0 0020 D45C C2DC D569 B2C8 B2E4 002E 0020 BE44 AD50 D560 0020 B54C B294 0020 C804 CCB4 0020 AC1C C218 B97C 0020 C149 B2C8 B2E4 002E"))
    rows.Add Array(SLC_U("BE44 AD50 0020 C124 C815"), SLC_RulesText(a.CompareFullEmail, a.IgnoreCase))
    rows.Add Array(SLC_U("BE44 AD50 C5D0 C11C 0020 BE60 C9C0 B294 0020 C140"), SLC_U("C228 AE34 0020 C140 ACFC 0020 D544 D130 B85C 0020 AC00 B824 C9C4 0020 C140 C740 0020 C77D C9C0 0020 C54A C73C BA70 0020 AC1C C218 B3C4 0020 C138 C9C0 0020 C54A C2B5 B2C8 B2E4 002E 0020 C77C BC18 0020 BC94 C704 C758 0020 C81C BAA9 C740 0020 C9C1 C811 0020 BE7C ACE0 0020 C120 D0DD D558 C138 C694 002E"))
    rows.Add Array(SLC_U("C6D0 BCF8 C744 0020 C218 C815 D588 B2E4 BA74"), SLC_U("C218 C815 D55C 0020 BC94 C704 B97C 0020 B2E4 C2DC 0020 B2F4 C73C C138 C694 002E 0020 C774 0020 D30C C77C C740 0020 B2F4 C558 C744 0020 B54C C758 0020 B0B4 C6A9 C774 BA70 0020 C790 B3D9 C73C B85C 0020 BC14 B00C C9C0 0020 C54A C2B5 B2C8 B2E4 002E"))
    rows.Add Array(SLC_U("C800 C7A5 D558 AE30"), SLC_U("C774 0020 D655 C778 C6A9 0020 D30C C77C C740 0020 D544 C694 D560 0020 B54C 0020 C9C1 C811 0020 C800 C7A5 D558 C138 C694 002E 0020 0045 0078 0063 0065 006C C744 0020 C644 C804 D788 0020 C885 B8CC D558 BA74 0020 AE30 C5B5 D55C 0020 CCAB 0020 BAA9 B85D C740 0020 C0AC B77C C9D1 B2C8 B2E4 002E"))
    InitBuffer buffer, 2
    outRow = 2
    WriteHeaders ws, Array(SLC_U("D655 C778 D560 0020 B0B4 C6A9"), SLC_U("B2F4 C740 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D"))
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
    If list Is Nothing Then SourceOf = SLC_U("BE44 AD50 0020 C804") Else SourceOf = list.Source
End Function

Private Function CapturedOf(ByVal list As CSLCList) As String
    If list Is Nothing Then CapturedOf = SLC_U("BE44 AD50 0020 C804") Else CapturedOf = Format$(list.CapturedAt, "yyyy-mm-dd hh:nn:ss")
End Function

Private Function MetricOf(ByVal list As CSLCList, ByVal metric As String) As Variant
    If list Is Nothing Then MetricOf = SLC_U("BE44 AD50 0020 C804"): Exit Function
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
    If list Is Nothing Then LocationSummary = SLC_U("BE44 AD50 0020 C804"): Exit Function
    LocationSummary = SLC_U("D45C C2DC 0020") & list.OccurrenceSamples.Count & SLC_U("AC1C 0020 002F 0020 D45C C2DC D558 C9C0 0020 C54A C740 0020 C704 CE58 0020") & list.OmittedOccurrences & SLC_U("AC1C")
End Function

Private Function ErrorSummary(ByVal list As CSLCList) As String
    If list Is Nothing Then ErrorSummary = SLC_U("BE44 AD50 0020 C804"): Exit Function
    ErrorSummary = SLC_U("D45C C2DC 0020") & list.ErrorSamples.Count & SLC_U("AC1C 0020 002F 0020 D45C C2DC D558 C9C0 0020 C54A C740 0020 C624 B958 0020") & list.OmittedErrors & SLC_U("AC1C")
End Function

Private Sub WriteDifferences(ByVal ws As Worksheet, ByVal a As CSLCList, ByVal b As CSLCList)
    Dim keys As Variant, k As Variant, buffer() As Variant, fill As Long, outRow As Long, tick As Long
    InitBuffer buffer, 10
    outRow = 1
    PutRow ws, buffer, fill, outRow, Array(SLC_U("B450 0020 BAA9 B85D C758 0020 CC28 C774"), SLC_U("AC12 C774 B098 0020 AC1C C218 AC00 0020 B2E4 B978 0020 D56D BAA9 B9CC 0020 D45C C2DC D569 B2C8 B2E4 002E"))
    PutRow ws, buffer, fill, outRow, Array(SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D"), a.Source)
    PutRow ws, buffer, fill, outRow, Array(SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D"), b.Source)
    PutRow ws, buffer, fill, outRow, Array(SLC_U("B2F4 C740 0020 C2DC AC01"), SLC_U("CCAB 0020 BAA9 B85D 003A 0020") & Format$(a.CapturedAt, "yyyy-mm-dd hh:nn:ss"), SLC_U("B458 C9F8 0020 BAA9 B85D 003A 0020") & Format$(b.CapturedAt, "yyyy-mm-dd hh:nn:ss"))
    PutRow ws, buffer, fill, outRow, Array(SLC_U("BE44 AD50 D55C 0020 AC12 C758 0020 AC1C C218"), SLC_U("CCAB 0020 BAA9 B85D 003A 0020") & CStr(a.Total) & SLC_U("AC1C"), SLC_U("B458 C9F8 0020 BAA9 B85D 003A 0020") & CStr(b.Total) & SLC_U("AC1C"), SLC_U("C6D0 BCF8 0020 AC12 C740 0020 CC98 C74C 0020 BC1C ACAC D55C 0020 C140 C758 0020 C608 C785 B2C8 B2E4 002E"))
    PutRow ws, buffer, fill, outRow, Array(SLC_U("BE44 AD50 C5D0 C11C 0020 BE80 0020 C140"), SLC_U("CCAB 0020 BAA9 B85D 003A 0020") & ExclusionText(a), SLC_U("B458 C9F8 0020 BAA9 B85D 003A 0020") & ExclusionText(b), SLC_U("C228 AE34 0020 C140 00B7 D544 D130 B85C 0020 AC00 B824 C9C4 0020 C140 C740 0020 C81C C678 D569 B2C8 B2E4 002E 0020 C624 B958 0020 C140 C740 0020 BE44 AD50 D558 C9C0 0020 BABB D588 C2B5 B2C8 B2E4 002E"))
    PutRow ws, buffer, fill, outRow, Array(SLC_U("BE44 AD50 0020 C124 C815"), SLC_RulesText(a.CompareFullEmail, a.IgnoreCase), SLC_U("B354 0020 B9CE C740 0020 AC1C C218 C640 0020 C6D0 BCF8 0020 C140 0020 C704 CE58 003A 0020 0046 007E 004B C5F4 0020 C120 D0DD 0020 2192 0020 C6B0 D074 B9AD 0020 2192 0020 C228 AE30 AE30 0020 CDE8 C18C"))
    FlushRows ws, buffer, fill, outRow
    WriteHeaders ws, Array(SLC_U("CC28 C774"), SLC_U("BE44 AD50 D55C 0020 AC12"), SLC_U("CCAB 0020 BAA9 B85D 0020 C6D0 BCF8 0020 AC12 0020 0028 C608 0029"), SLC_U("CCAB 0020 BAA9 B85D 0020 AC1C C218"), _
        SLC_U("B458 C9F8 0020 BAA9 B85D 0020 C6D0 BCF8 0020 AC12 0020 0028 C608 0029"), SLC_U("B458 C9F8 0020 BAA9 B85D 0020 AC1C C218"), SLC_U("CCAB 0020 BAA9 B85D C774 0020 B354 0020 B9CE C740 0020 AC1C C218"), SLC_U("B458 C9F8 0020 BAA9 B85D C774 0020 B354 0020 B9CE C740 0020 AC1C C218"), SLC_U("CCAB 0020 BAA9 B85D 0020 C6D0 BCF8 0020 C140 0020 0028 C608 0029"), SLC_U("B458 C9F8 0020 BAA9 B85D 0020 C6D0 BCF8 0020 C140 0020 0028 C608 0029")), 8
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
    ExclusionText = SLC_U("BE48 CE78 0020") & CStr(list.BlankCount) & SLC_U("AC1C 0020 002F 0020 C624 B958 0020") & CStr(list.ErrorCount) & SLC_U("AC1C 0020 002F 0020 D45C 0020 C81C BAA9 00B7 D569 ACC4 0020") & CStr(list.MetadataCount) & SLC_U("AC1C")
End Function


Private Sub AddDifference(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, _
                          ByRef outRow As Long, ByVal a As CSLCList, ByVal b As CSLCList, ByVal key As String)
    Dim ca As Long, cb As Long, leftA As Long, leftB As Long, status As String
    ca = CountOf(a, key)
    cb = CountOf(b, key)
    If ca = cb Then Exit Sub
    If ca = 0 Then
        status = SLC_U("B458 C9F8 0020 BAA9 B85D C5D0 B9CC 0020 C788 C74C")
    ElseIf cb = 0 Then
        status = SLC_U("CCAB 0020 BAA9 B85D C5D0 B9CC 0020 C788 C74C")
    ElseIf ca <> cb Then
        status = SLC_U("AC1C C218 AC00 0020 B2E4 B984")
    Else
        status = SLC_U("C911 BCF5 0020 0028 AC1C C218 0020 C77C CE58 0029")
    End If
    If ca > cb Then leftA = ca - cb Else leftB = cb - ca
    PutRow ws, buffer, fill, outRow, Array(status, Mid$(key, 4), DictText(a.Examples, key), ca, DictText(b.Examples, key), cb, _
        leftA, leftB, DictText(a.Addresses, key), DictText(b.Addresses, key))
End Sub

Private Sub WriteLocations(ByVal ws As Worksheet, ByVal a As CSLCList, ByVal b As CSLCList)
    Dim buffer() As Variant, fill As Long, outRow As Long
    WriteHeaders ws, Array(SLC_U("AD6C BD84"), SLC_U("BAA9 B85D"), SLC_U("BE44 AD50 D55C 0020 AC12"), SLC_U("C6D0 BCF8 0020 AC12 0020 002F 0020 C624 B958"), SLC_U("C6D0 BCF8 0020 C140 0020 C704 CE58"), SLC_U("C548 B0B4"))
    InitBuffer buffer, 6
    outRow = 2
    AddErrorRows ws, buffer, fill, outRow, a, SLC_U("CCAB 0020 BC88 C9F8")
    If Not b Is Nothing Then AddErrorRows ws, buffer, fill, outRow, b, SLC_U("B450 0020 BC88 C9F8")
    AddLocationRows ws, buffer, fill, outRow, a, SLC_U("CCAB 0020 BC88 C9F8")
    If Not b Is Nothing Then AddLocationRows ws, buffer, fill, outRow, b, SLC_U("B450 0020 BC88 C9F8")
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
        PutRow ws, buffer, fill, outRow, Array(SLC_U("C624 B958 0020 C548 B0B4"), label, "", SLC_U("D45C C2DC D560 0020 C624 B958 0020 C5C6 C74C"), "", ErrorSummary(list))
    Else
        For Each sample In list.ErrorSamples
            PutRow ws, buffer, fill, outRow, Array(SLC_U("BE44 AD50 C5D0 C11C 0020 BE80 0020 C624 B958"), label, "", sample(1), sample(0), SLC_U("C6D0 BCF8 C5D0 C11C 0020 C624 B958 B97C 0020 D655 C778 D558 C138 C694 002E"))
        Next sample
    End If
    If list.OmittedErrors > 0 Then
        PutRow ws, buffer, fill, outRow, Array(SLC_U("CD94 AC00 0020 C624 B958"), label, "", "", "", CStr(list.OmittedErrors) & SLC_U("AC1C B294 0020 D45C C2DC 0020 D55C B3C4 B97C 0020 B118 C5B4 0020 C704 CE58 B97C 0020 D45C C2DC D558 C9C0 0020 C54A C558 C2B5 B2C8 B2E4 002E"))
    End If
End Sub

Private Sub AddLocationRows(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, _
                            ByRef outRow As Long, ByVal list As CSLCList, ByVal label As String)
    Dim sample As Variant
    PutRow ws, buffer, fill, outRow, Array(SLC_U("C704 CE58 0020 C548 B0B4"), label, "", SLC_U("C6D0 BCF8 0020 D30C C77C 00B7 C2DC D2B8 B294 0020 005B C694 C57D 005D C5D0 C11C 0020 D655 C778 D558 C138 C694 002E"), "", LocationSummary(list))
    For Each sample In list.OccurrenceSamples
        PutRow ws, buffer, fill, outRow, Array(SLC_U("B2F4 C740 0020 AC12"), label, Mid$(CStr(sample(0)), 4), sample(1), sample(2), "")
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
    used.Font.Name = SLC_U("B9D1 C740 0020 ACE0 B515")
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
    AssertReport testBook.Worksheets(1).Name = SLC_U("BA85 B2E8 BE44 AD50 005F ACB0 ACFC"), "RC9 compatible sheet name"
    AssertReport testBook.Worksheets(1).Cells(8, 3).Value2 = SLC_U("CCAB 0020 BAA9 B85D 0020 C6D0 BCF8 0020 AC12 0020 0028 C608 0029"), "RC9 compatible columns"
    AssertReport InStr(CStr(testBook.Worksheets(1).Cells(6, 2).Value2), SLC_U("C624 B958 0020 0031")) > 0, "Excluded errors disclosed"
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
    AssertReport CStr(testBook.Worksheets(1).Cells(2, 2).Value2) = SLC_U("B2F4 C544 0020 B454 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D C785 B2C8 B2E4 002E 0020 C544 C9C1 0020 BE44 AD50 D558 C9C0 0020 C54A C558 C2B5 B2C8 B2E4 002E"), "Preview heading"
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
