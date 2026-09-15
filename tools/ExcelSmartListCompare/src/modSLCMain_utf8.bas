Attribute VB_Name = "modSLCMain"
Option Explicit

Private Const VERSION_TEXT As String = "0.2.0"
Private Const UI_TAG As String = "SLC_68A45C44_2026"
Private Const BAR_NAME As String = "SLC_68A45C44_Toolbar"
Private Const MAX_VISIBLE As Long = 100000
Private Const WARN_VISIBLE As Long = 20000
Private Const MAX_SCAN As Double = 2000000#
Private Const WARN_SCAN As Double = 200000#
Private Const MAX_AREAS As Long = 5000
Private Const WARN_AREAS As Long = 500
Private Const MAX_ITEM_CHARS As Long = 4096
Private Const MAX_RAW_CHARS As Long = 5000000
Private Const CHUNK_CELLS As Long = 8192
Private Const MAX_ACTIVE_SECONDS As Double = 30#
Private Const ERR_LIMIT As Long = vbObjectError + 2101
Private Const ERR_DATA As Long = vbObjectError + 2102
Private Const ERR_TIME As Long = vbObjectError + 2103
Private Const ERR_CANCEL As Long = vbObjectError + 2104

Private mPending As CSLCList
Private mBusy As Boolean
Private mStarted As Double
Private mCancelled As Boolean
Private mUiAttached As Boolean
Private mOwnStatus As Boolean
Private mPreviousStatus As Variant
Private mLastStatus As String

Public Function SLC_Version() As String
    SLC_Version = VERSION_TEXT
End Function

Public Function SLC_UiReady() As Boolean
    SLC_UiReady = mUiAttached
End Function

Public Sub Auto_Open()
    SLC_AttachUI
End Sub
Public Sub Auto_Add()
    SLC_AttachUI
End Sub
Public Sub Auto_Close()
    SLC_DetachUI
End Sub
Public Sub Auto_Remove()
    SLC_DetachUI
End Sub

' Never calls OnKey, CommandBars.Reset, SendKeys, or changes the clipboard.
Public Sub SLC_AttachUI()
    Dim bar As CommandBar, menuName As Variant, pop As CommandBarPopup
    On Error GoTo Failed
    If mUiAttached Then Exit Sub
    RemoveOwnUI
    Set bar = Application.CommandBars.Add(Name:=BAR_NAME, Position:=msoBarTop, Temporary:=True)
    AddButton bar.Controls, "명단 비교", "SLC_Run", "run"
    AddButton bar.Controls, "", "", "pending"
    AddButton bar.Controls, "첫 번째 목록 비우기", "SLC_Clear", "clear"
    AddButton bar.Controls, "첫 번째 목록 바꾸기", "SLC_Replace", "replace"
    AddButton bar.Controls, "사용 안내", "SLC_About", "about"
    bar.Visible = True
    For Each menuName In Array("Cell", "Row", "Column")
        Set bar = Nothing
        On Error Resume Next
        Set bar = Application.CommandBars(CStr(menuName))
        On Error GoTo Failed
        If Not bar Is Nothing Then
            Set pop = bar.Controls.Add(Type:=msoControlPopup, Temporary:=True)
            pop.Tag = UI_TAG
            pop.Caption = "명단 비교"
            AddButton pop.Controls, "명단 비교", "SLC_Run", "run"
            AddButton pop.Controls, "", "", "pending"
            AddButton pop.Controls, "첫 번째 목록 비우기", "SLC_Clear", "clear"
            AddButton pop.Controls, "첫 번째 목록 바꾸기", "SLC_Replace", "replace"
            AddButton pop.Controls, "사용 안내", "SLC_About", "about"
        End If
    Next menuName
    mUiAttached = True
    RefreshUI
    Exit Sub
Failed:
    RemoveOwnUI
    mUiAttached = False
End Sub

Private Sub AddButton(ByVal controls As CommandBarControls, ByVal caption As String, _
                      ByVal procedureName As String, ByVal suffix As String)
    Dim button As CommandBarButton
    Set button = controls.Add(Type:=msoControlButton, Temporary:=True)
    button.Caption = caption
    button.Tag = UI_TAG & "." & suffix
    button.Style = msoButtonCaption
    If Len(procedureName) > 0 Then
        button.OnAction = "'" & Replace(ThisWorkbook.Name, "'", "''") & "'!" & procedureName
    Else
        ' A read-only count beside the action, visible only while a list is stored.
        button.Enabled = False
        button.Visible = False
    End If
End Sub

Private Sub RemoveOwnUI()
    Dim n As Variant, bar As CommandBar, i As Long
    On Error Resume Next
    For Each n In Array("Cell", "Row", "Column")
        Set bar = Nothing
        Set bar = Application.CommandBars(CStr(n))
        If Not bar Is Nothing Then
            For i = bar.Controls.Count To 1 Step -1
                If bar.Controls(i).Tag = UI_TAG Then bar.Controls(i).Delete
            Next i
        End If
    Next n
    Application.CommandBars(BAR_NAME).Delete
    On Error GoTo 0
End Sub

Public Sub SLC_DetachUI()
    If mBusy Then mCancelled = True
    Set mPending = Nothing
    ReleaseStatus
    RemoveOwnUI
    mUiAttached = False
End Sub

