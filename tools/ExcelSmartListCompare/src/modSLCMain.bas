Attribute VB_Name = "modSLCMain"
Option Explicit

#If VBA7 Then
Private Declare PtrSafe Function SLC_GetAsyncKeyState Lib "user32" Alias "GetAsyncKeyState" (ByVal virtualKey As Long) As Integer
Private Declare PtrSafe Function SLC_GetForegroundWindow Lib "user32" Alias "GetForegroundWindow" () As LongPtr
Private Declare PtrSafe Function SLC_GetWindowThreadProcessId Lib "user32" Alias "GetWindowThreadProcessId" (ByVal hwnd As LongPtr, ByRef processId As Long) As Long
Private Declare PtrSafe Function SLC_GetCurrentProcessId Lib "kernel32" Alias "GetCurrentProcessId" () As Long
#Else
Private Declare Function SLC_GetAsyncKeyState Lib "user32" Alias "GetAsyncKeyState" (ByVal virtualKey As Long) As Integer
Private Declare Function SLC_GetForegroundWindow Lib "user32" Alias "GetForegroundWindow" () As Long
Private Declare Function SLC_GetWindowThreadProcessId Lib "user32" Alias "GetWindowThreadProcessId" (ByVal hwnd As Long, ByRef processId As Long) As Long
Private Declare Function SLC_GetCurrentProcessId Lib "kernel32" Alias "GetCurrentProcessId" () As Long
#End If

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
Private Const CANCEL_POLL_ITEMS As Long = 64
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
Private mAppEvents As CSLCAppEvents
Private mRibbonLoaded As Boolean
Private mOwnStatus As Boolean
Private mPreviousStatus As Variant
Private mLastStatus As String

Public Function SLC_Version() As String
    SLC_Version = VERSION_TEXT
End Function

Public Function SLC_UiReady() As Boolean
    SLC_UiReady = mUiAttached
End Function

Public Sub SLC_RibbonLoad(ByVal ribbon As Office.IRibbonUI)
    mRibbonLoaded = True
End Sub

Public Function SLC_RibbonReady() As Boolean
    SLC_RibbonReady = mRibbonLoaded
End Function

Public Function SLC_ReleaseVersion() As String
    SLC_ReleaseVersion = "0.2.0-rc.9"
End Function

Public Sub SLC_GetContextMenu(ByVal control As Office.IRibbonControl, ByRef content)
    content = SLC_MenuXml(control.Tag)
End Sub

