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
    AddButton bar.Controls, SLC_U("BA85 B2E8 0020 BE44 AD50"), "SLC_Run", "run"
    AddButton bar.Controls, SLC_U("AE30 C900 0020 BE44 C6B0 AE30"), "SLC_Clear", "clear"
    AddButton bar.Controls, SLC_U("C120 D0DD 0020 BC94 C704 B85C 0020 AE30 C900 0020 AD50 CCB4"), "SLC_Replace", "replace"
    AddButton bar.Controls, SLC_U("C0AC C6A9 0020 C548 B0B4"), "SLC_About", "about"
    bar.Visible = True
    For Each menuName In Array("Cell", "Row", "Column")
        Set bar = Nothing
        On Error Resume Next
        Set bar = Application.CommandBars(CStr(menuName))
        On Error GoTo Failed
        If Not bar Is Nothing Then
            Set pop = bar.Controls.Add(Type:=msoControlPopup, Temporary:=True)
            pop.Tag = UI_TAG
            pop.Caption = SLC_U("BA85 B2E8 0020 BE44 AD50")
            AddButton pop.Controls, SLC_U("BA85 B2E8 0020 BE44 AD50"), "SLC_Run", "run"
            AddButton pop.Controls, SLC_U("AE30 C900 0020 BE44 C6B0 AE30"), "SLC_Clear", "clear"
            AddButton pop.Controls, SLC_U("C120 D0DD 0020 BC94 C704 B85C 0020 AE30 C900 0020 AD50 CCB4"), "SLC_Replace", "replace"
            AddButton pop.Controls, SLC_U("C0AC C6A9 0020 C548 B0B4"), "SLC_About", "about"
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
    button.OnAction = "'" & Replace(ThisWorkbook.Name, "'", "''") & "'!" & procedureName
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
    Dim title As String
    If mPending Is Nothing Then
        title = SLC_U("BA85 B2E8 0020 BE44 AD50 003A 0020 AE30 C900 0020 B2F4 AE30")
    Else
        title = SLC_U("BA85 B2E8 0020 BE44 AD50 003A 0020 AE30 C900 0020") & Format$(mPending.Total, "#,##0") & SLC_U("AC74 ACFC 0020 BE44 AD50")
    End If
    On Error Resume Next
    For Each n In Array(BAR_NAME, "Cell", "Row", "Column")
        Set bar = Nothing
        Set bar = Application.CommandBars(CStr(n))
        If Not bar Is Nothing Then
            For Each ctl In bar.Controls
                If ctl.Tag = UI_TAG & ".run" Then ctl.Caption = title
                If ctl.Tag = UI_TAG Then
                    Set popup = ctl
                    For Each child In popup.Controls
                        If child.Tag = UI_TAG & ".run" Then child.Caption = title
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
        MsgBox SLC_U("BE44 AD50 D560 0020 C140 0020 BC94 C704 B97C 0020 C120 D0DD D574 0020 C8FC C138 C694 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        Exit Sub
    End If
    Set selected = Application.Selection
    If Application.ActiveWindow.SelectedSheets.Count > 1 Then
        MsgBox SLC_U("ADF8 B8F9 0020 C120 D0DD B41C 0020 C2DC D2B8 B97C 0020 D574 C81C D558 ACE0 0020 D55C 0020 C2DC D2B8 C758 0020 BC94 C704 B97C 0020 C120 D0DD D574 0020 C8FC C138 C694 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        Exit Sub
    End If
    If Application.CalculationState <> xlDone Then
        MsgBox SLC_U("0045 0078 0063 0065 006C C774 0020 ACC4 C0B0 0020 C911 C785 B2C8 B2E4 002E 0020 ACC4 C0B0 C774 0020 B05D B09C 0020 B4A4 0020 B2E4 C2DC 0020 C2E4 D589 D574 0020 C8FC C138 C694 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
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
    Application.Interactive = False
    Set exclusions = MetadataRects(selected.Worksheet)
    Set current = ReadParts(selected, parts, exclusions)
    If current.Total = 0 Then
        ReleaseStatus
        MsgBox SLC_U("D654 BA74 C5D0 0020 B0A8 C740 0020 C120 D0DD 0020 C140 C5D0 C11C 0020 BE44 AD50 D560 0020 AC12 C744 0020 CC3E C9C0 0020 BABB D588 C2B5 B2C8 B2E4 002E") & vbCrLf & _
               SLC_U("BE48 CE78 00B7 C624 B958 AC12 00B7 D45C 0020 C81C BAA9 002F D569 ACC4 0020 C140 C740 0020 C81C C678 B429 B2C8 B2E4 002E 0020 AE30 C874 0020 AE30 C900 C740 0020 C720 C9C0 B429 B2C8 B2E4 002E"), _
               vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        GoTo Finished
    End If
    If Not combining Then
        Set mPending = current
        SetStatus SLC_U("BA85 B2E8 0020 BE44 AD50 003A 0020 AE30 C900 0020") & Format$(current.Total, "#,##0") & _
                  SLC_U("AC74 0020 C800 C7A5 B428 002E 0020 B2E4 B978 0020 BC94 C704 B97C 0020 C120 D0DD D55C 0020 B4A4 0020 B2E4 C2DC 0020 C2E4 D589 D558 C138 C694 002E")
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
        MsgBox SLC_U("C791 C5C5 C744 0020 CDE8 C18C D588 C2B5 B2C8 B2E4 002E 0020 AE30 C874 0020 AE30 C900 C740 0020 C720 C9C0 B429 B2C8 B2E4 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
    Else
        MsgBox errText & vbCrLf & vbCrLf & SLC_U("AE30 C874 0020 AE30 C900 ACFC 0020 C6D0 BCF8 0020 B370 C774 D130 B294 0020 BCC0 ACBD D558 C9C0 0020 C54A C558 C2B5 B2C8 B2E4 002E") & _
               vbCrLf & SLC_U("C624 B958 0020 CF54 B4DC 003A 0020") & CStr(errNo), vbExclamation, SLC_U("BA85 B2E8 0020 BE44 AD50")
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
        Err.Raise ERR_LIMIT, , SLC_U("C120 D0DD 0020 C601 C5ED 0020 C870 AC01 C774 0020 0035 002C 0030 0030 0030 AC1C B97C 0020 CD08 ACFC D569 B2C8 B2E4 002E 0020 BC94 C704 B97C 0020 C904 C5EC 0020 C8FC C138 C694 002E")
    End If
    ' Intersect, not Find: never changes the user's Find/Replace settings.
    Set bounded = Application.Intersect(sel, sel.Worksheet.UsedRange)
    If bounded Is Nothing Then
        Set PrepareParts = parts
        Exit Function
    End If
    scanCount = CDbl(bounded.CountLarge)
    If scanCount > MAX_SCAN Then
        Err.Raise ERR_LIMIT, , SLC_U("AC00 C2DC C131 0020 D655 C778 0020 B300 C0C1 C774 0020 0032 002C 0030 0030 0030 002C 0030 0030 0030 C140 C744 0020 CD08 ACFC D569 B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("C804 CCB4 0020 D589 002F C5F4 0020 B300 C2E0 0020 C2E4 C81C 0020 AC12 C774 0020 C788 B294 0020 C791 C740 0020 BC94 C704 B97C 0020 C120 D0DD D574 0020 C8FC C138 C694 002E")
    End If
    If bounded.Areas.Count > MAX_AREAS Then
        Err.Raise ERR_LIMIT, , SLC_U("C120 D0DD 0020 C601 C5ED 0020 C870 AC01 C774 0020 0035 002C 0030 0030 0030 AC1C B97C 0020 CD08 ACFC D569 B2C8 B2E4 002E")
    End If
    If scanCount >= WARN_SCAN Or bounded.Areas.Count >= WARN_AREAS Then
        text = SLC_U("C120 D0DD 0020 BC94 C704 C758 0020 AC00 C2DC C131 C744 0020 D655 C778 D558 B294 0020 B370 0020 C2DC AC04 C774 0020 AC78 B9B4 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("D655 C778 0020 B300 C0C1 003A 0020") & Format$(scanCount, "#,##0") & SLC_U("C140") & vbCrLf & _
            SLC_U("D544 D130 002F C228 AE40 0020 D655 C778 0020 D6C4 0020 BCF4 C774 B294 0020 C140 B9CC 0020 C77D C2B5 B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("AC12 0020 C77D AE30 00B7 BE44 AD50 B97C 0020 ACC4 C18D D560 AE4C C694 003F 0020 005B C544 B2C8 C694 005D AC00 0020 AE30 BCF8 C785 B2C8 B2E4 002E")
        If ask Then
            If MsgBox(text, vbYesNo + vbExclamation + vbDefaultButton2, SLC_U("BA85 B2E8 0020 BE44 AD50 0020 002D 0020 B300 B7C9 0020 C791 C5C5")) <> vbYes Then Exit Function
        End If
        warned = True
        mStarted = Timer
    End If
    For Each ar In bounded.Areas
        Checkpoint
        mergeState = ar.MergeCells
        If IsNull(mergeState) Then
            Err.Raise ERR_DATA, , SLC_U("BCD1 D569 0020 C140 C774 0020 C11E C5EC 0020 C788 C2B5 B2C8 B2E4 002E 0020 BCD1 D569 0020 C140 C744 0020 C81C C678 D55C 0020 AC12 0020 BC94 C704 B97C 0020 C120 D0DD D574 0020 C8FC C138 C694 002E")
        ElseIf CBool(mergeState) Then
            Err.Raise ERR_DATA, , SLC_U("BCD1 D569 0020 C140 C740 0020 BE44 AD50 D558 C9C0 0020 C54A C2B5 B2C8 B2E4 002E 0020 BCD1 D569 B418 C9C0 0020 C54A C740 0020 AC12 0020 BC94 C704 B97C 0020 C120 D0DD D574 0020 C8FC C138 C694 002E")
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
                    Err.Raise specialErr, , SLC_U("BCF4 C774 B294 0020 C140 C744 0020 D655 C778 D558 C9C0 0020 BABB D588 C2B5 B2C8 B2E4 002E")
                ElseIf Not EntirelyHidden(ar) Then
                    ' 1004 is ambiguous: do not silently turn a visibility failure into an empty list.
                    Err.Raise ERR_DATA, , SLC_U("BCF4 C774 B294 0020 C140 C744 0020 C548 C804 D558 AC8C 0020 D655 C778 D558 C9C0 0020 BABB D588 C2B5 B2C8 B2E4 002E 0020 C120 D0DD 0020 BC94 C704 B97C 0020 C904 C5EC 0020 C8FC C138 C694 002E")
                End If
            End If
            If Not vis Is Nothing Then Set vis = Application.Intersect(ar, vis)
        End If
        If Not vis Is Nothing Then
            If parts.Count + vis.Areas.Count > MAX_AREAS Then
                Err.Raise ERR_LIMIT, , SLC_U("D544 D130 B85C 0020 B098 B25C 0020 AC00 C2DC 0020 C601 C5ED C774 0020 0035 002C 0030 0030 0030 AC1C B97C 0020 CD08 ACFC D569 B2C8 B2E4 002E 0020 C120 D0DD 0020 BC94 C704 B97C 0020 C904 C5EC 0020 C8FC C138 C694 002E")
            End If
            visibleCount = visibleCount + CDbl(vis.CountLarge)
            If visibleCount > MAX_VISIBLE Then
                Err.Raise ERR_LIMIT, , SLC_U("D55C 0020 BA85 B2E8 C740 0020 BCF4 C774 B294 0020 C120 D0DD 0020 C140 0020 0031 0030 0030 002C 0030 0030 0030 AC1C AE4C C9C0 0020 CC98 B9AC D569 B2C8 B2E4 002E") & vbCrLf & _
                    SLC_U("BE48 CE78 C744 0020 D3EC D568 D55C 0020 C548 C804 0020 C0C1 D55C C785 B2C8 B2E4 002E 0020 C228 ACA8 C9C4 0020 C140 C740 0020 C774 0020 C218 C5D0 0020 B123 C9C0 0020 C54A C2B5 B2C8 B2E4 002E")
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
            text = SLC_U("C77D AE30 00B7 BE44 AD50 00B7 ACB0 ACFC 0020 CD9C B825 C5D0 0020 C2DC AC04 C774 0020 AC78 B9B4 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E") & vbCrLf & _
                   SLC_U("C774 BC88 0020 C120 D0DD 003A 0020 BCF4 C774 B294 0020") & Format$(visibleCount, "#,##0") & SLC_U("C140 0020 002F 0020") & _
                   Format$(parts.Count, "#,##0") & SLC_U("AC1C 0020 C601 C5ED") & vbCrLf & _
                   SLC_U("AE30 C900 0020 D3EC D568 0020 CC98 B9AC 0020 ADDC BAA8 003A 0020") & Format$(combinedCount, "#,##0") & SLC_U("C140") & vbCrLf & _
                   SLC_U("ACC4 C18D D560 AE4C C694 003F 0020 C2E4 D589 0020 C911 0020 0045 0073 0063 B85C 0020 CDE8 C18C D560 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E")
            If ask Then
                If MsgBox(text, vbYesNo + vbExclamation + vbDefaultButton2, SLC_U("BA85 B2E8 0020 BE44 AD50 0020 002D 0020 B300 B7C9 0020 C791 C5C5")) <> vbYes Then Exit Function
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
                        SetStatus SLC_U("BA85 B2E8 0020 BE44 AD50 003A 0020") & Format$(result.VisibleCellCount, "#,##0") & SLC_U("C140 0020 CC98 B9AC 0020 C911 0020 002F 0020 0045 0073 0063 0020 CDE8 C18C")
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
        Err.Raise ERR_LIMIT, , address & SLC_U("003A 0020 C140 0020 D558 B098 C758 0020 AC12 C774 0020 0034 002C 0030 0039 0036 C790 B97C 0020 CD08 ACFC D569 B2C8 B2E4 002E 0020 BA85 B2E8 0020 BC94 C704 B97C 0020 B2E4 C2DC 0020 D655 C778 D574 0020 C8FC C138 C694 002E")
    End If
    list.RawCharCount = list.RawCharCount + Len(raw)
    If list.RawCharCount > MAX_RAW_CHARS Then
        Err.Raise ERR_LIMIT, , SLC_U("D55C 0020 BA85 B2E8 C758 0020 C804 CCB4 0020 D14D C2A4 D2B8 AC00 0020 0035 002C 0030 0030 0030 002C 0030 0030 0030 C790 B97C 0020 CD08 ACFC D569 B2C8 B2E4 002E 0020 BC94 C704 B97C 0020 C904 C5EC 0020 C8FC C138 C694 002E")
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
        Err.Raise ERR_TIME, , SLC_U("C9C0 C5F0 0020 BCF4 D638 0020 D55C B3C4 0028 D65C C131 0020 CC98 B9AC 0020 C57D 0020 0033 0030 CD08 0029 C5D0 0020 B3C4 B2EC D574 0020 C911 B2E8 D588 C2B5 B2C8 B2E4 002E 0020 BC94 C704 B97C 0020 C904 C5EC 0020 C8FC C138 C694 002E")
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
        MsgBox SLC_U("B450 0020 BA85 B2E8 C758 0020 AC12 ACFC 0020 AC1C C218 AC00 0020 AC19 C2B5 B2C8 B2E4 002E") & vbCrLf & _
            "A " & Format$(a.Total, "#,##0") & SLC_U("AC74 0020 002F 0020 0042 0020") & Format$(b.Total, "#,##0") & SLC_U("AC74") & vbCrLf & _
            SLC_U("BE44 AD50 0020 AE30 C900 003A 0020 C774 BA54 C77C 0020 0049 0044 00B7 C22B C790 0020 D45C AE30 00B7 B300 C18C BB38 C790 00B7 ACF5 BC31 0020 C790 B3D9 0020 C815 B9AC"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
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
    ws.Name = SLC_U("BA85 B2E8 BE44 AD50 005F ACB0 ACFC")
    ws.Range("A1:J8").NumberFormat = "@"
    ws.Range("A1:J1").Merge
    ws.Range("A1").Value2 = SLC_U("BA85 B2E8 0020 BE44 AD50 0020 ACB0 ACFC")
    ws.Range("A2").Value2 = SLC_U("0041 0020 CD9C CC98 0020 002F 0020 C2DC C810")
    ws.Range("B2:J2").Merge
    ws.Range("B2").Value2 = OutputText(a.Source & " / " & Format$(a.CapturedAt, "yyyy-mm-dd hh:nn:ss"))
    ws.Range("A3").Value2 = SLC_U("0042 0020 CD9C CC98 0020 002F 0020 C2DC C810")
    ws.Range("B3:J3").Merge
    ws.Range("B3").Value2 = OutputText(b.Source & " / " & Format$(b.CapturedAt, "yyyy-mm-dd hh:nn:ss"))
    ws.Range("A4").Value2 = SLC_U("AC74 C218")
    ws.Range("B4:J4").Merge
    ws.Range("B4").Value2 = "A " & a.Total & " / B " & b.Total & SLC_U("0020 002F 0020 C77C CE58 0020") & matched & _
                            SLC_U("0020 002F 0020 0041 0020 C794 C5EC 0020") & excessA & SLC_U("0020 002F 0020 0042 0020 C794 C5EC 0020") & excessB
    ws.Range("A5").Value2 = SLC_U("C911 BCF5 0020 002F 0020 C81C C678")
    ws.Range("B5:J5").Merge
    ws.Range("B5").Value2 = SLC_U("C911 BCF5 CD08 ACFC 0020 0041 0020") & a.DuplicateExcess & " / B " & b.DuplicateExcess & _
        SLC_U("0020 007C 0020 BE48 CE78 0020 0041 0020") & a.BlankCount & " / B " & b.BlankCount & _
        SLC_U("0020 007C 0020 C624 B958 0020 0041 0020") & a.ErrorCount & " / B " & b.ErrorCount & _
        SLC_U("0020 007C 0020 D45C 0020 C81C BAA9 00B7 D569 ACC4 0020 0041 0020") & a.MetadataCount & " / B " & b.MetadataCount
    ws.Range("A6").Value2 = SLC_U("BE44 AD50 0020 ADDC CE59")
    ws.Range("B6:J6").Merge
    ws.Range("B6").Value2 = SLC_U("C774 BA54 C77C 0020 0040 0020 C55E BD80 BD84 0020 002F 0020 C22B C790 002D BB38 C790 C22B C790 0020 D1B5 C77C 0020 002F 0020 C55E C790 B9AC 0020 0030 0020 BCF4 C874 0020 002F 0020 ACF5 BC31 00B7 B300 C18C BB38 C790 0020 C815 B9AC 0020 002F 0020 AC12 BCC4 0020 AC1C C218 0020 BE44 AD50")
    ws.Range("A7:J7").Merge
    If a.ErrorCount + b.ErrorCount > 0 Then
        ws.Range("A7").Value2 = SLC_U("C8FC C758 003A 0020 C624 B958 0020 C140 C744 0020 C81C C678 D55C 0020 ACB0 ACFC C785 B2C8 B2E4 002E 0020 B450 0020 C6D0 BCF8 0020 C804 CCB4 AC00 0020 B3D9 C77C D558 B2E4 B294 0020 C758 BBF8 AC00 0020 C544 B2D9 B2C8 B2E4 002E")
    Else
        ws.Range("A7").Value2 = SLC_U("D45C C5D0 B294 0020 CC28 C774 00B7 C911 BCF5 B9CC 0020 D45C C2DC D569 B2C8 B2E4 002E 0020 C8FC C18C C640 0020 C6D0 BCF8 0020 C608 B294 0020 D574 B2F9 0020 D0A4 C758 0020 CCAB 0020 BC88 C9F8 0020 C140 C785 B2C8 B2E4 002E")
    End If
    labels = Array(SLC_U("C0C1 D0DC"), SLC_U("BE44 AD50 D0A4"), SLC_U("0041 0020 C6D0 BCF8 0020 C608"), SLC_U("0041 0020 AC1C C218"), SLC_U("0042 0020 C6D0 BCF8 0020 C608"), SLC_U("0042 0020 AC1C C218"), SLC_U("0041 0020 C794 C5EC"), SLC_U("0042 0020 C794 C5EC"), SLC_U("0041 0020 C8FC C18C"), SLC_U("0042 0020 C8FC C18C"))
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
                status = SLC_U("0042 C5D0 B9CC 0020 C788 C74C")
            ElseIf cb = 0 Then
                status = SLC_U("0041 C5D0 B9CC 0020 C788 C74C")
            ElseIf ca <> cb Then
                status = SLC_U("AC1C C218 0020 CC28 C774")
            Else
                status = SLC_U("C911 BCF5")
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
        ws.Range("A9").Value2 = SLC_U("BE44 AD50 0020 AC00 B2A5 D55C 0020 AC12 C758 0020 CC28 C774 B294 0020 C5C6 C2B5 B2C8 B2E4 002E 0020 C81C C678 B41C 0020 C624 B958 0020 C140 C744 0020 D655 C778 D574 0020 C8FC C138 C694 002E")
        outRow = 10
    End If
    With ws
        .Columns("A").ColumnWidth = 18
        .Columns("B").ColumnWidth = 25
        .Columns("C").ColumnWidth = 32
        .Columns("D").ColumnWidth = 10
        .Columns("E").ColumnWidth = 32
        .Columns("F:H").ColumnWidth = 10
        .Columns("I:J").ColumnWidth = 13
        .Range("A1:J1").Font.Size = 17
        .Range("A1:J1").Font.Bold = True
        .Range("A1:J1").RowHeight = 32
        .Range("A1:J1").Interior.Color = RGB(30, 65, 92)
        .Range("A1:J1").Font.Color = RGB(255, 255, 255)
        .Range("A2:A6").Font.Bold = True
        .Range("A8:J8").Font.Bold = True
        .Range("A8:J8").Interior.Color = RGB(225, 234, 242)
        .Range("A2:J7").WrapText = True
        .Range("A2:J3").RowHeight = 32
        .Range("A5:J7").RowHeight = 32
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
        SLC_U("0031 002E 0020 CCAB 0020 BC94 C704 0020 C120 D0DD 0020 2192 0020 BA85 B2E8 0020 BE44 AD50 003A 0020 AE30 C900 0020 B2F4 AE30") & vbCrLf & _
        SLC_U("0032 002E 0020 B2E4 B978 0020 BC94 C704 0020 C120 D0DD 0020 2192 0020 BA85 B2E8 0020 BE44 AD50 003A 0020 AE30 C900 ACFC 0020 BE44 AD50") & vbCrLf & vbCrLf & _
        SLC_U("AC00 B85C 00B7 C138 B85C 00B7 C0AC AC01 0020 BC94 C704 00B7 B2E4 C911 0020 C120 D0DD C740 0020 BAA8 B450 0020 D558 B098 C758 0020 BA85 B2E8 C785 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("B2E4 B978 0020 D30C C77C B3C4 0020 AC19 C740 0020 0045 0078 0063 0065 006C 0020 C2E4 D589 0020 C138 C158 C774 BA74 0020 AC00 B2A5 D569 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("D544 D130 002F C228 AE40 0020 C140 C740 0020 C81C C678 D569 B2C8 B2E4 002E 0020 AC12 BCC4 0020 AC1C C218 AE4C C9C0 0020 BE44 AD50 D569 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("0031 0030 0030 002C 0030 0030 0030 C140 002F BA85 B2E8 0020 C0C1 D55C 002E 0020 0032 0030 002C 0030 0030 0030 C140 BD80 D130 0020 C9C0 C5F0 0020 ACBD ACE0 002E") & vbCrLf & _
        SLC_U("C804 C5ED 0020 B2E8 CD95 D0A4 00B7 D074 B9BD BCF4 B4DC 00B7 C6D0 BCF8 0020 AC12 00B7 ACC4 C0B0 0020 BAA8 B4DC B97C 0020 BCC0 ACBD D558 C9C0 0020 C54A C2B5 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("C218 B3D9 0020 ACC4 C0B0 0020 C0C1 D0DC C758 0020 C624 B798 B41C 0020 C218 C2DD 0020 ACB0 ACFC B098 0020 0045 0078 0063 0065 006C C774 0020 C774 BBF8 0020 C783 C740 0020 C22B C790 0020 C815 BC00 B3C4 B294 0020 BCF5 AD6C D558 C9C0 0020 C54A C2B5 B2C8 B2E4 002E"), _
        vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50 0020 002D 0020 C0AC C6A9 0020 C548 B0B4")
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
    ws.Range("D2").Value2 = SLC_U("0020 D64D AE38 B3D9 0020")
    ws.Range("E2").Value2 = "00123"
    ws.Range("H3:H6").NumberFormat = "@"
    ws.Range("H3").Value2 = "00123"
    ws.Range("H4").Value2 = SLC_U("D64D AE38 B3D9")
    ws.Range("H5").Value2 = "user@b.com"
    ws.Range("H6").Value2 = "123"
    Set a = TestSnapshot(ws.Range("B2:E2"))
    Set b = TestSnapshot(ws.Range("H3:H6"))
    AssertSame a, b, "horizontal -> vertical"
    AssertSame b, a, "vertical -> horizontal"
    n = n + 2
    arr(1, 1) = "00123": arr(1, 2) = SLC_U("D64D AE38 B3D9")
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