Private Sub RefreshUI()
    Dim bar As CommandBar, n As Variant, ctl As CommandBarControl, child As CommandBarControl
    Dim popup As CommandBarPopup
    Dim title As String, pendingTitle As String
    If mPending Is Nothing Then
        title = "첫 번째 목록 담기"
    Else
        title = "두 번째 목록과 비교"
        pendingTitle = "첫 번째 목록: " & Format$(mPending.Total, "#,##0") & "개 항목"
    End If
    On Error Resume Next
    For Each n In Array(BAR_NAME, "Cell", "Row", "Column")
        Set bar = Nothing
        Set bar = Application.CommandBars(CStr(n))
        If Not bar Is Nothing Then
            For Each ctl In bar.Controls
                If ctl.Tag = UI_TAG & ".run" Then ctl.Caption = title
                If ctl.Tag = UI_TAG & ".pending" Then
                    ctl.Caption = pendingTitle
                    ctl.Visible = (Len(pendingTitle) > 0)
                End If
                If ctl.Tag = UI_TAG Then
                    Set popup = ctl
                    For Each child In popup.Controls
                        If child.Tag = UI_TAG & ".run" Then child.Caption = title
                        If child.Tag = UI_TAG & ".pending" Then
                            child.Caption = pendingTitle
                            child.Visible = (Len(pendingTitle) > 0)
                        End If
                    Next child
                End If
            Next ctl
        End If
    Next n
    On Error GoTo 0
End Sub

Public Sub SLC_Clear()
    If mBusy Then
        mCancelled = True
        Exit Sub
    End If
    Set mPending = Nothing
    ReleaseStatus
    RefreshUI
End Sub

Public Sub SLC_Replace()
    ' Transactional: a failed/cancelled replacement preserves the previous A.
    RunSelection True
End Sub

Public Sub SLC_Run()
    RunSelection False
End Sub

Private Sub RunSelection(ByVal replaceOnly As Boolean)
    Dim selected As Range, parts As Collection, exclusions As Collection
    Dim current As CSLCList
    Dim oldCancel As XlEnableCancelKey
    Dim errNo As Long, errText As String
    Dim setState As Boolean, combining As Boolean, oldInteractive As Boolean

    If mBusy Then Exit Sub
    On Error GoTo Failed
    If TypeName(Application.Selection) <> "Range" Then
        MsgBox "비교할 셀 범위를 선택해 주세요.", vbInformation, "명단 비교"
        Exit Sub
    End If
    Set selected = Application.Selection
    If Application.ActiveWindow.SelectedSheets.Count > 1 Then
        MsgBox "그룹 선택된 시트를 해제하고 한 시트의 범위를 선택해 주세요.", vbInformation, "명단 비교"
        Exit Sub
    End If
    If Application.CalculationState <> xlDone Then
        MsgBox "Excel이 계산 중입니다. 계산이 끝난 뒤 다시 실행해 주세요.", vbInformation, "명단 비교"
        Exit Sub
    End If

    mBusy = True
    mCancelled = False
    mStarted = Timer
    oldCancel = Application.EnableCancelKey
    oldInteractive = Application.Interactive
    Application.EnableCancelKey = xlErrorHandler
    setState = True
    combining = Not (mPending Is Nothing)
    If replaceOnly Then combining = False
    Set parts = PrepareParts(selected, True, combining)
    If parts Is Nothing Then GoTo Finished
    mStarted = Timer
    ' Keep keyboard input available so EnableCancelKey can handle Esc.
    ' The selected Range is already captured and mBusy rejects re-entry.
    Set exclusions = MetadataRects(selected.Worksheet)
    Set current = ReadParts(selected, parts, exclusions)
    If current.Total = 0 Then
        ReleaseStatus
        MsgBox "화면에 남은 선택 셀에서 비교할 값을 찾지 못했습니다." & vbCrLf & _
               "빈칸·오류값·표 제목/합계 셀은 제외됩니다. 담아 둔 첫 번째 목록은 유지됩니다.", _
               vbInformation, "명단 비교"
        GoTo Finished
    End If
    If Not combining Then
        Set mPending = current
        SetStatus "첫 번째 목록: " & Format$(current.Total, "#,##0") & "개 항목"
    Else
        ShowComparison mPending, current
        Set mPending = Nothing
        ReleaseStatus
    End If
Finished:
    If setState Then
        Application.EnableCancelKey = oldCancel
        Application.Interactive = oldInteractive
    End If
    mBusy = False
    RefreshUI
    Exit Sub
Failed:
    errNo = Err.Number
    errText = Err.Description
    On Error Resume Next
    If setState Then
        Application.EnableCancelKey = oldCancel
        Application.Interactive = oldInteractive
    End If
    ReleaseStatus
    mBusy = False
    RefreshUI
    On Error GoTo 0
    If errNo = 18 Or errNo = ERR_CANCEL Then
        MsgBox "작업을 취소했습니다. 담아 둔 첫 번째 목록은 유지됩니다.", vbInformation, "명단 비교"
    Else
        MsgBox errText & vbCrLf & vbCrLf & "담아 둔 첫 번째 목록과 원본 데이터는 변경하지 않았습니다." & _
               vbCrLf & "오류 코드: " & CStr(errNo), vbExclamation, "명단 비교"
    End If
End Sub