Public Function SLC_MenuXml(Optional ByVal menuKind As String = "Cell") As String
    Dim prefix As String, xml As String
    Select Case menuKind
        Case "Cell", "Row", "Column", "Table", "CellLayout", "RowLayout", "ColumnLayout", "TableLayout"
            prefix = "slc68" & menuKind
        Case Else
            Err.Raise 5, "SLC_MenuXml", "Unknown product menu."
    End Select
    ' Called on every drop, independent of workbook/window event delivery.
    ' Only read the process snapshot; never inspect or change a selection here.
    xml = "<menu xmlns=""http://schemas.microsoft.com/office/2009/07/customui"">"
    If mPending Is Nothing Then
        xml = xml & MenuButton(prefix & "Capture", SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 AE30"), "SLC_CaptureClick")
    Else
        xml = xml & MenuButton(prefix & "Compare", SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 C544 0020 BE44 AD50"), "SLC_CompareClick")
        xml = xml & "<button id=""" & prefix & "Count"" enabled=""false"" label=""" & _
              SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 003A 0020") & Format$(mPending.Total, "#,##0") & SLC_U("AC1C 0020 D56D BAA9") & """/>"
        xml = xml & MenuButton(prefix & "Clear", SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 BE44 C6B0 AE30"), "SLC_ClearClick")
        xml = xml & MenuButton(prefix & "Replace", SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 BC14 AFB8 AE30"), "SLC_ReplaceClick")
    End If
    xml = xml & MenuButton(prefix & "About", SLC_U("C0AC C6A9 0020 C548 B0B4"), "SLC_AboutClick")
    SLC_MenuXml = xml & "</menu>"
End Function

Private Function MenuButton(ByVal id As String, ByVal label As String, ByVal action As String) As String
    ' All attributes are product constants or the allow-listed menu prefix.
    MenuButton = "<button id=""" & id & """ label=""" & label & """ onAction=""" & action & """/>"
End Function

Public Sub SLC_CaptureClick(ByVal control As Office.IRibbonControl)
    SLC_Capture
End Sub
Public Sub SLC_CompareClick(ByVal control As Office.IRibbonControl)
    SLC_Compare
End Sub
Public Sub SLC_ClearClick(ByVal control As Office.IRibbonControl)
    SLC_Clear
End Sub
Public Sub SLC_ReplaceClick(ByVal control As Office.IRibbonControl)
    SLC_Replace
End Sub
Public Sub SLC_AboutClick(ByVal control As Office.IRibbonControl)
    SLC_About
End Sub

Public Sub SLC_Capture()
    RunSelection True
End Sub
Public Sub SLC_Compare()
    If mBusy Then Exit Sub
    If mPending Is Nothing Then
        MsgBox SLC_U("BA3C C800 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D C744 0020 C120 D0DD D558 ACE0 0020 005B CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 AE30 005D B97C 0020 B204 B974 C138 C694 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        Exit Sub
    End If
    RunSelection False
End Sub

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
    Dim bar As CommandBar
    On Error GoTo Failed
    If mUiAttached Then Exit Sub
    RemoveOwnUI
    Set bar = Application.CommandBars.Add(Name:=BAR_NAME, Position:=msoBarTop, Temporary:=True)
    AddButton bar.Controls, SLC_U("BA85 B2E8 0020 BE44 AD50"), "SLC_Run", "run"
    AddButton bar.Controls, "", "", "pending"
    AddButton bar.Controls, SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 BE44 C6B0 AE30"), "SLC_Clear", "clear"
    AddButton bar.Controls, SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 BC14 AFB8 AE30"), "SLC_Replace", "replace"
    AddButton bar.Controls, SLC_U("C0AC C6A9 0020 C548 B0B4"), "SLC_About", "about"
    bar.Visible = True
    ' Context menus are registered by customUI14.xml, never by legacy controls.
    Set mAppEvents = New CSLCAppEvents
    Set mAppEvents.ExcelApp = Application
    mUiAttached = True
    RefreshUI
    Exit Sub
Failed:
    Set mAppEvents = Nothing
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
    Set mAppEvents = Nothing
    If mBusy Then mCancelled = True
    Set mPending = Nothing
    ReleaseStatus
    RemoveOwnUI
    mUiAttached = False
End Sub

Public Sub SLC_RefreshActiveUI()
    ' Excel SDI windows keep their own copies of legacy menu controls.
    ' Refresh presentation only; never select a cell or replace the snapshot.
    If Not mUiAttached Or mBusy Then Exit Sub
    RefreshUI
End Sub

Private Sub RefreshUI()
    Dim bar As CommandBar, ctl As CommandBarControl, child As CommandBarControl
    Dim popup As CommandBarPopup
    Dim title As String, pendingTitle As String
    If mPending Is Nothing Then
        title = SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 AE30")
    Else
        title = SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 C544 0020 BE44 AD50")
        pendingTitle = SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 003A 0020") & Format$(mPending.Total, "#,##0") & SLC_U("AC1C 0020 D56D BAA9")
    End If
    On Error Resume Next
    ' Resolve controls afresh in the active window, not a cached first-window bar.
    For Each bar In Application.CommandBars
        If bar.Name = BAR_NAME Or bar.Name = "Cell" Or bar.Name = "Row" Or bar.Name = "Column" Then
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
    Next bar
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
    Dim current As CSLCList, previousPending As CSLCList
    Dim oldCancel As XlEnableCancelKey
    Dim errNo As Long, errText As String
    Dim setState As Boolean, combining As Boolean, oldInteractive As Boolean
    Dim operationCommitted As Boolean

    If mBusy Then Exit Sub
    On Error GoTo Failed
    If TypeName(Application.Selection) <> "Range" Then
        MsgBox SLC_U("BE44 AD50 D560 0020 C140 0020 BC94 C704 B97C 0020 C120 D0DD D574 0020 C8FC C138 C694 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        Exit Sub
    End If
    Set selected = Application.Selection
    If Application.ActiveWindow.SelectedSheets.Count > 1 Then
        MsgBox SLC_U("C5EC B7EC 0020 C2DC D2B8 AC00 0020 D568 AED8 0020 C120 D0DD B418 C5B4 0020 C788 C2B5 B2C8 B2E4 002E 0020 C2DC D2B8 0020 D558 B098 B9CC 0020 C120 D0DD D55C 0020 B4A4 0020 BE44 AD50 D560 0020 C140 C744 0020 C120 D0DD D574 0020 C8FC C138 C694 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        Exit Sub
    End If
    If Application.CalculationState <> xlDone Then
        MsgBox SLC_U("0045 0078 0063 0065 006C C774 0020 ACC4 C0B0 0020 C911 C785 B2C8 B2E4 002E 0020 ACC4 C0B0 C774 0020 B05D B09C 0020 B4A4 0020 B2E4 C2DC 0020 C2E4 D589 D574 0020 C8FC C138 C694 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        Exit Sub
    End If

    mBusy = True
    Set previousPending = mPending
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
    ' A cancellation queued during the last partial chunk must precede commit.
    Checkpoint
    If current.Total = 0 Then
        ReleaseStatus
        MsgBox SLC_U("C120 D0DD D55C 0020 C140 C5D0 0020 BE44 AD50 D560 0020 AC12 C774 0020 C5C6 C2B5 B2C8 B2E4 002E") & vbCrLf & _
               SLC_U("C228 AE34 0020 C140 002C 0020 D544 D130 B85C 0020 AC00 B824 C9C4 0020 C140 002C 0020 BE48 CE78 002C 0020 C624 B958 0020 C140 002C 0020 D45C C758 0020 C81C BAA9 00B7 D569 ACC4 0020 C140 C740 0020 BE44 AD50 C5D0 C11C 0020 BE8D B2C8 B2E4 002E") & vbCrLf & _
               SLC_U("B2F4 C544 0020 B454 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D C774 0020 C788 B2E4 BA74 0020 ADF8 B300 B85C 0020 B0A8 C544 0020 C788 C2B5 B2C8 B2E4 002E"), _
               vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        GoTo Finished
    End If
    If Not combining Then
        SetStatus SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 003A 0020") & Format$(current.Total, "#,##0") & SLC_U("AC1C 0020 D56D BAA9")
        Checkpoint
        ' No event dispatch or dialogs between the final check and commit.
        Application.EnableCancelKey = xlDisabled
        Set mPending = current
        operationCommitted = True
    Else
        ShowComparison mPending, current
        operationCommitted = True
        Application.EnableCancelKey = xlDisabled
        Set mPending = Nothing
        ReleaseStatus
    End If
Finished:
    If setState Then
        Application.Interactive = oldInteractive
        Application.EnableCancelKey = oldCancel
    End If
    mBusy = False
    RefreshUI
    Exit Sub
Failed:
    errNo = Err.Number
    errText = Err.Description
    On Error Resume Next
    If mBusy And Not operationCommitted Then Set mPending = previousPending
    If setState Then
        Application.EnableCancelKey = xlDisabled
        Application.Interactive = oldInteractive
    End If
    ReleaseStatus
    mBusy = False
    RefreshUI
    If setState Then Application.EnableCancelKey = oldCancel
    On Error GoTo 0
    If operationCommitted Then
        MsgBox SLC_U("C791 C5C5 0020 ACB0 ACFC B294 0020 B9CC B4E4 C5B4 C84C C9C0 B9CC 0020 0045 0078 0063 0065 006C 0020 C0C1 D0DC B97C 0020 BCF5 C6D0 D558 B294 0020 C911 0020 BB38 C81C AC00 0020 C0DD ACBC C2B5 B2C8 B2E4 002E") & vbCrLf & _
               SLC_U("ACB0 ACFC B97C 0020 D655 C778 D558 ACE0 0020 D544 C694 D55C 0020 D30C C77C C744 0020 C800 C7A5 D55C 0020 B4A4 0020 0045 0078 0063 0065 006C C744 0020 B2E4 C2DC 0020 C2E4 D589 D574 0020 C8FC C138 C694 002E") & vbCrLf & _
               SLC_U("C624 B958 0020 CF54 B4DC 003A 0020") & CStr(errNo), vbExclamation, SLC_U("BA85 B2E8 0020 BE44 AD50")
    ElseIf errNo = 18 Or errNo = ERR_CANCEL Then
        MsgBox SLC_U("C791 C5C5 C744 0020 CDE8 C18C D588 C2B5 B2C8 B2E4 002E 0020 B2F4 C544 0020 B454 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D C774 0020 C788 B2E4 BA74 0020 ADF8 B300 B85C 0020 B0A8 C544 0020 C788 C2B5 B2C8 B2E4 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
    Else
        MsgBox errText & vbCrLf & vbCrLf & SLC_U("B2F4 C544 0020 B454 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D ACFC 0020 C6D0 BCF8 0020 B0B4 C6A9 C740 0020 BC14 B00C C9C0 0020 C54A C558 C2B5 B2C8 B2E4 002E") & _
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
        Err.Raise ERR_LIMIT, , SLC_U("B530 B85C 0020 C120 D0DD D55C 0020 C601 C5ED C774 0020 0035 002C 0030 0030 0030 AC1C B97C 0020 B118 C2B5 B2C8 B2E4 002E 0020 C120 D0DD 0020 BC94 C704 B97C 0020 C904 C5EC 0020 C8FC C138 C694 002E")
    End If
    ' Intersect, not Find: never changes the user's Find/Replace settings.
    Set bounded = Application.Intersect(sel, sel.Worksheet.UsedRange)
    If bounded Is Nothing Then
        Set PrepareParts = parts
        Exit Function
    End If
    scanCount = CDbl(bounded.CountLarge)
    If scanCount > MAX_SCAN Then
        Err.Raise ERR_LIMIT, , SLC_U("C228 AE40 0020 C5EC BD80 B97C 0020 D655 C778 D560 0020 C140 C774 0020 0032 002C 0030 0030 0030 002C 0030 0030 0030 AC1C B97C 0020 B118 C2B5 B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("D589 C774 B098 0020 C5F4 0020 C804 CCB4 B97C 0020 C120 D0DD D588 B2E4 BA74 0020 AC12 C774 0020 C788 B294 0020 BD80 BD84 B9CC 0020 B2E4 C2DC 0020 C120 D0DD D574 0020 C8FC C138 C694 002E")
    End If
    If bounded.Areas.Count > MAX_AREAS Then
        Err.Raise ERR_LIMIT, , SLC_U("C120 D0DD D55C 0020 BC94 C704 AC00 0020 0035 002C 0030 0030 0030 AC1C AC00 0020 B118 B294 0020 C601 C5ED C73C B85C 0020 B098 B258 C5B4 0020 C788 C2B5 B2C8 B2E4 002E 0020 C120 D0DD 0020 BC94 C704 B97C 0020 C904 C5EC 0020 C8FC C138 C694 002E")
    End If
    If scanCount >= WARN_SCAN Or bounded.Areas.Count >= WARN_AREAS Then
        text = SLC_U("C120 D0DD D55C 0020 C140 C774 0020 B9CE C544 0020 C228 AE40 0020 C5EC BD80 B97C 0020 D655 C778 D558 B294 0020 B370 0020 C2DC AC04 C774 0020 AC78 B9B4 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("D655 C778 D560 0020 C140 003A 0020") & Format$(scanCount, "#,##0") & SLC_U("AC1C") & vbCrLf & _
            SLC_U("C228 AE34 0020 C140 ACFC 0020 D544 D130 B85C 0020 AC00 B824 C9C4 0020 C140 C740 0020 BE44 AD50 C5D0 C11C 0020 BE8D B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("C774 0020 C2DC D5D8 0020 BC84 C804 C5D0 C11C B294 0020 0045 0073 0063 B97C 0020 B20C B7EC B3C4 0020 C791 C5C5 C774 0020 CDE8 C18C B418 C9C0 0020 C54A C744 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("ACC4 C18D D560 AE4C C694 003F 0020 BC94 C704 B97C 0020 C904 C774 B824 BA74 0020 005B C544 B2C8 C694 005D B97C 0020 B204 B974 C138 C694 002E")
        If ask Then
            If MsgBox(text, vbYesNo + vbExclamation + vbDefaultButton2, SLC_U("BA85 B2E8 0020 BE44 AD50 0020 002D 0020 C120 D0DD 0020 BC94 C704 0020 D655 C778")) <> vbYes Then Exit Function
        End If
        warned = True
        mStarted = Timer
    End If
    For Each ar In bounded.Areas
        Checkpoint
        mergeState = ar.MergeCells
        If IsNull(mergeState) Then
            Err.Raise ERR_DATA, , SLC_U("C120 D0DD D55C 0020 BC94 C704 C5D0 0020 BCD1 D569 B41C 0020 C140 C774 0020 C788 C2B5 B2C8 B2E4 002E 0020 BCD1 D569 B41C 0020 C140 C744 0020 BE7C ACE0 0020 B2E4 C2DC 0020 C120 D0DD D574 0020 C8FC C138 C694 002E")
        ElseIf CBool(mergeState) Then
            Err.Raise ERR_DATA, , SLC_U("BCD1 D569 B41C 0020 C140 C740 0020 BE44 AD50 D560 0020 C218 0020 C5C6 C2B5 B2C8 B2E4 002E 0020 BCD1 D569 B418 C9C0 0020 C54A C740 0020 C140 C744 0020 C120 D0DD D574 0020 C8FC C138 C694 002E")
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
                    Err.Raise specialErr, , SLC_U("C5B4 B5A4 0020 C140 C774 0020 C228 ACA8 C838 0020 C788 B294 C9C0 0020 D655 C778 D558 C9C0 0020 BABB D588 C2B5 B2C8 B2E4 002E 0020 B2E4 C2DC 0020 C2E4 D589 D574 0020 C8FC C138 C694 002E")
                ElseIf Not EntirelyHidden(ar) Then
                    ' 1004 is ambiguous: do not silently turn a visibility failure into an empty list.
                    Err.Raise ERR_DATA, , SLC_U("C5B4 B5A4 0020 C140 C774 0020 C228 ACA8 C838 0020 C788 B294 C9C0 0020 D655 C778 D558 C9C0 0020 BABB D588 C2B5 B2C8 B2E4 002E 0020 C120 D0DD 0020 BC94 C704 B97C 0020 C904 C5EC 0020 B2E4 C2DC 0020 C2E4 D589 D574 0020 C8FC C138 C694 002E")
                End If
            End If
            If Not vis Is Nothing Then Set vis = Application.Intersect(ar, vis)
        End If
        If Not vis Is Nothing Then
            If parts.Count + vis.Areas.Count > MAX_AREAS Then
                Err.Raise ERR_LIMIT, , SLC_U("BE44 AD50 D560 0020 C140 C774 0020 0035 002C 0030 0030 0030 AC1C AC00 0020 B118 B294 0020 C601 C5ED C5D0 0020 B098 B258 C5B4 0020 C788 C2B5 B2C8 B2E4 002E 0020 C120 D0DD 0020 BC94 C704 B97C 0020 C904 C5EC 0020 C8FC C138 C694 002E")
            End If
            visibleCount = visibleCount + CDbl(vis.CountLarge)
            If visibleCount > MAX_VISIBLE Then
                Err.Raise ERR_LIMIT, , SLC_U("D55C 0020 BAA9 B85D C5D0 0020 B2F4 C744 0020 C218 0020 C788 B294 0020 C140 C740 0020 0031 0030 0030 002C 0030 0030 0030 AC1C AE4C C9C0 C785 B2C8 B2E4 002E 0020 C120 D0DD 0020 BC94 C704 B97C 0020 C904 C5EC 0020 C8FC C138 C694 002E") & vbCrLf & _
                    SLC_U("BE48 CE78 B3C4 0020 C774 0020 AC1C C218 C5D0 0020 D3EC D568 D569 B2C8 B2E4 002E 0020 C228 AE34 0020 C140 ACFC 0020 D544 D130 B85C 0020 AC00 B824 C9C4 0020 C140 C740 0020 C138 C9C0 0020 C54A C2B5 B2C8 B2E4 002E")
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
            text = SLC_U("C120 D0DD D55C 0020 AC12 C744 0020 C77D ACE0 0020 ACB0 ACFC B97C 0020 B9CC B4DC B294 0020 B370 0020 C2DC AC04 C774 0020 AC78 B9B4 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E") & vbCrLf & _
                   SLC_U("C774 BC88 C5D0 0020 C120 D0DD D55C 0020 BC94 C704 003A 0020 C228 AE30 C9C0 0020 C54A C740 0020 C140 0020") & Format$(visibleCount, "#,##0") & SLC_U("AC1C 0020 002F 0020") & _
                   Format$(parts.Count, "#,##0") & SLC_U("AC1C 0020 C601 C5ED") & vbCrLf & _
                   SLC_U("C774 BC88 0020 C791 C5C5 C5D0 C11C 0020 B2E4 B8F0 0020 C140 003A 0020") & Format$(combinedCount, "#,##0") & SLC_U("AC1C") & vbCrLf & _
                   SLC_U("C774 0020 C2DC D5D8 0020 BC84 C804 C5D0 C11C B294 0020 0045 0073 0063 B97C 0020 B20C B7EC B3C4 0020 C791 C5C5 C774 0020 CDE8 C18C B418 C9C0 0020 C54A C744 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E") & vbCrLf & _
                   SLC_U("ACC4 C18D D560 AE4C C694 003F 0020 BC94 C704 B97C 0020 C904 C774 B824 BA74 0020 005B C544 B2C8 C694 005D B97C 0020 B204 B974 C138 C694 002E")
            If ask Then
                If MsgBox(text, vbYesNo + vbExclamation + vbDefaultButton2, SLC_U("BA85 B2E8 0020 BE44 AD50 0020 002D 0020 C120 D0DD 0020 BC94 C704 0020 D655 C778")) <> vbYes Then Exit Function
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
    Dim optionalError As Long
    On Error Resume Next
    Set af = ws.AutoFilter
    optionalError = Err.Number
    Err.Clear
    On Error GoTo 0
    If optionalError = 18 Then Err.Raise 18
    If Not af Is Nothing Then AddRect rects, af.Range.Rows(1)
    For Each lo In ws.ListObjects
        Checkpoint
        Set hdr = Nothing
        On Error Resume Next
        Set hdr = lo.HeaderRowRange
        optionalError = Err.Number
        Err.Clear
        On Error GoTo 0
        If optionalError = 18 Then Err.Raise 18
        If Not hdr Is Nothing Then AddRect rects, hdr
        If lo.ShowTotals Then
            Set hdr = Nothing
            On Error Resume Next
            Set hdr = lo.TotalsRowRange
            optionalError = Err.Number
            Err.Clear
            On Error GoTo 0
            If optionalError = 18 Then Err.Raise 18
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
    Dim firstRow As Long, firstColumn As Long, unseen As Boolean
    Dim coordinate As String
    ' A single rectangular part cannot visit the same cell twice.
    If parts.Count > 1 Then Set seen = CreateObject("Scripting.Dictionary")
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
            ' Keep Excel object-model calls outside the per-cell loop.
            firstRow = block.Row
            firstColumn = block.Column
            For r = 1 To takeRows
                absR = firstRow + r - 1
                For c = 1 To nc
                    absC = firstColumn + c - 1
                    unseen = True
                    If Not seen Is Nothing Then
                        coordinate = CStr(absR) & ":" & CStr(absC)
                        unseen = Not seen.Exists(coordinate)
                        If unseen Then seen.Add coordinate, True
                    End If
                    If unseen Then
                        result.VisibleCellCount = result.VisibleCellCount + 1
                        If IsMetadata(absR, absC, exclusions) Then
                            result.MetadataCount = result.MetadataCount + 1
                        Else
                            If takeRows = 1 And nc = 1 Then v = vals Else v = vals(r, c)
                            AddValue result, v, CellAddress(absR, absC)
                        End If
                    End If
                    tick = tick + 1
                    If tick Mod CANCEL_POLL_ITEMS = 0 Then PollCancellation
                    If tick Mod 512 = 0 Then
                        SetStatus SLC_U("BA85 B2E8 0020 BE44 AD50 003A 0020 C140 0020") & Format$(result.VisibleCellCount, "#,##0") & SLC_U("AC1C 0020 D655 C778 0020 C911")
                        Checkpoint
                    End If
                Next c
            Next r
        Next r0
    Next ar
    Checkpoint
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
        Err.Raise ERR_LIMIT, , address & SLC_U("0020 C140 C758 0020 B0B4 C6A9 C774 0020 0034 002C 0030 0039 0036 C790 B97C 0020 B118 C2B5 B2C8 B2E4 002E 0020 C774 0020 C140 C744 0020 BE7C ACE0 0020 B2E4 C2DC 0020 C120 D0DD D574 0020 C8FC C138 C694 002E")
    End If
    list.RawCharCount = list.RawCharCount + Len(raw)
    If list.RawCharCount > MAX_RAW_CHARS Then
        Err.Raise ERR_LIMIT, , SLC_U("C120 D0DD D55C 0020 C140 C758 0020 B0B4 C6A9 C744 0020 BAA8 B450 0020 D569 CE58 BA74 0020 0035 002C 0030 0030 0030 002C 0030 0030 0030 C790 B97C 0020 B118 C2B5 B2C8 B2E4 002E 0020 C120 D0DD 0020 BC94 C704 B97C 0020 C904 C5EC 0020 C8FC C138 C694 002E")
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
    If rng.Areas.Count > 6 Then s = s & SLC_U("0020 002E 002E 002E 0020 0028 CD1D 0020") & CStr(rng.Areas.Count) & SLC_U("AC1C 0020 C601 C5ED 0029")
    SourceLabel = rng.Worksheet.Parent.FullName & " / " & rng.Worksheet.Name & "!" & s
End Function

Private Sub Checkpoint()
    Dim elapsed As Double
    ' Excel may reset this setting while dispatching window/UI callbacks.
    ' Keep the running operation's handler armed on both sides of DoEvents.
    Application.EnableCancelKey = xlErrorHandler
    PollCancellation
    DoEvents
    Application.EnableCancelKey = xlErrorHandler
    PollCancellation
    elapsed = Timer - mStarted
    If elapsed < 0 Then elapsed = elapsed + 86400#
    If elapsed > MAX_ACTIVE_SECONDS Then
        Err.Raise ERR_TIME, , SLC_U("C791 C5C5 0020 C2DC AC04 C774 0020 AE38 C5B4 C838 0020 C911 B2E8 D588 C2B5 B2C8 B2E4 002E 0020 C120 D0DD 0020 BC94 C704 B97C 0020 C904 C5EC 0020 B2E4 C2DC 0020 C2E4 D589 D574 0020 C8FC C138 C694 002E")
    End If
End Sub

Private Sub PollCancellation()
    ' Sample only while this product is executing; never register a key/hook.
    If mBusy Then
        If OwnForegroundEscapeHeld() Then mCancelled = True
    End If
    If mCancelled Then Err.Raise ERR_CANCEL, , "Cancelled"
End Sub

Private Function OwnForegroundEscapeHeld() As Boolean
#If VBA7 Then
    Dim foreground As LongPtr
#Else
    Dim foreground As Long
#End If
    Dim foregroundPid As Long, ownPid As Long, keyState As Integer
    If Not mBusy Then Exit Function
    foreground = SLC_GetForegroundWindow()
    If foreground = 0 Then Exit Function
    ownPid = SLC_GetCurrentProcessId()
    If ownPid = 0 Then Exit Function
    If SLC_GetWindowThreadProcessId(foreground, foregroundPid) = 0 Then Exit Function
    If foregroundPid <> ownPid Then Exit Function
    ' SHORT's sign bit means currently down. The unreliable low history bit is
    ' never used. No key is sampled while a different process is foreground.
    keyState = SLC_GetAsyncKeyState(vbKeyEscape)
    OwnForegroundEscapeHeld = HeldEscapeSampleCancels(mBusy, foregroundPid, ownPid, _
        (SLC_GetForegroundWindow() = foreground), keyState)
    ' No error suppression: API/policy failures and native error 18 propagate to
    ' the operation's existing rollback/error handler.
End Function

Private Function HeldEscapeSampleCancels(ByVal busy As Boolean, ByVal foregroundPid As Long, _
                                        ByVal ownPid As Long, ByVal foregroundStable As Boolean, _
                                        ByVal keyState As Integer) As Boolean
    If Not busy Or Not foregroundStable Then Exit Function
    If ownPid = 0 Or foregroundPid = 0 Or foregroundPid <> ownPid Then Exit Function
    HeldEscapeSampleCancels = (keyState < 0)
End Function

Private Sub SetStatus(ByVal text As String)
    If Not mOwnStatus Then
        mPreviousStatus = PreviousStatus()
        mOwnStatus = True
    End If
    If mOwnStatus Then
        If CStr(Application.StatusBar) <> mLastStatus And Len(mLastStatus) > 0 Then
            mPreviousStatus = PreviousStatus()
        End If
    End If
    mLastStatus = text
    Application.StatusBar = text
End Sub

Private Function PreviousStatus() As Variant
    Dim value As Variant
    value = Application.StatusBar
    ' Some Excel builds expose their default False sentinel as text after a
    ' custom status was shown. Do not restore that sentinel as visible text.
    If VarType(value) = vbString Then
        If StrComp(CStr(value), CStr(False), vbTextCompare) = 0 Then value = False
    End If
    PreviousStatus = value
End Function

Private Sub ReleaseStatus()
    On Error Resume Next
    If mOwnStatus Then
        If VarType(Application.StatusBar) = vbString Then
            If CStr(Application.StatusBar) = mLastStatus Then
                ' Pass an actual Boolean, not a Variant coerced to display text.
                If VarType(mPreviousStatus) = vbBoolean Then
                    Application.StatusBar = False
                Else
                    Application.StatusBar = mPreviousStatus
                End If
            End If
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
        tick = tick + 1
        If tick Mod CANCEL_POLL_ITEMS = 0 Then PollCancellation
        If tick Mod 1024 = 0 Then Checkpoint
    Next k
    For Each k In b.Counts.Keys
        If Not keys.Exists(CStr(k)) Then keys.Add CStr(k), True
        tick = tick + 1
        If tick Mod CANCEL_POLL_ITEMS = 0 Then PollCancellation
        If tick Mod 1024 = 0 Then Checkpoint
    Next k
    For Each k In keys.Keys
        ca = CountOf(a, CStr(k))
        cb = CountOf(b, CStr(k))
        If ca < cb Then matched = matched + ca Else matched = matched + cb
        If ca > cb Then excessA = excessA + ca - cb
        If cb > ca Then excessB = excessB + cb - ca
        tick = tick + 1
        If tick Mod CANCEL_POLL_ITEMS = 0 Then PollCancellation
        If tick Mod 1024 = 0 Then Checkpoint
    Next k
    Checkpoint
    If excessA = 0 And excessB = 0 And a.DuplicateExcess = 0 And b.DuplicateExcess = 0 _
        And a.ErrorCount = 0 And b.ErrorCount = 0 Then
        ReleaseStatus
        MsgBox SLC_U("BE44 AD50 0020 ADDC CE59 C744 0020 C801 C6A9 D55C 0020 ACB0 ACFC 002C 0020 B450 0020 BAA9 B85D C758 0020 AC12 ACFC 0020 AC1C C218 AC00 0020 AC19 C2B5 B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 003A 0020") & Format$(a.Total, "#,##0") & SLC_U("AC1C 0020 D56D BAA9") & vbCrLf & _
            SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 003A 0020") & Format$(b.Total, "#,##0") & SLC_U("AC1C 0020 D56D BAA9") & vbCrLf & _
            SLC_U("C774 BA54 C77C C740 0020 0040 0020 C55E BD80 BD84 B9CC 0020 BE44 AD50 D569 B2C8 B2E4 002E 0020 C22B C790 0020 D45C AE30 002C 0020 C601 BB38 0020 B300 C18C BB38 C790 002C 0020 C77C BD80 0020 ACF5 BC31 0020 CC28 C774 B294 0020 BB34 C2DC D569 B2C8 B2E4 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
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
    ws.Range("A2").Value2 = SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 C704 CE58 0020 002F 0020 B2F4 C740 0020 C2DC AC01")
    ws.Range("B2:J2").Merge
    ws.Range("B2").Value2 = OutputText(a.Source & " / " & Format$(a.CapturedAt, "yyyy-mm-dd hh:nn:ss"))
    ws.Range("A3").Value2 = SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 C704 CE58 0020 002F 0020 B2F4 C740 0020 C2DC AC01")
    ws.Range("B3:J3").Merge
    ws.Range("B3").Value2 = OutputText(b.Source & " / " & Format$(b.CapturedAt, "yyyy-mm-dd hh:nn:ss"))
    ws.Range("A4").Value2 = SLC_U("D56D BAA9 0020 C218")
    ws.Range("B4:J4").Merge
    ws.Range("B4").Value2 = SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 003A 0020") & a.Total & SLC_U("AC1C 0020 D56D BAA9 0020 002F 0020 B450 0020 BC88 C9F8 0020 BAA9 B85D 003A 0020") & b.Total & _
        SLC_U("AC1C 0020 D56D BAA9 0020 002F 0020 C77C CE58 0020") & matched & SLC_U("AC1C 0020 002F 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B0A8 C740 0020 D56D BAA9 0020") & excessA & SLC_U("AC1C 0020 002F 0020 B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 B0A8 C740 0020 D56D BAA9 0020") & excessB & SLC_U("AC1C")
    ws.Range("A5").Value2 = SLC_U("C911 BCF5 B41C 0020 AC12 0020 002F 0020 BE44 AD50 C5D0 C11C 0020 BE80 0020 C140")
    ws.Range("B5:J5").Merge
    ws.Range("B5").Value2 = SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 003A 0020 C911 BCF5 0020") & a.DuplicateExcess & SLC_U("AC1C 0020 002F 0020 BE44 AD50 C5D0 C11C 0020 BE80 0020 C140 003A 0020 BE48 CE78 0020") & a.BlankCount & _
        SLC_U("AC1C 002C 0020 C624 B958 0020") & a.ErrorCount & SLC_U("AC1C 002C 0020 D45C 0020 C81C BAA9 00B7 D569 ACC4 0020") & a.MetadataCount & SLC_U("AC1C") & vbLf & _
        SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 003A 0020 C911 BCF5 0020") & b.DuplicateExcess & SLC_U("AC1C 0020 002F 0020 BE44 AD50 C5D0 C11C 0020 BE80 0020 C140 003A 0020 BE48 CE78 0020") & b.BlankCount & _
        SLC_U("AC1C 002C 0020 C624 B958 0020") & b.ErrorCount & SLC_U("AC1C 002C 0020 D45C 0020 C81C BAA9 00B7 D569 ACC4 0020") & b.MetadataCount & SLC_U("AC1C") & vbLf & _
        SLC_U("C911 BCF5 C740 0020 AC19 C740 0020 AC12 C774 0020 B450 0020 BC88 C9F8 B85C 0020 B098 C628 0020 AC83 BD80 D130 0020 C149 B2C8 B2E4 002E 0020 AC19 C740 0020 AC12 C774 0020 0033 AC1C 0020 C788 C73C BA74 0020 C911 BCF5 C740 0020 0032 AC1C C785 B2C8 B2E4 002E")
    ws.Range("A6").Value2 = SLC_U("BE44 AD50 0020 ADDC CE59")
    ws.Range("B6:J6").Merge
    ws.Range("B6").Value2 = SLC_U("C774 BA54 C77C C740 0020 0040 0020 C55E BD80 BD84 B9CC 0020 BE44 AD50 D569 B2C8 B2E4 002E 0020 C22B C790 0020 D45C AE30 00B7 C601 BB38 0020 B300 C18C BB38 C790 00B7 C77C BD80 0020 ACF5 BC31 0020 CC28 C774 B294 0020 BB34 C2DC D569 B2C8 B2E4 002E 0020 BB38 C790 B85C 0020 C785 B825 D55C 0020 0030 0030 0031 0032 0033 ACFC 0020 C22B C790 0020 0031 0032 0033 C740 0020 B2E4 B974 AC8C 0020 BD05 B2C8 B2E4 002E") & vbLf & _
        SLC_U("B0A8 C740 0020 AC1C C218 003A 0020 AC19 C740 0020 AC12 C774 0020 CCAB 0020 BC88 C9F8 C5D0 0020 0032 AC1C 002C 0020 B450 0020 BC88 C9F8 C5D0 0020 0031 AC1C BA74 0020 CCAB 0020 BC88 C9F8 C5D0 0020 0031 AC1C AC00 0020 B0A8 C2B5 B2C8 B2E4 002E")
    ws.Range("A7:J7").Merge
    If a.ErrorCount + b.ErrorCount > 0 Then
        ws.Range("A7").Value2 = SLC_U("C624 B958 0020 C140 C744 0020 BE80 0020 ACB0 ACFC C774 BBC0 B85C 0020 C6D0 BCF8 0020 C804 CCB4 AC00 0020 AC19 B2E4 ACE0 0020 BCFC 0020 C218 B294 0020 C5C6 C2B5 B2C8 B2E4 002E 0020 C6D0 B798 0020 AC12 0020 0028 C608 0029 C640 0020 C140 0020 C8FC C18C B294 0020 D574 B2F9 0020 D56D BAA9 C774 0020 AC01 0020 BAA9 B85D C5D0 C11C 0020 CC98 C74C 0020 B098 C628 0020 C140 C744 0020 BCF4 C5EC C90D B2C8 B2E4 002E")
    Else
        ws.Range("A7").Value2 = SLC_U("D45C C5D0 B294 0020 CC28 C774 00B7 C911 BCF5 B9CC 0020 BCF4 C5EC C90D B2C8 B2E4 002E 0020 C6D0 B798 0020 AC12 0020 0028 C608 0029 C640 0020 C140 0020 C8FC C18C B294 0020 D574 B2F9 0020 D56D BAA9 C774 0020 AC01 0020 BAA9 B85D C5D0 C11C 0020 CC98 C74C 0020 B098 C628 0020 C140 C744 0020 BCF4 C5EC C90D B2C8 B2E4 002E")
    End If
    labels = Array(SLC_U("C0C1 D0DC"), SLC_U("BE44 AD50 C5D0 0020 C4F4 0020 AC12"), SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 C6D0 B798 0020 AC12 0020 0028 C608 0029"), SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 AC1C C218"), _
        SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 C6D0 B798 0020 AC12 0020 0028 C608 0029"), SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 AC1C C218"), SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B0A8 C740 0020 AC1C C218"), SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 B0A8 C740 0020 AC1C C218"), _
        SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 C140 0020 C8FC C18C"), SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 C140 0020 C8FC C18C"))
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
                status = SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D C5D0 B9CC 0020 C788 C74C")
            ElseIf cb = 0 Then
                status = SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D C5D0 B9CC 0020 C788 C74C")
            ElseIf ca <> cb Then
                status = SLC_U("AC1C C218 AC00 0020 B2E4 B984")
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
        If tick Mod CANCEL_POLL_ITEMS = 0 Then PollCancellation
        If tick Mod 1024 = 0 Then Checkpoint
    Next k
    If fill > 0 Then FlushOutput ws, buffer, fill, outRow
    If outRow = 9 Then
        ws.Range("A9").Value2 = SLC_U("BE44 AD50 D55C 0020 AC12 ACFC 0020 AC1C C218 B294 0020 AC19 C2B5 B2C8 B2E4 002E 0020 BE44 AD50 C5D0 C11C 0020 BE80 0020 C624 B958 0020 C140 C740 0020 C6D0 BCF8 C5D0 C11C 0020 D655 C778 D574 0020 C8FC C138 C694 002E")
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
        .Range("A5:J5").RowHeight = 60
        .Range("A6:J6").RowHeight = 48
        .Range("A8:J8").RowHeight = 48
        .Range("A8:J" & CStr(outRow - 1)).AutoFilter
    End With
    wb.Activate
    ws.Range("A9").Select
    wb.Windows(1).FreezePanes = True
    ws.Range("A1").Select
    ' Until this checkpoint, the new workbook is provisional and the failure
    ' handler closes only that workbook, preserving all older results.
    Checkpoint
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
    MsgBox "Excel Smart List Compare " & SLC_ReleaseVersion() & vbCrLf & vbCrLf & _
        SLC_U("0031 002E 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D C744 0020 C120 D0DD D558 ACE0 0020 005B CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 AE30 005D B97C 0020 B204 B974 C138 C694 002E") & vbCrLf & _
        SLC_U("0032 002E 0020 B450 0020 BC88 C9F8 0020 BAA9 B85D C744 0020 C120 D0DD D558 ACE0 0020 005B B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 C544 0020 BE44 AD50 005D B97C 0020 B204 B974 C138 C694 002E") & vbCrLf & vbCrLf & _
        SLC_U("C120 D0DD D55C 0020 C140 0020 C804 CCB4 AC00 0020 BAA9 B85D 0020 D558 B098 C774 BA70 002C 0020 C140 C758 0020 AC12 0020 D558 B098 B97C 0020 D56D BAA9 C774 B77C ACE0 0020 D569 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("AC00 B85C 002C 0020 C138 B85C 002C 0020 C5EC B7EC 0020 C601 C5ED C744 0020 C120 D0DD D574 B3C4 0020 BAA9 B85D 0020 D558 B098 B85C 0020 BE44 AD50 D569 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("B2E4 B978 0020 D30C C77C B85C 0020 C774 B3D9 D55C 0020 B4A4 C5D0 B3C4 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D C758 0020 AC1C C218 0020 D45C C2DC AC00 0020 BCF4 C774 BA74 0020 C774 C5B4 C11C 0020 BE44 AD50 D560 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("C228 AE34 0020 C140 002C 0020 D544 D130 B85C 0020 AC00 B824 C9C4 0020 C140 002C 0020 BE48 CE78 002C 0020 C624 B958 0020 C140 002C 0020 D45C C758 0020 C81C BAA9 00B7 D569 ACC4 0020 C140 C740 0020 BE44 AD50 C5D0 C11C 0020 BE8D B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("AC19 C740 0020 AC12 C774 0020 BA87 0020 BC88 0020 B098 C624 B294 C9C0 B3C4 0020 BE44 AD50 D569 B2C8 B2E4 002E 0020 C774 BA54 C77C C740 0020 0040 0020 C55E BD80 BD84 B9CC 0020 BE44 AD50 D569 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("C6D0 BCF8 C740 0020 BC14 AFB8 C9C0 0020 C54A C2B5 B2C8 B2E4 002E 0020 CC28 C774 00B7 C911 BCF5 00B7 C624 B958 B294 0020 C0C8 0020 D30C C77C C5D0 0020 D45C C2DC D558 BA70 002C 0020 D544 C694 D558 BA74 0020 C9C1 C811 0020 C800 C7A5 D574 0020 C8FC C138 C694 002E") & vbCrLf & _
        SLC_U("D55C 0020 BAA9 B85D C740 0020 C228 AE30 C9C0 0020 C54A C740 0020 C140 C744 0020 BE48 CE78 AE4C C9C0 0020 D569 CCD0 0020 0031 0030 0030 002C 0030 0030 0030 AC1C B85C 0020 C81C D55C D569 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("C218 B3D9 0020 ACC4 C0B0 C744 0020 C4F0 ACE0 0020 C788 B2E4 BA74 0020 BA3C C800 0020 C218 C2DD C744 0020 ACC4 C0B0 D574 0020 C8FC C138 C694 002E") & vbCrLf & _
        SLC_U("AE34 0020 C0AC BC88 C774 B098 0020 0049 0044 B294 0020 CC98 C74C 0020 C785 B825 D560 0020 B54C BD80 D130 0020 D14D C2A4 D2B8 0020 D615 C2DD C73C B85C 0020 C800 C7A5 D574 0020 C8FC C138 C694 002E") & vbCrLf & _
        SLC_U("C774 0020 C2DC D5D8 0020 BC84 C804 C5D0 C11C B294 0020 0045 0073 0063 B97C 0020 B20C B7EC B3C4 0020 C791 C5C5 C774 0020 CDE8 C18C B418 C9C0 0020 C54A C744 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E"), _
        vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50 0020 002D 0020 C0AC C6A9 0020 C548 B0B4")
End Sub

' Integration tests must be executed in Windows desktop Excel, not a VBA emulator.
Public Function SLC_CancellationDecisionTests() As Long
    ' Pure decisions: no HWND/API calls, keyboard input or Excel state changes.
    Dim cases As Variant, sample As Variant, actual As Boolean, passed As Long
    cases = Array( _
        Array("key up", True, 42&, 42&, True, 0, False), _
        Array("low history bit only", True, 42&, 42&, True, 1, False), _
        Array("reserved bits without high bit", True, 42&, 42&, True, 32767, False), _
        Array("held high bit", True, 42&, 42&, True, -32768, True), _
        Array("held plus history", True, 42&, 42&, True, -32767, True), _
        Array("held with other bits", True, 42&, 42&, True, -1, True), _
        Array("idle product", False, 42&, 42&, True, -32768, False), _
        Array("foreground changed", True, 42&, 42&, False, -32768, False), _
        Array("different foreground process", True, 43&, 42&, True, -32768, False), _
        Array("missing foreground process", True, 0&, 42&, True, -32768, False), _
        Array("missing own process", True, 42&, 0&, True, -32768, False), _
        Array("both process identifiers absent", True, 0&, 0&, True, -32768, False))
    For Each sample In cases
        actual = HeldEscapeSampleCancels(CBool(sample(1)), CLng(sample(2)), CLng(sample(3)), _
            CBool(sample(4)), CInt(sample(5)))
        If actual <> CBool(sample(6)) Then Err.Raise ERR_DATA, , "Held Esc decision: " & CStr(sample(0))
        passed = passed + 1
    Next sample
    SLC_CancellationDecisionTests = passed
End Function

Public Function SLC_TestAll() As String
    Dim wb As Workbook, other As Workbook, ws As Worksheet, lo As ListObject
    Dim a As CSLCList, b As CSLCList, parts As Collection, rects As Collection
    Dim arr(1 To 2, 1 To 2) As Variant, i As Long, n As Long
    Dim oldEvents As Boolean, oldCancel As XlEnableCancelKey, oldBook As Workbook
    Dim errNo As Long, errText As String, cancelChecks As Long
    On Error GoTo Failed
    oldEvents = Application.EnableEvents
    oldCancel = Application.EnableCancelKey
    Set oldBook = Application.ActiveWorkbook
    Application.EnableEvents = False
    Application.EnableCancelKey = xlErrorHandler
    mStarted = Timer
    mCancelled = False
    SLC_NormalizeTests
    cancelChecks = SLC_CancellationDecisionTests()
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
    SLC_TestAll = "PASS: normalization + " & CStr(n) & " Excel integration checks + " & _
        CStr(cancelChecks) & " cancellation decision checks"
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