' Metadata preflight: never reads cell values before size/fragment warnings.
Private Function PrepareParts(ByVal sel As Range, ByVal ask As Boolean, _
                              ByVal combining As Boolean) As Collection
    Dim bounded As Range, vis As Range, ar As Range, part As Range
    Dim parts As New Collection
    Dim scanCount As Double, visibleCount As Double, combinedCount As Double
    Dim mergeState As Variant, warned As Boolean, text As String
    Dim specialErr As Long

    If sel.Areas.Count > MAX_AREAS Then
        Err.Raise ERR_LIMIT, , "선택 영역 조각이 5,000개를 초과합니다. 범위를 줄여 주세요."
    End If
    ' Intersect, not Find: never changes the user's Find/Replace settings.
    Set bounded = Application.Intersect(sel, sel.Worksheet.UsedRange)
    If bounded Is Nothing Then
        Set PrepareParts = parts
        Exit Function
    End If
    scanCount = CDbl(bounded.CountLarge)
    If scanCount > MAX_SCAN Then
        Err.Raise ERR_LIMIT, , "가시성 확인 대상이 2,000,000셀을 초과합니다." & vbCrLf & _
            "전체 행/열 대신 실제 값이 있는 작은 범위를 선택해 주세요."
    End If
    If bounded.Areas.Count > MAX_AREAS Then
        Err.Raise ERR_LIMIT, , "선택 영역 조각이 5,000개를 초과합니다."
    End If
    If scanCount >= WARN_SCAN Or bounded.Areas.Count >= WARN_AREAS Then
        text = "선택 범위의 가시성을 확인하는 데 시간이 걸릴 수 있습니다." & vbCrLf & _
            "확인 대상: " & Format$(scanCount, "#,##0") & "셀" & vbCrLf & _
            "필터/숨김 확인 후 보이는 셀만 읽습니다." & vbCrLf & _
            "값 읽기·비교를 계속할까요? [아니요]가 기본입니다."
        If ask Then
            If MsgBox(text, vbYesNo + vbExclamation + vbDefaultButton2, "명단 비교 - 대량 작업") <> vbYes Then Exit Function
        End If
        warned = True
        mStarted = Timer
    End If
    For Each ar In bounded.Areas
        Checkpoint
        mergeState = ar.MergeCells
        If IsNull(mergeState) Then
            Err.Raise ERR_DATA, , "병합 셀이 섞여 있습니다. 병합 셀을 제외한 값 범위를 선택해 주세요."
        ElseIf CBool(mergeState) Then
            Err.Raise ERR_DATA, , "병합 셀은 비교하지 않습니다. 병합되지 않은 값 범위를 선택해 주세요."
        End If
        Set vis = Nothing
        If ar.CountLarge = 1 Then
            ' SpecialCells on one cell can broaden its scope. Handle explicitly.
            If Not ar.EntireRow.Hidden And Not ar.EntireColumn.Hidden Then Set vis = ar
        Else
            On Error Resume Next
            Set vis = ar.SpecialCells(xlCellTypeVisible)
            specialErr = Err.Number
            Err.Clear
            On Error GoTo 0
            If specialErr <> 0 Then
                If specialErr <> 1004 Then
                    Err.Raise specialErr, , "보이는 셀을 확인하지 못했습니다."
                ElseIf Not EntirelyHidden(ar) Then
                    ' 1004 is ambiguous: do not silently turn a visibility failure into an empty list.
                    Err.Raise ERR_DATA, , "보이는 셀을 안전하게 확인하지 못했습니다. 선택 범위를 줄여 주세요."
                End If
            End If
            If Not vis Is Nothing Then Set vis = Application.Intersect(ar, vis)
        End If
        If Not vis Is Nothing Then
            If parts.Count + vis.Areas.Count > MAX_AREAS Then
                Err.Raise ERR_LIMIT, , "필터로 나뉜 가시 영역이 5,000개를 초과합니다. 선택 범위를 줄여 주세요."
            End If
            visibleCount = visibleCount + CDbl(vis.CountLarge)
            If visibleCount > MAX_VISIBLE Then
                Err.Raise ERR_LIMIT, , "한 목록은 보이는 선택 셀 100,000개까지 처리합니다." & vbCrLf & _
                    "빈칸을 포함한 안전 상한입니다. 숨겨진 셀은 이 수에 넣지 않습니다."
            End If
            For Each part In vis.Areas
                parts.Add part
            Next part
        End If
    Next ar
    combinedCount = visibleCount
    If combining Then combinedCount = combinedCount + mPending.VisibleCellCount
    If Not warned Then
        If combinedCount >= WARN_VISIBLE Or parts.Count >= WARN_AREAS Then
            text = "읽기·비교·결과 출력에 시간이 걸릴 수 있습니다." & vbCrLf & _
                   "이번 선택: 보이는 " & Format$(visibleCount, "#,##0") & "셀 / " & _
                   Format$(parts.Count, "#,##0") & "개 영역" & vbCrLf & _
                   "전체 처리 규모: " & Format$(combinedCount, "#,##0") & "셀" & vbCrLf & _
                   "계속할까요? 실행 중 Esc로 취소할 수 있습니다."
            If ask Then
                If MsgBox(text, vbYesNo + vbExclamation + vbDefaultButton2, "명단 비교 - 대량 작업") <> vbYes Then Exit Function
            End If
        End If
    End If
    Set PrepareParts = parts
End Function

Private Function EntirelyHidden(ByVal rng As Range) As Boolean
    Dim hidden As Variant
    hidden = rng.EntireRow.Hidden
    If Not IsNull(hidden) Then
        If CBool(hidden) Then EntirelyHidden = True: Exit Function
    End If
    hidden = rng.EntireColumn.Hidden
    If Not IsNull(hidden) Then
        If CBool(hidden) Then EntirelyHidden = True
    End If
End Function

Private Function MetadataRects(ByVal ws As Worksheet) As Collection
    Dim rects As New Collection, lo As ListObject, hdr As Range, af As AutoFilter
    On Error Resume Next
    Set af = ws.AutoFilter
    On Error GoTo 0
    If Not af Is Nothing Then AddRect rects, af.Range.Rows(1)
    For Each lo In ws.ListObjects
        Set hdr = Nothing
        On Error Resume Next
        Set hdr = lo.HeaderRowRange
        On Error GoTo 0
        If Not hdr Is Nothing Then AddRect rects, hdr
        If lo.ShowTotals Then
            Set hdr = Nothing
            On Error Resume Next
            Set hdr = lo.TotalsRowRange
            On Error GoTo 0
            If Not hdr Is Nothing Then AddRect rects, hdr
        End If
    Next lo
    Set MetadataRects = rects
End Function

Private Sub AddRect(ByVal rects As Collection, ByVal rng As Range)
    rects.Add Array(rng.Row, rng.Row + rng.Rows.Count - 1, rng.Column, rng.Column + rng.Columns.Count - 1)
End Sub

Private Function IsMetadata(ByVal r As Long, ByVal c As Long, ByVal rects As Collection) As Boolean
    Dim box As Variant
    For Each box In rects
        If r >= box(0) And r <= box(1) And c >= box(2) And c <= box(3) Then
            IsMetadata = True
            Exit Function
        End If
    Next box
End Function

Private Function ReadParts(ByVal sel As Range, ByVal parts As Collection, ByVal exclusions As Collection) As CSLCList
    Dim result As New CSLCList, seen As Object
    Dim ar As Range, block As Range, vals As Variant, v As Variant
    Dim r0 As Long, takeRows As Long, rowStep As Long, nr As Long, nc As Long
    Dim r As Long, c As Long, absR As Long, absC As Long, tick As Long
    Dim coordinate As String
    Set seen = CreateObject("Scripting.Dictionary")
    result.Source = SourceLabel(sel)
    result.CapturedAt = Now
    result.FragmentCount = parts.Count
    For Each ar In parts
        Checkpoint
        nr = ar.Rows.Count
        nc = ar.Columns.Count
        rowStep = CHUNK_CELLS \ nc
        If rowStep < 1 Then rowStep = 1
        For r0 = 1 To nr Step rowStep
            Checkpoint
            takeRows = rowStep
            If r0 + takeRows - 1 > nr Then takeRows = nr - r0 + 1
            Set block = ar.Cells(r0, 1).Resize(takeRows, nc)
            vals = block.Value2
            For r = 1 To takeRows
                absR = block.Row + r - 1
                For c = 1 To nc
                    absC = block.Column + c - 1
                    coordinate = CStr(absR) & ":" & CStr(absC)
                    If Not seen.Exists(coordinate) Then
                        seen.Add coordinate, True
                        result.VisibleCellCount = result.VisibleCellCount + 1
                        If IsMetadata(absR, absC, exclusions) Then
                            result.MetadataCount = result.MetadataCount + 1
                        Else
                            If takeRows = 1 And nc = 1 Then v = vals Else v = vals(r, c)
                            AddValue result, v, CellAddress(absR, absC)
                        End If
                    End If
                    tick = tick + 1
                    If tick Mod 512 = 0 Then
                        SetStatus "명단 비교: " & Format$(result.VisibleCellCount, "#,##0") & "셀 처리 중 / Esc 취소"
                        Checkpoint
                    End If
                Next c
            Next r
        Next r0
    Next ar
    Set ReadParts = result
End Function

Private Sub AddValue(ByVal list As CSLCList, ByVal v As Variant, ByVal address As String)
    Dim raw As String, key As String
    If IsError(v) Then
        list.ErrorCount = list.ErrorCount + 1
        Exit Sub
    End If
    If IsEmpty(v) Or IsNull(v) Then
        list.BlankCount = list.BlankCount + 1
        Exit Sub
    End If
    raw = CStr(v)
    If Len(raw) > MAX_ITEM_CHARS Then
        Err.Raise ERR_LIMIT, , address & ": 셀 하나의 값이 4,096자를 초과합니다. 목록 범위를 다시 확인해 주세요."
    End If
    list.RawCharCount = list.RawCharCount + Len(raw)
    If list.RawCharCount > MAX_RAW_CHARS Then
        Err.Raise ERR_LIMIT, , "한 목록의 전체 텍스트가 5,000,000자를 초과합니다. 범위를 줄여 주세요."
    End If
    key = SLC_Normalize(v)
    If Len(key) = 0 Then
        list.BlankCount = list.BlankCount + 1
        Exit Sub
    End If
    list.Total = list.Total + 1
    If list.Counts.Exists(key) Then
        list.Counts(key) = CLng(list.Counts(key)) + 1
        list.DuplicateExcess = list.DuplicateExcess + 1
    Else
        list.Counts.Add key, 1
        list.Examples.Add key, raw
        list.Addresses.Add key, address
    End If
End Sub

Private Function CellAddress(ByVal rowNum As Long, ByVal colNum As Long) As String
    Dim letters As String
    Do While colNum > 0
        colNum = colNum - 1
        letters = Chr$(65 + colNum Mod 26) & letters
        colNum = colNum \ 26
    Loop
    CellAddress = letters & CStr(rowNum)
End Function

Private Function SourceLabel(ByVal rng As Range) As String
    Dim ar As Range, s As String, n As Long
    For Each ar In rng.Areas
        n = n + 1
        If n > 6 Then Exit For
        If Len(s) > 0 Then s = s & ", "
        s = s & ar.Address(False, False)
    Next ar
    If rng.Areas.Count > 6 Then s = s & " ... (" & CStr(rng.Areas.Count) & " areas)"
    SourceLabel = rng.Worksheet.Parent.FullName & " / " & rng.Worksheet.Name & "!" & s
End Function

Private Sub Checkpoint()
    Dim elapsed As Double
    DoEvents
    If mCancelled Then Err.Raise ERR_CANCEL, , "Cancelled"
    elapsed = Timer - mStarted
    If elapsed < 0 Then elapsed = elapsed + 86400#
    If elapsed > MAX_ACTIVE_SECONDS Then
        Err.Raise ERR_TIME, , "지연 보호 한도(활성 처리 약 30초)에 도달해 중단했습니다. 범위를 줄여 주세요."
    End If
End Sub

Private Sub SetStatus(ByVal text As String)
    If Not mOwnStatus Then
        mPreviousStatus = Application.StatusBar
        mOwnStatus = True
    End If
    If mOwnStatus Then
        If CStr(Application.StatusBar) <> mLastStatus And Len(mLastStatus) > 0 Then
            mPreviousStatus = Application.StatusBar
        End If
    End If
    mLastStatus = text
    Application.StatusBar = text
End Sub

Private Sub ReleaseStatus()
    On Error Resume Next
    If mOwnStatus Then
        If VarType(Application.StatusBar) = vbString Then
            If CStr(Application.StatusBar) = mLastStatus Then Application.StatusBar = mPreviousStatus
        End If
    End If
    mOwnStatus = False
    On Error GoTo 0
End Sub

Private Function CountOf(ByVal list As CSLCList, ByVal key As String) As Long
    If list.Counts.Exists(key) Then CountOf = CLng(list.Counts(key))
End Function

Private Function DictText(ByVal dict As Object, ByVal key As String) As String
    If dict.Exists(key) Then DictText = CStr(dict(key))
End Function

Private Sub ShowComparison(ByVal a As CSLCList, ByVal b As CSLCList)
    Dim keys As Object, k As Variant, ca As Long, cb As Long
    Dim matched As Long, excessA As Long, excessB As Long, tick As Long
    Set keys = CreateObject("Scripting.Dictionary")
    For Each k In a.Counts.Keys
        keys.Add CStr(k), True
    Next k
    For Each k In b.Counts.Keys
        If Not keys.Exists(CStr(k)) Then keys.Add CStr(k), True
    Next k
    For Each k In keys.Keys
        ca = CountOf(a, CStr(k))
        cb = CountOf(b, CStr(k))
        If ca < cb Then matched = matched + ca Else matched = matched + cb
        If ca > cb Then excessA = excessA + ca - cb
        If cb > ca Then excessB = excessB + cb - ca
        tick = tick + 1
        If tick Mod 1024 = 0 Then Checkpoint
    Next k
    If excessA = 0 And excessB = 0 And a.DuplicateExcess = 0 And b.DuplicateExcess = 0 _
        And a.ErrorCount = 0 And b.ErrorCount = 0 Then
        ReleaseStatus
        MsgBox "두 목록의 값과 개수가 같습니다." & vbCrLf & _
            "첫 번째 목록: " & Format$(a.Total, "#,##0") & "개 항목" & vbCrLf & _
            "두 번째 목록: " & Format$(b.Total, "#,##0") & "개 항목" & vbCrLf & _
            "비교 규칙: 이메일 ID·숫자 표기·대소문자·공백 자동 정리", vbInformation, "명단 비교"
    Else
        WriteResults a, b, keys, matched, excessA, excessB
    End If
End Sub

Private Function OutputText(ByVal text As String) As String
    ' Defense in depth: no formula activation through raw values or filenames.
    If Len(text) > 0 Then
        Select Case Left$(text, 1)
            Case "=", "+", "-", "@", "'"
                text = "'" & text
        End Select
    End If
    OutputText = text
End Function

Private Sub WriteResults(ByVal a As CSLCList, ByVal b As CSLCList, ByVal keys As Object, _
                         ByVal matched As Long, ByVal excessA As Long, ByVal excessB As Long)
    Dim wb As Workbook, ws As Worksheet, oldBook As Workbook
    Dim oldScreen As Boolean, oldEvents As Boolean, setState As Boolean
    Dim k As Variant, ca As Long, cb As Long, status As String
    Dim buffer(1 To 4096, 1 To 10) As Variant, fill As Long, outRow As Long, tick As Long
    Dim headers(1 To 1, 1 To 10) As Variant
    Dim labels As Variant, i As Long, errNo As Long, errText As String
    On Error GoTo Failed
    oldScreen = Application.ScreenUpdating
    oldEvents = Application.EnableEvents
    Set oldBook = Application.ActiveWorkbook
    setState = True
    Application.EnableEvents = False
    Application.ScreenUpdating = False
    Set wb = Application.Workbooks.Add(xlWBATWorksheet)
    Set ws = wb.Worksheets(1)
    ws.Name = "명단비교_결과"
    ws.Range("A1:J8").NumberFormat = "@"
    ws.Range("A1:J1").Merge
    ws.Range("A1").Value2 = "명단 비교 결과"
    ws.Range("A2").Value2 = "첫 번째 목록 출처 / 시점"
    ws.Range("B2:J2").Merge
    ws.Range("B2").Value2 = OutputText(a.Source & " / " & Format$(a.CapturedAt, "yyyy-mm-dd hh:nn:ss"))
    ws.Range("A3").Value2 = "두 번째 목록 출처 / 시점"
    ws.Range("B3:J3").Merge
    ws.Range("B3").Value2 = OutputText(b.Source & " / " & Format$(b.CapturedAt, "yyyy-mm-dd hh:nn:ss"))
    ws.Range("A4").Value2 = "항목 수"
    ws.Range("B4:J4").Merge
    ws.Range("B4").Value2 = "첫 번째 목록: " & a.Total & "개 항목 / 두 번째 목록: " & b.Total & _
        "개 항목 / 일치 " & matched & "개 / 첫 번째 목록 잔여 " & excessA & "개 / 두 번째 목록 잔여 " & excessB & "개"
    ws.Range("A5").Value2 = "중복 / 제외"
    ws.Range("B5:J5").Merge
    ws.Range("B5").Value2 = "첫 번째 목록: 중복 초과 " & a.DuplicateExcess & "개 / 빈칸 " & a.BlankCount & _
        "개 / 오류 " & a.ErrorCount & "개 / 표 제목·합계 " & a.MetadataCount & "개" & vbLf & _
        "두 번째 목록: 중복 초과 " & b.DuplicateExcess & "개 / 빈칸 " & b.BlankCount & _
        "개 / 오류 " & b.ErrorCount & "개 / 표 제목·합계 " & b.MetadataCount & "개"
    ws.Range("A6").Value2 = "비교 규칙"
    ws.Range("B6:J6").Merge
    ws.Range("B6").Value2 = "이메일 @ 앞부분 / 숫자-문자숫자 통일 / 앞자리 0 보존 / 공백·대소문자 정리 / 값별 개수 비교"
    ws.Range("A7:J7").Merge
    If a.ErrorCount + b.ErrorCount > 0 Then
        ws.Range("A7").Value2 = "주의: 오류 셀을 제외한 결과입니다. 두 원본 전체가 동일하다는 의미가 아닙니다."
    Else
        ws.Range("A7").Value2 = "표에는 차이·중복만 표시합니다. 주소와 원본 예는 해당 키의 첫 번째 셀입니다."
    End If
    labels = Array("상태", "비교키", "첫 번째 목록 원본 예", "첫 번째 목록 개수", _
        "두 번째 목록 원본 예", "두 번째 목록 개수", "첫 번째 목록 잔여", "두 번째 목록 잔여", _
        "첫 번째 목록 주소", "두 번째 목록 주소")
    For i = 0 To 9
        headers(1, i + 1) = labels(i)
    Next i
    ws.Range("A8:J8").Value2 = headers
    outRow = 9
    For Each k In keys.Keys
        ca = CountOf(a, CStr(k))
        cb = CountOf(b, CStr(k))
        If ca <> cb Or ca > 1 Or cb > 1 Then
            If ca = 0 Then
                status = "두 번째 목록에만 있음"
            ElseIf cb = 0 Then
                status = "첫 번째 목록에만 있음"
            ElseIf ca <> cb Then
                status = "개수 차이"
            Else
                status = "중복"
            End If
            fill = fill + 1
            buffer(fill, 1) = status
            buffer(fill, 2) = OutputText(Mid$(CStr(k), 4))
            buffer(fill, 3) = OutputText(DictText(a.Examples, CStr(k)))
            buffer(fill, 4) = ca
            buffer(fill, 5) = OutputText(DictText(b.Examples, CStr(k)))
            buffer(fill, 6) = cb
            If ca > cb Then buffer(fill, 7) = ca - cb Else buffer(fill, 7) = 0
            If cb > ca Then buffer(fill, 8) = cb - ca Else buffer(fill, 8) = 0
            buffer(fill, 9) = DictText(a.Addresses, CStr(k))
            buffer(fill, 10) = DictText(b.Addresses, CStr(k))
            If fill = 4096 Then FlushOutput ws, buffer, fill, outRow
        End If
        tick = tick + 1
        If tick Mod 1024 = 0 Then Checkpoint
    Next k
    If fill > 0 Then FlushOutput ws, buffer, fill, outRow
    If outRow = 9 Then
        ws.Range("A9").Value2 = "비교 가능한 값의 차이는 없습니다. 제외된 오류 셀을 확인해 주세요."
        outRow = 10
    End If
    With ws
        .Columns("A").ColumnWidth = 26
        .Columns("B").ColumnWidth = 25
        .Columns("C").ColumnWidth = 32
        .Columns("D").ColumnWidth = 16
        .Columns("E").ColumnWidth = 32
        .Columns("F:H").ColumnWidth = 16
        .Columns("I:J").ColumnWidth = 16
        .Range("A1:J1").Font.Size = 17
        .Range("A1:J1").Font.Bold = True
        .Range("A1:J1").RowHeight = 32
        .Range("A1:J1").Interior.Color = RGB(30, 65, 92)
        .Range("A1:J1").Font.Color = RGB(255, 255, 255)
        .Range("A2:A6").Font.Bold = True
        .Range("A8:J8").Font.Bold = True
        .Range("A8:J8").Interior.Color = RGB(225, 234, 242)
        .Range("A2:J8").WrapText = True
        .Range("A2:J7").RowHeight = 36
        .Range("A5:J5").RowHeight = 48
        .Range("A8:J8").RowHeight = 48
        .Range("A8:J" & CStr(outRow - 1)).AutoFilter
    End With
    wb.Activate
    ws.Range("A9").Select
    wb.Windows(1).FreezePanes = True
    ws.Range("A1").Select
    ' Deliberately leave Saved=False: never discard the user's result edits.
    Application.ScreenUpdating = oldScreen
    Application.EnableEvents = oldEvents
    Exit Sub
Failed:
    errNo = Err.Number
    errText = Err.Description
    On Error Resume Next
    If Not wb Is Nothing Then wb.Close SaveChanges:=False
    If Not oldBook Is Nothing Then oldBook.Activate
    If setState Then
        Application.ScreenUpdating = oldScreen
        Application.EnableEvents = oldEvents
    End If
    On Error GoTo 0
    Err.Raise errNo, "WriteResults", errText
End Sub

Private Sub FlushOutput(ByVal ws As Worksheet, ByRef buffer() As Variant, ByRef fill As Long, ByRef outRow As Long)
    Dim target As Range, small() As Variant, r As Long, c As Long
    Set target = ws.Cells(outRow, 1).Resize(fill, 10)
    target.NumberFormat = "@"
    If fill = 4096 Then
        target.Value2 = buffer
    Else
        ReDim small(1 To fill, 1 To 10)
        For r = 1 To fill
            For c = 1 To 10
                small(r, c) = buffer(r, c)
            Next c
        Next r
        target.Value2 = small
    End If
    target.Columns(4).NumberFormat = "0"
    target.Columns(6).Resize(fill, 3).NumberFormat = "0"
    outRow = outRow + fill
    fill = 0
    Checkpoint
End Sub

Public Sub SLC_About()
    MsgBox "Excel Smart List Compare " & VERSION_TEXT & vbCrLf & vbCrLf & _
        "첫 번째 목록을 선택하고 [첫 번째 목록 담기]를 누르세요." & vbCrLf & _
        "이어서 두 번째 목록을 선택하고 [두 번째 목록과 비교]를 누르세요." & vbCrLf & vbCrLf & _
        "목록은 선택한 셀 전체, 항목은 그 안의 값 하나입니다." & vbCrLf & _
        "가로·세로·사각 범위·다중 선택은 모두 하나의 목록입니다." & vbCrLf & _
        "다른 파일도 같은 Excel 실행 세션이면 가능합니다." & vbCrLf & _
        "필터/숨김 셀은 제외합니다. 값별 개수까지 비교합니다." & vbCrLf & _
        "100,000셀/목록 상한. 20,000셀부터 지연 경고." & vbCrLf & _
        "전역 단축키·클립보드·원본 값·계산 모드를 변경하지 않습니다." & vbCrLf & _
        "수동 계산 상태의 오래된 수식 결과나 Excel이 이미 잃은 숫자 정밀도는 복구하지 않습니다.", _
        vbInformation, "명단 비교 - 사용 안내"
End Sub

' Integration tests must be executed in Windows desktop Excel, not a VBA emulator.
Public Function SLC_TestAll() As String
    Dim wb As Workbook, other As Workbook, ws As Worksheet, lo As ListObject
    Dim a As CSLCList, b As CSLCList, parts As Collection, rects As Collection
    Dim arr(1 To 2, 1 To 2) As Variant, i As Long, n As Long
    Dim oldEvents As Boolean, oldCancel As XlEnableCancelKey, oldBook As Workbook
    Dim errNo As Long, errText As String
    On Error GoTo Failed
    oldEvents = Application.EnableEvents
    oldCancel = Application.EnableCancelKey
    Set oldBook = Application.ActiveWorkbook
    Application.EnableEvents = False
    Application.EnableCancelKey = xlErrorHandler
    mStarted = Timer
    mCancelled = False
    SLC_NormalizeTests
    Set wb = Application.Workbooks.Add(xlWBATWorksheet)
    Set ws = wb.Worksheets(1)
    ws.Range("B2:E2").NumberFormat = "@"
    ws.Range("B2").Value2 = "USER@A.COM"
    ws.Range("C2").Value2 = "123.0"
    ws.Range("D2").Value2 = " 홍길동 "
    ws.Range("E2").Value2 = "00123"
    ws.Range("H3:H6").NumberFormat = "@"
    ws.Range("H3").Value2 = "00123"
    ws.Range("H4").Value2 = "홍길동"
    ws.Range("H5").Value2 = "user@b.com"
    ws.Range("H6").Value2 = "123"
    Set a = TestSnapshot(ws.Range("B2:E2"))
    Set b = TestSnapshot(ws.Range("H3:H6"))
    AssertSame a, b, "horizontal -> vertical"
    AssertSame b, a, "vertical -> horizontal"
    n = n + 2
    arr(1, 1) = "00123": arr(1, 2) = "홍길동"
    arr(2, 1) = "123": arr(2, 2) = "user"
    ws.Range("J3:K4").NumberFormat = "@"
    ws.Range("J3:K4").Value2 = arr
    Set b = TestSnapshot(ws.Range("J3:K4"))
    AssertSame a, b, "rectangle flattens"
    n = n + 1
    ws.Range("M1").Value2 = "Outside"
    Set b = TestSnapshot(ws.Range("B2"))
    If b.Total <> 1 Then Err.Raise ERR_DATA, , "Single-cell selection broadened"
    n = n + 1
    ws.Columns("C").Hidden = True
    Set b = TestSnapshot(ws.Range("B2:E2"))
    If b.Total <> 3 Or b.Counts.Exists(SLC_Normalize("123")) Then Err.Raise ERR_DATA, , "Hidden column included"
    ws.Columns("C").Hidden = False
    n = n + 1
    ws.Rows(4).Hidden = True
    Set b = TestSnapshot(ws.Range("H3:H6"))
    If b.Total <> 3 Then Err.Raise ERR_DATA, , "Hidden row included"
    ws.Rows(4).Hidden = False
    n = n + 1
    ws.Range("A10").Value2 = "name"
    ws.Range("A11").Value2 = "keep"
    ws.Range("A12").Value2 = "drop"
    ws.Range("A13").Value2 = "keep"
    ws.Range("B10").Value2 = "not a header"
    ws.Range("A10:A13").AutoFilter Field:=1, Criteria1:="keep"
    Set b = TestSnapshot(ws.Range("A10:A13"))
    If b.Total <> 2 Or b.MetadataCount <> 1 Or b.Counts.Count <> 1 Then Err.Raise ERR_DATA, , "Filter/header failed"
    Set b = TestSnapshot(ws.Range("A10:B10"))
    If b.Total <> 1 Then Err.Raise ERR_DATA, , "Header exclusion escaped its columns"
    ws.AutoFilterMode = False
    n = n + 2
    Set b = TestSnapshot(Application.Union(ws.Range("B2:C2"), ws.Range("D2:E2")))
    AssertSame a, b, "multi-area"
    n = n + 1
    Set b = TestSnapshot(Application.Union(ws.Range("B2:D2"), ws.Range("C2:E2")))
    AssertSame a, b, "overlapping selection counted once"
    n = n + 1
    Set b = TestSnapshot(ws.Rows(2))
    AssertSame a, b, "whole row bounded by used range"
    n = n + 1
    ws.Range("P1").Value2 = "one"
    ws.Range("P2").Value2 = "one"
    ws.Range("P3").Value2 = CVErr(xlErrNA)
    ws.Range("P4").Formula = "=" & Chr$(34) & Chr$(34)
    ws.Range("P4").Calculate
    Set b = TestSnapshot(ws.Range("P1:P4"))
    If b.Total <> 2 Or b.DuplicateExcess <> 1 Or b.ErrorCount <> 1 Or b.BlankCount <> 1 Then
        Err.Raise ERR_DATA, , "duplicates / errors / formula empty"
    End If
    n = n + 1
    Set b = TestSnapshot(ws.Columns("H"))
    AssertSame a, b, "whole column bounded by used range"
    n = n + 1
    ws.Range("R10").Value2 = "heading"
    ws.Range("R11").Value2 = "one"
    Set lo = ws.ListObjects.Add(xlSrcRange, ws.Range("R10:R11"), , xlYes)
    lo.ShowTotals = True
    Set b = TestSnapshot(lo.Range)
    If b.Total <> 1 Or b.MetadataCount <> 2 Then Err.Raise ERR_DATA, , "Table totals/header"
    n = n + 1
    ws.Columns("T").Hidden = True
    ws.Range("T1").Value2 = "hidden"
    Set b = TestSnapshot(ws.Range("T1"))
    If b.Total <> 0 Then Err.Raise ERR_DATA, , "Hidden single cell"
    ws.Columns("T").Hidden = False
    n = n + 1
    ws.Range("V1:W1").Merge
    If Not TestRejects(ws.Range("V1:W1"), ERR_DATA) Then Err.Raise ERR_DATA, , "Merged cells not rejected"
    ws.Range("V1:W1").UnMerge
    n = n + 1
    ws.Range("A100002").Value2 = "sentinel"
    If Not TestRejects(ws.Range("A1:A100001"), ERR_LIMIT) Then Err.Raise ERR_DATA, , "Visible cap failed"
    If Not TestRejects(ws.Cells, ERR_LIMIT) Then Err.Raise ERR_DATA, , "Scan cap failed"
    n = n + 2
    Set other = Application.Workbooks.Add(xlWBATWorksheet)
    other.Worksheets(1).Range("A1:B2").NumberFormat = "@"
    other.Worksheets(1).Range("A1:B2").Value2 = arr
    Set b = TestSnapshot(other.Worksheets(1).Range("A1:B2"))
    wb.Close SaveChanges:=False
    Set wb = Nothing
    AssertSame a, b, "closed first workbook snapshot"
    n = n + 1
    other.Close SaveChanges:=False
    Set other = Nothing
    ReleaseStatus
    Application.EnableEvents = oldEvents
    Application.EnableCancelKey = oldCancel
    If Not oldBook Is Nothing Then oldBook.Activate
    SLC_TestAll = "PASS: normalization + " & CStr(n) & " Excel integration checks"
    Exit Function
Failed:
    errNo = Err.Number: errText = Err.Description
    On Error Resume Next
    If Not wb Is Nothing Then wb.Close SaveChanges:=False
    If Not other Is Nothing Then other.Close SaveChanges:=False
    Application.EnableEvents = oldEvents
    Application.EnableCancelKey = oldCancel
    ReleaseStatus
    If Not oldBook Is Nothing Then oldBook.Activate
    On Error GoTo 0
    Err.Raise errNo, "SLC_TestAll", errText
End Function

Private Function TestSnapshot(ByVal rng As Range) As CSLCList
    Dim parts As Collection, rects As Collection
    mStarted = Timer
    Set parts = PrepareParts(rng, False, False)
    Set rects = MetadataRects(rng.Worksheet)
    Set TestSnapshot = ReadParts(rng, parts, rects)
End Function

Private Function TestRejects(ByVal rng As Range, ByVal expectedError As Long) As Boolean
    Dim parts As Collection, actualError As Long
    On Error GoTo Expected
    mStarted = Timer
    Set parts = PrepareParts(rng, False, False)
    Exit Function
Expected:
    actualError = Err.Number
    TestRejects = (actualError = expectedError)
End Function

Private Sub AssertSame(ByVal a As CSLCList, ByVal b As CSLCList, ByVal label As String)
    Dim k As Variant
    If a.Total <> b.Total Or a.Counts.Count <> b.Counts.Count Then Err.Raise ERR_DATA, , label
    For Each k In a.Counts.Keys
        If CountOf(a, CStr(k)) <> CountOf(b, CStr(k)) Then Err.Raise ERR_DATA, , label
    Next k
End Sub
