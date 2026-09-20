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
Private mUiFailure As String
Private mAppEvents As CSLCAppEvents
Private mRibbonLoaded As Boolean
Private mOwnStatus As Boolean
Private mPreviousStatus As Variant
Private mLastStatus As String
Private mPhase As String
Private mLastOutcome As String
Private Const SETTINGS_APP As String = "ExcelSmartListCompare"
Private Const SETTINGS_SECTION As String = "Preferences"
Private Const SETTINGS_KEY As String = "OptionsV1"
Private mSettingsLoaded As Boolean
Private mFullEmail As Boolean
Private mIgnoreCase As Boolean
Private mKeepFirst As Boolean
Private mSettingsTestSection As String
Private mTestOutputFailure As Boolean

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
    SLC_ReleaseVersion = "0.2.0-rc.11"
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
    ' Menu creation reads only the stored snapshot, never the current selection.
    LoadSettings
    xml = "<menu xmlns=""http://schemas.microsoft.com/office/2009/07/customui"">"
    If mBusy Then
        xml = xml & MenuLabel(prefix & "Progress", mPhase)
        xml = xml & MenuButton(prefix & "Cancel", SLC_U("C791 C5C5 0020 CDE8 C18C"), "SLC_CancelClick")
    Else
        If mPending Is Nothing Then
            xml = xml & MenuButton(prefix & "Capture", SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 AE30"), "SLC_CaptureClick")
        Else
            xml = xml & MenuButton(prefix & "Compare", SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 C544 0020 BE44 AD50"), "SLC_CompareClick")
            xml = xml & MenuLabel(prefix & "Count", PendingLabel())
            xml = xml & MenuLabel(prefix & "Source", PendingSource())
            xml = xml & MenuButton(prefix & "Preview", SLC_U("B2F4 C740 0020 BAA9 B85D 0020 D655 C778"), "SLC_PreviewClick")
            xml = xml & MenuButton(prefix & "Replace", SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 BC14 AFB8 AE30"), "SLC_ReplaceClick")
            xml = xml & MenuButton(prefix & "Clear", SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 BE44 C6B0 AE30"), "SLC_ClearClick")
        End If
        If Len(mLastOutcome) > 0 Then xml = xml & MenuLabel(prefix & "Outcome", mLastOutcome)
        xml = xml & SettingsMenuXml(prefix)
        xml = xml & MenuButton(prefix & "About", SLC_U("C0AC C6A9 0020 C548 B0B4"), "SLC_AboutClick")
    End If
    SLC_MenuXml = xml & "</menu>"
End Function

Private Function XmlLabel(ByVal value As String) As String
    value = Replace(value, "&", "&amp;")
    value = Replace(value, "<", "&lt;")
    value = Replace(value, ">", "&gt;")
    value = Replace(value, Chr$(34), "&quot;")
    XmlLabel = Replace(value, "'", "&apos;")
End Function

Private Function MenuLabel(ByVal id As String, ByVal label As String) As String
    MenuLabel = "<button id=""" & id & """ enabled=""false"" label=""" & XmlLabel(label) & """/>"
End Function

Private Function PendingLabel() As String
    If mPending Is Nothing Then
        PendingLabel = SLC_U("B2F4 C544 0020 B454 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D C774 0020 C5C6 C2B5 B2C8 B2E4 002E")
    Else
        PendingLabel = SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 003A 0020") & Format$(mPending.Total, "#,##0") & SLC_U("AC1C 0020 D56D BAA9")
    End If
End Function

Private Function PendingSource() As String
    If Not mPending Is Nothing Then PendingSource = mPending.DisplaySource
End Function

Private Function PendingSummary() As String
    PendingSummary = PendingLabel()
    If Not mPending Is Nothing Then PendingSummary = PendingSummary & vbCrLf & mPending.DisplaySource
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
Public Sub SLC_PreviewClick(ByVal control As Office.IRibbonControl)
    SLC_Preview
End Sub
Public Sub SLC_CancelClick(ByVal control As Office.IRibbonControl)
    SLC_Cancel
End Sub
Public Sub SLC_AboutClick(ByVal control As Office.IRibbonControl)
    SLC_About
End Sub

Public Sub SLC_Capture()
    Dim completed As Workbook
    RunSelection True, completed
End Sub
Public Sub SLC_Compare()
    Dim completed As Workbook
    If mBusy Then Exit Sub
    If mPending Is Nothing Then
        MsgBox SLC_U("BA3C C800 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D C744 0020 C120 D0DD D558 ACE0 0020 005B CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 AE30 005D B97C 0020 B204 B974 C138 C694 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        Exit Sub
    End If
    RunSelection False, completed
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
    Dim bar As CommandBar, settings As CommandBarPopup
    Dim uiStage As String
    On Error GoTo Failed
    If mUiAttached Then Exit Sub
    mUiFailure = ""
    uiStage = "load settings"
    LoadSettings
    uiStage = "remove own UI"
    RemoveOwnUI
    uiStage = "create toolbar"
    Set bar = Application.CommandBars.Add(Name:=BAR_NAME, Position:=msoBarTop, Temporary:=True)
    uiStage = "add standard buttons"
    AddButton bar.Controls, SLC_U("BA85 B2E8 0020 BE44 AD50"), "SLC_Run", "run"
    AddButton bar.Controls, "", "", "pending"
    AddButton bar.Controls, SLC_U("B2F4 C740 0020 BAA9 B85D 0020 D655 C778"), "SLC_Preview", "preview"
    AddButton bar.Controls, SLC_U("C791 C5C5 0020 CDE8 C18C"), "SLC_Cancel", "cancel"
    AddButton bar.Controls, "", "", "progress"
    AddButton bar.Controls, SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 BE44 C6B0 AE30"), "SLC_Clear", "clear"
    AddButton bar.Controls, SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 BC14 AFB8 AE30"), "SLC_Replace", "replace"
    uiStage = "add settings popup"
    Set settings = bar.Controls.Add(Type:=msoControlPopup, Temporary:=True)
    settings.Caption = SLC_U("BE44 AD50 0020 C124 C815")
    settings.Tag = UI_TAG & ".settings"
    uiStage = "add settings buttons"
    AddButton settings.Controls, SLC_U("BA54 C77C 0020 C804 CCB4 0020 C8FC C18C 0020 BE44 AD50 0020 0028 0040 0020 B4A4 0020 D3EC D568 0029"), "SLC_ToggleFullEmail", "fullEmail"
    AddButton settings.Controls, SLC_U("B300 C18C BB38 C790 0020 BB34 C2DC"), "SLC_ToggleIgnoreCase", "ignoreCase"
    AddButton settings.Controls, SLC_U("BE44 AD50 0020 D6C4 0020 CCAB 0020 BAA9 B85D 0020 C720 C9C0"), "SLC_ToggleKeepFirst", "keepFirst"
    AddButton settings.Controls, SLC_U("AE30 BCF8 AC12 C73C B85C 0020 B418 B3CC B9AC AE30"), "SLC_ResetSettings", "resetSettings"
    AddButton settings.Controls, "", "", "settingsNote"
    AddButton bar.Controls, SLC_U("C0AC C6A9 0020 C548 B0B4"), "SLC_About", "about"
    uiStage = "show toolbar"
    bar.Visible = True
    ' Context menus are registered by customUI14.xml, never by legacy controls.
    uiStage = "attach events"
    Set mAppEvents = New CSLCAppEvents
    Set mAppEvents.ExcelApp = Application
    mUiAttached = True
    RefreshUI
    Exit Sub
Failed:
    mUiFailure = uiStage & " / " & CStr(Err.Number) & " / " & Err.Description
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
    Dim bar As CommandBar, ctl As CommandBarControl, title As String
    If Not mUiAttached Then Exit Sub
    If mPending Is Nothing Then title = SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 AE30") Else title = SLC_U("B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 C544 0020 BE44 AD50")
    On Error Resume Next
    Set bar = Application.CommandBars(BAR_NAME)
    If bar Is Nothing Then Exit Sub
    For Each ctl In bar.Controls
        Select Case ctl.Tag
            Case UI_TAG & ".run"
                ctl.Caption = title
                ctl.Enabled = Not mBusy
            Case UI_TAG & ".pending"
                ctl.Caption = Replace(PendingLabel() & SLC_U("0020 00B7 0020") & PendingSource(), "&", "&&")
                ctl.Visible = Not (mPending Is Nothing)
            Case UI_TAG & ".preview", UI_TAG & ".clear", UI_TAG & ".replace"
                ctl.Enabled = Not mBusy And Not (mPending Is Nothing)
            Case UI_TAG & ".cancel"
                ctl.Visible = mBusy
                ctl.Enabled = mBusy And Not mCancelled
            Case UI_TAG & ".progress"
                If mBusy Then ctl.Caption = mPhase Else ctl.Caption = mLastOutcome
                ctl.Visible = (Len(ctl.Caption) > 0)
            Case UI_TAG & ".settings"
                ctl.Enabled = Not mBusy
                RefreshSettingsControls ctl
            Case UI_TAG & ".about"
                ctl.Enabled = Not mBusy
        End Select
    Next ctl
    On Error GoTo 0
End Sub

Public Sub SLC_Clear()
    If mBusy Then Exit Sub
    Set mPending = Nothing
    mLastOutcome = SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D C744 0020 BE44 C6E0 C2B5 B2C8 B2E4 002E 0020 C6D0 BCF8 0020 C140 C740 0020 ADF8 B300 B85C C785 B2C8 B2E4 002E")
    ReleaseStatus
    RefreshUI
End Sub

Public Sub SLC_Cancel()
    If Not mBusy Then Exit Sub
    mCancelled = True
    mPhase = SLC_U("CDE8 C18C 0020 C694 CCAD B428 0020 00B7 0020 C791 C5C5 0020 C885 B8CC B97C 0020 AE30 B2E4 B824 0020 C8FC C138 C694 002E")
    SetStatus SLC_U("BA85 B2E8 0020 BE44 AD50 003A 0020") & mPhase
    RefreshUI
End Sub

Public Function SLC_CurrentState() As String
    ' Read-only diagnostic and accessible status, containing no cell values.
    If mBusy Then
        SLC_CurrentState = mPhase & vbCrLf & PendingSummary()
    Else
        SLC_CurrentState = mLastOutcome & vbCrLf & PendingSummary()
    End If
End Function

Private Sub SetPhase(ByVal text As String)
    mPhase = text
    SetStatus SLC_U("BA85 B2E8 0020 BE44 AD50 003A 0020") & text
    RefreshUI
End Sub

Public Sub SLC_WorkCheckpoint()
    Checkpoint
End Sub

Public Sub SLC_WorkStatus(ByVal text As String)
    SetPhase text
End Sub

Public Sub SLC_Preview()
    Dim completed As Workbook
    PreviewSnapshot completed
End Sub

Private Sub PreviewSnapshot(ByRef completedResult As Workbook, Optional ByVal raiseTestError As Boolean = False)
    Dim oldCancel As XlEnableCancelKey, errNo As Long, errText As String
    Dim operationCommitted As Boolean
    If mBusy Or mPending Is Nothing Then Exit Sub
    oldCancel = Application.EnableCancelKey
    On Error GoTo Failed
    mBusy = True
    mCancelled = False
    mStarted = Timer
    Application.EnableCancelKey = xlErrorHandler
    SetPhase SLC_U("B2F4 C740 0020 BAA9 B85D 0020 D655 C778 0020 C790 B8CC 0020 C791 C131 0020 C911")
    Set completedResult = SLC_WriteSnapshotPreview(mPending)
    operationCommitted = True
    Application.EnableCancelKey = xlDisabled
    mLastOutcome = SLC_U("B2F4 C740 0020 BAA9 B85D 0020 D655 C778 0020 C790 B8CC B97C 0020 B9CC B4E4 C5C8 C2B5 B2C8 B2E4 002E 0020 CCAB 0020 BAA9 B85D C740 0020 C720 C9C0 B429 B2C8 B2E4 002E")
Finished:
    ReleaseStatus
    mBusy = False
    mPhase = ""
    Application.EnableCancelKey = oldCancel
    RefreshUI
    Exit Sub
Failed:
    errNo = Err.Number: errText = Err.Description
    On Error Resume Next
    ReleaseStatus
    mBusy = False
    mPhase = ""
    If operationCommitted Then
        mLastOutcome = SLC_U("D655 C778 0020 C790 B8CC 0020 C0DD C131 0020 C644 B8CC 0020 00B7 0020 0045 0078 0063 0065 006C 0020 C0C1 D0DC 0020 BCF5 C6D0 0020 D655 C778 0020 D544 C694")
    ElseIf errNo = 18 Or errNo = ERR_CANCEL Then
        mLastOutcome = SLC_U("CDE8 C18C 0020 C644 B8CC 0020 00B7 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 C720 C9C0")
    Else
        mLastOutcome = SLC_U("D655 C778 0020 C790 B8CC 0020 C791 C131 0020 C2E4 D328 0020 00B7 0020 CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 C720 C9C0")
    End If
    Application.EnableCancelKey = oldCancel
    RefreshUI
    On Error GoTo 0
    If raiseTestError Then Err.Raise errNo, "PreviewSnapshot", errText
    MsgBox mLastOutcome & vbCrLf & PendingSummary() & vbCrLf & errText, vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
End Sub

Public Sub SLC_Replace()
    Dim completed As Workbook
    ' Transactional: a failed/cancelled replacement preserves the previous A.
    RunSelection True, completed
End Sub

Public Sub SLC_Run()
    Dim completed As Workbook
    RunSelection False, completed
End Sub

Private Sub RunSelection(ByVal replaceOnly As Boolean, ByRef completedResult As Workbook, _
                         Optional ByVal raiseTestError As Boolean = False)
    Dim selected As Range, parts As Collection, exclusions As Collection
    Dim current As CSLCList, previousPending As CSLCList
    Dim oldCancel As XlEnableCancelKey
    Dim errNo As Long, errText As String
    Dim setState As Boolean, combining As Boolean, oldInteractive As Boolean
    Dim operationCommitted As Boolean
    Dim keepFirst As Boolean

    If mBusy Then Exit Sub
    On Error GoTo Failed
    LoadSettings
    keepFirst = mKeepFirst
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
    mLastOutcome = ""
    Set previousPending = mPending
    mCancelled = False
    mStarted = Timer
    oldCancel = Application.EnableCancelKey
    oldInteractive = Application.Interactive
    Application.EnableCancelKey = xlErrorHandler
    setState = True
    combining = Not (mPending Is Nothing)
    If replaceOnly Then combining = False
    SetPhase SLC_U("C120 D0DD 0020 BC94 C704 0020 D655 C778 0020 C911")
    Set parts = PrepareParts(selected, True, combining)
    If parts Is Nothing Then
        mLastOutcome = SLC_U("C791 C5C5 C744 0020 C2DC C791 D558 C9C0 0020 C54A C558 C2B5 B2C8 B2E4 002E 0020") & PendingLabel()
        GoTo Finished
    End If
    mStarted = Timer
    ' Keep keyboard input available so EnableCancelKey can handle Esc.
    ' The selected Range is already captured and mBusy rejects re-entry.
    Set exclusions = MetadataRects(selected.Worksheet)
    SetPhase SLC_U("C120 D0DD D55C 0020 AC12 0020 C77D B294 0020 C911")
    Set current = ReadParts(selected, parts, exclusions)
    ' A cancellation queued during the last partial chunk must precede commit.
    Checkpoint
    If current.Total = 0 Then
        mLastOutcome = SLC_U("BE44 AD50 D560 0020 AC12 0020 C5C6 C74C 0020 00B7 0020 C774 C804 0020 CCAB 0020 BAA9 B85D 0020 C720 C9C0")
        ReleaseStatus
        If Not raiseTestError Then MsgBox SLC_U("C120 D0DD D55C 0020 C140 C5D0 0020 BE44 AD50 D560 0020 AC12 C774 0020 C5C6 C2B5 B2C8 B2E4 002E") & vbCrLf & NoValuesSummary(current) & vbCrLf & _
               SLC_U("C228 AE34 0020 C140 ACFC 0020 D544 D130 B85C 0020 AC00 B824 C9C4 0020 C140 C740 0020 C77D C9C0 0020 C54A C2B5 B2C8 B2E4 002E") & vbCrLf & PendingSummary(), _
               vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        GoTo Finished
    End If
    If Not combining Then
        SetPhase SLC_U("CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 AE30 0020 B9C8 BB34 B9AC 0020 C911")
        Checkpoint
        ' No event dispatch or dialogs between the final check and commit.
        Application.EnableCancelKey = xlDisabled
        Set mPending = current
        operationCommitted = True
        mLastOutcome = SLC_U("CCAB 0020 BAA9 B85D 0020 B2F4 AE30 0020 C644 B8CC 0020 00B7 0020 005B B2F4 C740 0020 BAA9 B85D 0020 D655 C778 005D C5D0 C11C 0020 CD9C CC98 C640 0020 C81C C678 0020 C140 C744 0020 D655 C778 D558 C138 C694 002E")
    Else
        Set completedResult = ShowComparison(mPending, current)
        ' Output completion or the last equality checkpoint precedes this commit.
        Application.EnableCancelKey = xlDisabled
        If Not keepFirst Then Set mPending = Nothing
        operationCommitted = True
        If keepFirst Then
            mLastOutcome = SLC_U("BE44 AD50 0020 C644 B8CC 0020 00B7 0020 AC19 C740 0020 CCAB 0020 BAA9 B85D C73C B85C 0020 C774 C5B4 C11C 0020 BE44 AD50 D560 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E")
        Else
            mLastOutcome = SLC_U("BE44 AD50 0020 C644 B8CC 0020 00B7 0020 CCAB 0020 BAA9 B85D C744 0020 BE44 C6E0 C2B5 B2C8 B2E4 002E 0020 C0C8 0020 CCAB 0020 BAA9 B85D C744 0020 B2F4 C73C C138 C694 002E")
        End If
        ReleaseStatus
        If completedResult Is Nothing And Not raiseTestError Then
            MsgBox EqualityMessage(previousPending, current), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
        End If
    End If
Finished:
    ReleaseStatus
    mPhase = ""
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
    mPhase = ""
    If raiseTestError Then Err.Raise errNo, "RunSelection", errText
    If operationCommitted Then
        mLastOutcome = SLC_U("C791 C5C5 0020 C644 B8CC 0020 00B7 0020 0045 0078 0063 0065 006C 0020 C0C1 D0DC 0020 BCF5 C6D0 0020 D655 C778 0020 D544 C694")
        RefreshUI
        MsgBox SLC_U("C791 C5C5 0020 ACB0 ACFC B294 0020 B9CC B4E4 C5B4 C84C C9C0 B9CC 0020 0045 0078 0063 0065 006C 0020 C0C1 D0DC B97C 0020 BCF5 C6D0 D558 B294 0020 C911 0020 BB38 C81C AC00 0020 C0DD ACBC C2B5 B2C8 B2E4 002E") & vbCrLf & _
               SLC_U("ACB0 ACFC B97C 0020 D655 C778 D558 ACE0 0020 D544 C694 D55C 0020 D30C C77C C744 0020 C800 C7A5 D55C 0020 B4A4 0020 0045 0078 0063 0065 006C C744 0020 B2E4 C2DC 0020 C2E4 D589 D574 0020 C8FC C138 C694 002E") & vbCrLf & _
               SLC_U("C624 B958 0020 CF54 B4DC 003A 0020") & CStr(errNo), vbExclamation, SLC_U("BA85 B2E8 0020 BE44 AD50")
    ElseIf errNo = 18 Or errNo = ERR_CANCEL Then
        mLastOutcome = SLC_U("CDE8 C18C 0020 C644 B8CC 0020 00B7 0020 C774 C804 0020 CCAB 0020 BAA9 B85D 0020 C720 C9C0")
        RefreshUI
        MsgBox SLC_U("C791 C5C5 C744 0020 CDE8 C18C D588 C2B5 B2C8 B2E4 002E") & vbCrLf & PendingSummary() & vbCrLf & _
               SLC_U("C774 BC88 0020 C791 C5C5 C758 0020 BBF8 C644 C131 0020 ACB0 ACFC B294 0020 C815 B9AC D588 C2B5 B2C8 B2E4 002E 0020 C6D0 BCF8 C740 0020 BC14 B00C C9C0 0020 C54A C558 C2B5 B2C8 B2E4 002E"), vbInformation, SLC_U("BA85 B2E8 0020 BE44 AD50")
    Else
        mLastOutcome = SLC_U("C791 C5C5 0020 C2E4 D328 0020 00B7 0020 C774 C804 0020 CCAB 0020 BAA9 B85D 0020 C720 C9C0")
        RefreshUI
        MsgBox errText & vbCrLf & vbCrLf & PendingSummary() & vbCrLf & _
               SLC_U("C6D0 BCF8 0020 B0B4 C6A9 C740 0020 BC14 B00C C9C0 0020 C54A C558 C2B5 B2C8 B2E4 002E") & vbCrLf & SLC_U("C624 B958 0020 CF54 B4DC 003A 0020") & CStr(errNo), vbExclamation, SLC_U("BA85 B2E8 0020 BE44 AD50")
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
    result.DisplaySource = DisplaySourceLabel(sel)
    result.CapturedAt = Now
    LoadSettings
    If mPending Is Nothing Then
        result.CompareFullEmail = mFullEmail
        result.IgnoreCase = mIgnoreCase
    Else
        result.CompareFullEmail = mPending.CompareFullEmail
        result.IgnoreCase = mPending.IgnoreCase
    End If
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
                        SetStatus SLC_U("BA85 B2E8 0020 BE44 AD50 003A 0020 C77D B294 0020 C911 0020 00B7 0020") & Format$(result.VisibleCellCount, "#,##0") & SLC_U("C140 0020 D655 C778 0020 002F 0020") & _
                            Format$(result.Total, "#,##0") & SLC_U("AC1C 0020 D56D BAA9 0020 B2F4 C74C")
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
        list.AddError address, ErrorDescription(v)
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
    key = SLC_Normalize(v, list.CompareFullEmail, list.IgnoreCase)
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
    list.AddOccurrence key, raw, address
End Sub

Private Function NoValuesSummary(ByVal list As CSLCList) As String
    Dim sample As Variant, shown As Long, result As String
    result = SLC_U("C81C C678 003A 0020 BE48 CE78 0020") & list.BlankCount & SLC_U("AC1C 0020 002F 0020 C624 B958 0020") & list.ErrorCount & _
        SLC_U("AC1C 0020 002F 0020 C81C BAA9 00B7 D569 ACC4 0020") & list.MetadataCount & SLC_U("AC1C")
    For Each sample In list.ErrorSamples
        shown = shown + 1
        If shown > 5 Then Exit For
        result = result & vbCrLf & CStr(sample(0)) & ": " & CStr(sample(1))
    Next sample
    If list.ErrorCount > 5 Then result = result & vbCrLf & SLC_U("C624 B958 0020 C704 CE58 B294 0020 CC98 C74C 0020 0035 AC1C B9CC 0020 D45C C2DC D588 C2B5 B2C8 B2E4 002E")
    NoValuesSummary = result
End Function

Private Function ErrorDescription(ByVal value As Variant) As String
    ' Convert the stored error variant locally, without reading the cell again.
    Select Case Right$(CStr(value), 4)
        Case "2000": ErrorDescription = "#NULL!"
        Case "2007": ErrorDescription = "#DIV/0!"
        Case "2015": ErrorDescription = "#VALUE!"
        Case "2023": ErrorDescription = "#REF!"
        Case "2029": ErrorDescription = "#NAME?"
        Case "2036": ErrorDescription = "#NUM!"
        Case "2042": ErrorDescription = "#N/A"
        Case "2043": ErrorDescription = "#GETTING_DATA"
        Case "2045": ErrorDescription = "#SPILL!"
        Case "2050": ErrorDescription = "#CALC!"
        Case Else: ErrorDescription = CStr(value)
    End Select
End Function

Private Function DisplaySourceLabel(ByVal rng As Range) As String
    Dim label As String
    label = rng.Worksheet.Parent.Name & " / " & rng.Worksheet.Name & "!" & rng.Areas(1).Address(False, False)
    If rng.Areas.Count > 1 Then label = label & SLC_U("0020 C678 0020") & CStr(rng.Areas.Count - 1) & SLC_U("AC1C 0020 C601 C5ED")
    If Len(label) > 100 Then label = Left$(label, 97) & "..."
    DisplaySourceLabel = label
End Function

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
        Err.Raise ERR_TIME, , SLC_U("C791 C5C5 0020 C2DC AC04 C774 0020 AE38 C5B4 C838 0020 C911 B2E8 D588 C2B5 B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("B450 0020 BAA9 B85D C744 0020 D589 0020 BC88 D638 B85C 0020 B098 B204 BA74 0020 C798 BABB B41C 0020 CC28 C774 AC00 0020 B098 C62C 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("C804 CCB4 0020 BE44 AD50 AC00 0020 D544 C694 D558 BA74 0020 AC12 C744 0020 BE60 B728 B9AC C9C0 0020 C54A B294 0020 BE44 AD50 0020 BC29 BC95 C744 0020 C0AC C6A9 D574 0020 C8FC C138 C694 002E")
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
    ' Preserve the exact Variant, including an external literal string "FALSE".
    PreviousStatus = Application.StatusBar
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
    mLastStatus = ""
    On Error GoTo 0
End Sub

Private Function CountOf(ByVal list As CSLCList, ByVal key As String) As Long
    If list.Counts.Exists(key) Then CountOf = CLng(list.Counts(key))
End Function

Private Function DictText(ByVal dict As Object, ByVal key As String) As String
    If dict.Exists(key) Then DictText = CStr(dict(key))
End Function

Private Function ShowComparison(ByVal a As CSLCList, ByVal b As CSLCList) As Workbook
    Dim k As Variant, ca As Long, cb As Long, matched As Long, tick As Long
    SetPhase SLC_U("AC12 ACFC 0020 AC1C C218 0020 BE44 AD50 0020 C911")
    ' One pass is sufficient: total minus matched gives each list's excess.
    ' Do not partition by row or allocate a second union of all comparison keys.
    For Each k In a.Counts.Keys
        ca = CLng(a.Counts(CStr(k)))
        cb = CountOf(b, CStr(k))
        If ca < cb Then matched = matched + ca Else matched = matched + cb
        tick = tick + 1
        If tick Mod CANCEL_POLL_ITEMS = 0 Then PollCancellation
        If tick Mod 1024 = 0 Then
            SetStatus SLC_U("BA85 B2E8 0020 BE44 AD50 003A 0020 AC12 ACFC 0020 AC1C C218 0020 BE44 AD50 0020 C911 0020 00B7 0020") & Format$(tick, "#,##0") & SLC_U("C885 B958 0020 D655 C778")
            Checkpoint
        End If
    Next k
    Checkpoint
    If matched = a.Total And matched = b.Total Then Exit Function
    SetPhase SLC_U("ACB0 ACFC 0020 C791 C131 0020 C911")
    If mTestOutputFailure Then Err.Raise ERR_DATA, , "Injected result creation failure"
    Set ShowComparison = SLC_WriteUsabilityResults(a, b, matched, a.Total - matched, b.Total - matched)
End Function

Private Function SettingsSection() As String
    SettingsSection = SETTINGS_SECTION
    If Len(mSettingsTestSection) > 0 Then SettingsSection = mSettingsTestSection
End Function

Private Function EncodeSettings(ByVal fullEmail As Boolean, ByVal ignoreCase As Boolean, ByVal keepFirst As Boolean) As String
    EncodeSettings = "1|" & CStr(Abs(CInt(fullEmail))) & "|" & CStr(Abs(CInt(ignoreCase))) & "|" & CStr(Abs(CInt(keepFirst)))
End Function

Private Function DecodeSettings(ByVal value As String, ByRef fullEmail As Boolean, _
                                ByRef ignoreCase As Boolean, ByRef keepFirst As Boolean) As Boolean
    Dim parts As Variant, i As Long
    fullEmail = False: ignoreCase = False: keepFirst = False
    parts = Split(value, "|")
    If UBound(parts) <> 3 Then Exit Function
    If parts(0) <> "1" Then Exit Function
    For i = 1 To 3
        If parts(i) <> "0" And parts(i) <> "1" Then Exit Function
    Next i
    fullEmail = (parts(1) = "1")
    ignoreCase = (parts(2) = "1")
    keepFirst = (parts(3) = "1")
    DecodeSettings = True
End Function

Private Sub LoadSettings()
    Dim stored As String
    If mSettingsLoaded Then Exit Sub
    mFullEmail = False: mIgnoreCase = False: mKeepFirst = False
    ' Read failure or an invalid value uses defaults without overwriting the stored value.
    On Error GoTo Defaults
    stored = GetSetting(SETTINGS_APP, SettingsSection(), SETTINGS_KEY, "")
    DecodeSettings stored, mFullEmail, mIgnoreCase, mKeepFirst
Defaults:
    mSettingsLoaded = True
End Sub

Private Function ApplySettings(ByVal fullEmail As Boolean, ByVal ignoreCase As Boolean, _
                               ByVal keepFirst As Boolean, ByRef reason As String) As Boolean
    LoadSettings
    If mBusy Then
        reason = SLC_U("C791 C5C5 C774 0020 B05D B09C 0020 B4A4 0020 C124 C815 C744 0020 BC14 AFD4 0020 C8FC C138 C694 002E")
        Exit Function
    End If
    If Not mPending Is Nothing Then
        If fullEmail <> mPending.CompareFullEmail Or ignoreCase <> mPending.IgnoreCase Then
            reason = SLC_U("BE44 AD50 0020 AE30 C900 C744 0020 BC14 AFB8 B824 BA74 0020 CCAB 0020 BAA9 B85D C744 0020 BE44 C6CC 0020 C8FC C138 C694 002E")
            Exit Function
        End If
    End If
    On Error GoTo Failed
    ' One versioned registry value commits all three flags together, never list data.
    SaveSetting SETTINGS_APP, SettingsSection(), SETTINGS_KEY, EncodeSettings(fullEmail, ignoreCase, keepFirst)
    mFullEmail = fullEmail: mIgnoreCase = ignoreCase: mKeepFirst = keepFirst
    ApplySettings = True
    RefreshUI
    Exit Function
Failed:
    reason = SLC_U("C124 C815 C744 0020 C800 C7A5 D558 C9C0 0020 BABB D588 C2B5 B2C8 B2E4 002E 0020 AE30 C874 0020 C124 C815 C740 0020 C720 C9C0 B429 B2C8 B2E4 002E")
    If Len(mSettingsTestSection) > 0 Then reason = reason & " / " & CStr(Err.Number) & " / " & Err.Description
End Function

Private Sub ChangeSettings(ByVal fullEmail As Boolean, ByVal ignoreCase As Boolean, ByVal keepFirst As Boolean)
    Dim reason As String
    If Not ApplySettings(fullEmail, ignoreCase, keepFirst, reason) Then
        If Len(mSettingsTestSection) > 0 Then Err.Raise ERR_DATA, "R11 setting action", reason
        MsgBox reason, vbInformation, SLC_U("BE44 AD50 0020 C124 C815")
    End If
End Sub

Public Sub SLC_ToggleFullEmail()
    LoadSettings
    ChangeSettings Not mFullEmail, mIgnoreCase, mKeepFirst
End Sub

Public Sub SLC_ToggleIgnoreCase()
    LoadSettings
    ChangeSettings mFullEmail, Not mIgnoreCase, mKeepFirst
End Sub

Public Sub SLC_ToggleKeepFirst()
    LoadSettings
    ChangeSettings mFullEmail, mIgnoreCase, Not mKeepFirst
End Sub

Public Sub SLC_ResetSettings()
    If mBusy Then Exit Sub
    If Not mPending Is Nothing Then
        MsgBox SLC_U("AE30 BCF8 AC12 C73C B85C 0020 B418 B3CC B9AC B824 BA74 0020 CCAB 0020 BAA9 B85D C744 0020 BE44 C6CC 0020 C8FC C138 C694 002E"), vbInformation, SLC_U("BE44 AD50 0020 C124 C815")
        Exit Sub
    End If
    ChangeSettings False, False, False
End Sub

Public Sub SLC_ResetSettingsClick(ByVal control As Office.IRibbonControl)
    SLC_ResetSettings
End Sub

Public Sub SLC_SettingPressed(ByVal control As Office.IRibbonControl, ByRef returnedVal)
    LoadSettings
    Select Case control.Tag
        Case "fullEmail": returnedVal = mFullEmail
        Case "ignoreCase": returnedVal = mIgnoreCase
        Case "keepFirst": returnedVal = mKeepFirst
    End Select
End Sub

Public Sub SLC_SettingClick(ByVal control As Office.IRibbonControl, ByVal pressed As Boolean)
    LoadSettings
    Select Case control.Tag
        Case "fullEmail": ChangeSettings pressed, mIgnoreCase, mKeepFirst
        Case "ignoreCase": ChangeSettings mFullEmail, pressed, mKeepFirst
        Case "keepFirst": ChangeSettings mFullEmail, mIgnoreCase, pressed
    End Select
End Sub

Private Function XmlBoolean(ByVal value As Boolean) As String
    If value Then XmlBoolean = "true" Else XmlBoolean = "false"
End Function

Private Function SettingsCheck(ByVal prefix As String, ByVal tag As String, ByVal label As String, ByVal enabled As Boolean) As String
    SettingsCheck = "<checkBox id=""" & prefix & tag & """ tag=""" & tag & """ label=""" & XmlLabel(label) & _
        """ enabled=""" & XmlBoolean(enabled) & """ getPressed=""SLC_SettingPressed"" onAction=""SLC_SettingClick""/>"
End Function

Private Function SettingsMenuXml(ByVal prefix As String) As String
    Dim xml As String, rulesEnabled As Boolean
    rulesEnabled = Not mBusy And (mPending Is Nothing)
    xml = "<menu id=""" & prefix & SLC_U("0053 0065 0074 0074 0069 006E 0067 0073 0022 0020 006C 0061 0062 0065 006C 003D 0022 BE44 AD50 0020 C124 C815 0022 003E")
    xml = xml & SettingsCheck(prefix, "fullEmail", SLC_U("BA54 C77C 0020 C804 CCB4 0020 C8FC C18C 0020 BE44 AD50 0020 0028 0040 0020 B4A4 0020 D3EC D568 0029"), rulesEnabled)
    xml = xml & SettingsCheck(prefix, "ignoreCase", SLC_U("B300 C18C BB38 C790 0020 BB34 C2DC"), rulesEnabled)
    xml = xml & SettingsCheck(prefix, "keepFirst", SLC_U("BE44 AD50 0020 D6C4 0020 CCAB 0020 BAA9 B85D 0020 C720 C9C0"), Not mBusy)
    xml = xml & "<button id=""" & prefix & SLC_U("0052 0065 0073 0065 0074 0053 0065 0074 0074 0069 006E 0067 0073 0022 0020 006C 0061 0062 0065 006C 003D 0022 AE30 BCF8 AC12 C73C B85C 0020 B418 B3CC B9AC AE30 0022 0020 0065 006E 0061 0062 006C 0065 0064 003D 0022") & _
        XmlBoolean(rulesEnabled) & """ onAction=""SLC_ResetSettingsClick""/>"
    If mPending Is Nothing Then
        xml = xml & MenuLabel(prefix & "SettingsNote", SLC_U("C124 C815 C740 0020 B2E4 C74C 0020 0045 0078 0063 0065 006C 0020 C2E4 D589 C5D0 B3C4 0020 AE30 C5B5 D569 B2C8 B2E4 002E"))
    Else
        xml = xml & MenuLabel(prefix & "SettingsNote", SLC_U("BE44 AD50 0020 AE30 C900 C744 0020 BC14 AFB8 B824 BA74 0020 CCAB 0020 BAA9 B85D C744 0020 BE44 C6CC 0020 C8FC C138 C694 002E"))
    End If
    SettingsMenuXml = xml & "</menu>"
End Function

Private Sub RefreshSettingsControls(ByVal control As CommandBarControl)
    Dim popup As CommandBarPopup, button As CommandBarButton, checked As Boolean
    Set popup = control
    For Each button In popup.Controls
        checked = False
        button.Enabled = Not mBusy
        Select Case button.Tag
            Case UI_TAG & ".fullEmail"
                checked = mFullEmail
                button.Enabled = Not mBusy And (mPending Is Nothing)
            Case UI_TAG & ".ignoreCase"
                checked = mIgnoreCase
                button.Enabled = Not mBusy And (mPending Is Nothing)
            Case UI_TAG & ".keepFirst"
                checked = mKeepFirst
            Case UI_TAG & ".resetSettings"
                button.Enabled = Not mBusy And (mPending Is Nothing)
            Case UI_TAG & ".settingsNote"
                button.Visible = True
                button.Enabled = False
                If mPending Is Nothing Then
                    button.Caption = SLC_U("C124 C815 C740 0020 B2E4 C74C 0020 0045 0078 0063 0065 006C 0020 C2E4 D589 C5D0 B3C4 0020 AE30 C5B5 D569 B2C8 B2E4 002E")
                Else
                    button.Caption = SLC_U("BE44 AD50 0020 AE30 C900 C744 0020 BC14 AFB8 B824 BA74 0020 CCAB 0020 BAA9 B85D C744 0020 BE44 C6CC 0020 C8FC C138 C694 002E")
                End If
        End Select
        If checked Then button.State = msoButtonDown Else button.State = msoButtonUp
    Next button
End Sub

Public Function SLC_RulesText(ByVal fullEmail As Boolean, ByVal ignoreCase As Boolean) As String
    If fullEmail Then SLC_RulesText = SLC_U("BA54 C77C 0020 C804 CCB4 0020 C8FC C18C 0020 BE44 AD50") Else SLC_RulesText = SLC_U("BA54 C77C 0020 0040 0020 C55E BD80 BD84 B9CC 0020 BE44 AD50")
    If ignoreCase Then SLC_RulesText = SLC_RulesText & SLC_U("0020 002F 0020 B300 C18C BB38 C790 0020 BB34 C2DC") Else SLC_RulesText = SLC_RulesText & SLC_U("0020 002F 0020 B300 C18C BB38 C790 0020 AD6C BD84")
End Function

Public Function SLC_CompletionPolicyText() As String
    If mKeepFirst Then
        SLC_CompletionPolicyText = SLC_U("BE44 AD50 0020 C131 ACF5 0020 D6C4 0020 CCAB 0020 BAA9 B85D 0020 C720 C9C0")
    Else
        SLC_CompletionPolicyText = SLC_U("BE44 AD50 0020 C131 ACF5 0020 D6C4 0020 CCAB 0020 BAA9 B85D 0020 BE44 C6B0 AE30")
    End If
End Function

Private Function EqualityMessage(ByVal a As CSLCList, ByVal b As CSLCList) As String
    If a.ErrorCount + b.ErrorCount > 0 Then
        EqualityMessage = SLC_U("C624 B958 B97C 0020 C81C C678 D55C 0020 BE44 AD50 0020 B300 C0C1 C774 0020 AC19 C2B5 B2C8 B2E4 002E") & vbCrLf & _
            SLC_U("C81C C678 D55C 0020 C624 B958 003A 0020 CCAB 0020 BAA9 B85D 0020") & CStr(a.ErrorCount) & SLC_U("AC1C 0020 002F 0020 B450 0020 BC88 C9F8 0020 BAA9 B85D 0020") & CStr(b.ErrorCount) & SLC_U("AC1C")
    Else
        EqualityMessage = SLC_U("C120 D0DD D55C 0020 BE44 AD50 0020 AE30 C900 C73C B85C 0020 B450 0020 BAA9 B85D C758 0020 AC12 ACFC 0020 AC1C C218 AC00 0020 AC19 C2B5 B2C8 B2E4 002E")
    End If
    EqualityMessage = EqualityMessage & vbCrLf & SLC_U("ACB0 ACFC 0020 D30C C77C C740 0020 B9CC B4E4 C9C0 0020 C54A C558 C2B5 B2C8 B2E4 002E")
End Function

Public Sub SLC_About()
    If mBusy Then Exit Sub
    MsgBox SLC_U("0045 0078 0063 0065 006C 0020 BA85 B2E8 0020 BE44 AD50 0020") & SLC_ReleaseVersion() & vbCrLf & vbCrLf & _
        SLC_U("0031 002E 0020 CCAB 0020 BAA9 B85D C758 0020 C140 C744 0020 C120 D0DD D558 ACE0 0020 005B CCAB 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 AE30 005D B97C 0020 B204 B974 C138 C694 002E") & vbCrLf & _
        SLC_U("0032 002E 0020 CD9C CC98 B97C 0020 D655 C778 D558 C138 C694 002E 0020 005B B2F4 C740 0020 BAA9 B85D 0020 D655 C778 005D C5D0 C11C 0020 D45C BCF8 ACFC 0020 C81C C678 0020 C140 C744 0020 BCFC 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("0033 002E 0020 B450 0020 BC88 C9F8 0020 BAA9 B85D C744 0020 C120 D0DD D558 ACE0 0020 005B B450 0020 BC88 C9F8 0020 BAA9 B85D 0020 B2F4 C544 0020 BE44 AD50 005D B97C 0020 B204 B974 C138 C694 002E") & vbCrLf & vbCrLf & _
        SLC_U("C120 D0DD D55C 0020 C140 0020 C804 CCB4 AC00 0020 BAA9 B85D 0020 D558 B098 C785 B2C8 B2E4 002E 0020 C21C C11C C640 0020 BC29 D5A5 C740 0020 BB34 C2DC D558 ACE0 0020 AC12 BCC4 0020 AC1C C218 B97C 0020 BE44 AD50 D569 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("005B BE44 AD50 0020 C124 C815 005D C5D0 C11C 0020 BA54 C77C 0020 C804 CCB4 0020 C8FC C18C 00B7 B300 C18C BB38 C790 0020 BB34 C2DC 00B7 CCAB 0020 BAA9 B85D 0020 C720 C9C0 B97C 0020 C120 D0DD D558 C138 C694 002E") & vbCrLf & _
        SLC_U("AE30 BCF8 AC12 C740 0020 0040 0020 C55E BD80 BD84 0020 BE44 AD50 002C 0020 B300 C18C BB38 C790 0020 AD6C BD84 002C 0020 BE44 AD50 0020 D6C4 0020 CCAB 0020 BAA9 B85D 0020 BE44 C6B0 AE30 C785 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("AC19 C73C BA74 0020 ACB0 ACFC 0020 D30C C77C C744 0020 B9CC B4E4 C9C0 0020 C54A C2B5 B2C8 B2E4 002E 0020 CC28 C774 AC00 0020 C788 C73C BA74 0020 ACB0 ACFC B97C 0020 C9C1 C811 0020 C800 C7A5 D558 C138 C694 002E") & vbCrLf & _
        SLC_U("C124 C815 C740 0020 C790 B3D9 C73C B85C 0020 AE30 C5B5 D569 B2C8 B2E4 002E 0020 005B AE30 BCF8 AC12 C73C B85C 0020 B418 B3CC B9AC AE30 005D B85C 0020 CD08 AE30 D654 D560 0020 C218 0020 C788 C2B5 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("B2F4 C740 0020 B4A4 0020 C6D0 BCF8 C744 0020 ACE0 CCD0 B3C4 0020 C774 BBF8 0020 B2F4 AE34 0020 AC12 C740 0020 BC14 B00C C9C0 0020 C54A C2B5 B2C8 B2E4 002E 0020 0045 0078 0063 0065 006C 0020 C885 B8CC 0020 C2DC 0020 C0AC B77C C9D1 B2C8 B2E4 002E") & vbCrLf & _
        SLC_U("005B C791 C5C5 0020 CDE8 C18C 005D 0020 B610 B294 0020 0045 0073 0063 B85C 0020 CDE8 C18C B97C 0020 C694 CCAD D55C 0020 B4A4 0020 C644 B8CC 0020 C548 B0B4 B97C 0020 D655 C778 D558 C138 C694 002E") & vbCrLf & _
        SLC_U("0031 0030 0030 002C 0030 0030 0030 C140 C740 0020 C785 B825 0020 D55C B3C4 C774 BA70 0020 C644 B8CC 0020 BCF4 C7A5 B7C9 C774 0020 C544 B2D9 B2C8 B2E4 002E 0020 D589 0020 BC88 D638 B85C 0020 C784 C758 0020 BD84 D560 D558 C9C0 0020 B9C8 C138 C694 002E"), _
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
    Dim savedPending As CSLCList, savedLoaded As Boolean, savedFull As Boolean, savedIgnore As Boolean, savedKeep As Boolean
    Set savedPending = mPending
    savedLoaded = mSettingsLoaded: savedFull = mFullEmail: savedIgnore = mIgnoreCase: savedKeep = mKeepFirst
    Set mPending = Nothing
    mSettingsLoaded = True: mFullEmail = False: mIgnoreCase = False: mKeepFirst = False
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
    ws.Range("H5").Value2 = "USER@b.com"
    ws.Range("H6").Value2 = "123"
    Set a = TestSnapshot(ws.Range("B2:E2"))
    Set b = TestSnapshot(ws.Range("H3:H6"))
    AssertSame a, b, "horizontal -> vertical"
    AssertSame b, a, "vertical -> horizontal"
    n = n + 2
    arr(1, 1) = "00123": arr(1, 2) = SLC_U("D64D AE38 B3D9")
    arr(2, 1) = "123": arr(2, 2) = "USER"
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
    Set mPending = savedPending
    mSettingsLoaded = savedLoaded: mFullEmail = savedFull: mIgnoreCase = savedIgnore: mKeepFirst = savedKeep
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
    Set mPending = savedPending
    mSettingsLoaded = savedLoaded: mFullEmail = savedFull: mIgnoreCase = savedIgnore: mKeepFirst = savedKeep
    If Not oldBook Is Nothing Then oldBook.Activate
    On Error GoTo 0
    Err.Raise errNo, "SLC_TestAll", errText
End Function

Public Function SLC_UsabilityTests() As String
    ' Fast essential R11 checks: synthetic documents; a unique, removed settings key.
    Dim source As Workbook, result As Workbook, preview As Workbook, firstResult As Workbook
    Dim oldBook As Workbook, ws As Worksheet, oldPending As CSLCList, captured As CSLCList
    Dim oldCancel As XlEnableCancelKey, oldEvents As Boolean, oldStatus As Variant
    Dim oldOutcome As String, oldPhase As String, oldCancelled As Boolean
    Dim savedFull As Boolean, savedIgnore As Boolean, savedKeep As Boolean, savedLoaded As Boolean
    Dim reportResult As String, n As Long, errNo As Long, errText As String, reason As String
    Dim i As Long, books As Long, full As Boolean, ignore As Boolean, scope As String
    Dim popup As CommandBarPopup, menuDocument As Object, kind As Variant, testStage As String
    Dim savedTestTrace As Variant
    If mBusy Then SLC_UsabilityTests = "FAIL: an active comparison prevents testing": Exit Function
    If Len(mSettingsTestSection) > 0 Then SLC_UsabilityTests = "FAIL: settings test already active": Exit Function
    On Error GoTo InitialStateFailed
    savedTestTrace = ThisWorkbook.Worksheets(1).Range("A1").Formula
    TraceR11 "initial application state"
    Set oldBook = Application.ActiveWorkbook
    Set oldPending = mPending
    oldCancel = Application.EnableCancelKey
    oldEvents = Application.EnableEvents
    oldStatus = Application.StatusBar
    oldOutcome = mLastOutcome: oldPhase = mPhase: oldCancelled = mCancelled
    savedFull = mFullEmail: savedIgnore = mIgnoreCase: savedKeep = mKeepFirst: savedLoaded = mSettingsLoaded
    On Error GoTo Failed
    testStage = "isolated settings defaults"
    TraceR11 testStage
    scope = "R11Test-" & CStr(Application.Hwnd) & "-" & Format$(Now, "yyyymmddhhnnss")
    If Len(GetSetting(SETTINGS_APP, scope, SETTINGS_KEY, "")) > 0 Then Err.Raise ERR_DATA, , "Test settings key already exists"
    mSettingsTestSection = scope
    mSettingsLoaded = False
    Set mPending = Nothing
    LoadSettings
    Call AssertR11(Not mFullEmail And Not mIgnoreCase And Not mKeepFirst, "Initial defaults")
    n = n + 1
    testStage = "settings menu binding and shared action"
    TraceR11 testStage
    Application.EnableEvents = False
    Set source = Application.Workbooks.Add(xlWBATWorksheet)
    Set ws = source.Worksheets(1)
    ws.Name = "R11 & source"
    TraceR11 "attach toolbar"
    SLC_AttachUI
    TraceR11 "verify toolbar initialization"
    Call AssertR11(SLC_UiReady(), "Toolbar initialization with an active workbook: " & mUiFailure)
    Set popup = Application.CommandBars(BAR_NAME).FindControl(Type:=msoControlPopup, Tag:=UI_TAG & ".settings")
    Call AssertR11(Not popup Is Nothing, "Toolbar settings menu exists")
    ' Check the binding and invoke its shared action directly. Dispatching a
    ' CommandBar action from inside an Application.Run macro can wait on UI;
    ' physical menu interaction belongs to the separate user validation.
    Call AssertR11(IsOwnMacroBinding(popup.Controls(1).OnAction, "SLC_ToggleFullEmail"), _
        "Toolbar setting binding: " & popup.Controls(1).OnAction)
    TraceR11 "invoke email setting action"
    SLC_ToggleFullEmail
    TraceR11 "verify email setting action"
    Call AssertR11(mFullEmail, "Shared setting action toggles email scope")
    Call AssertR11(ApplySettings(False, False, False, reason), "Restore defaults after menu action")
    Set menuDocument = CreateObject("MSXML2.DOMDocument.6.0")
    menuDocument.setProperty "SelectionNamespaces", "xmlns:slc='http://schemas.microsoft.com/office/2009/07/customui'"
    TraceR11 "validate context menu XML"
    For Each kind In Array("Cell", "Row", "Column", "Table", "CellLayout", "RowLayout", "ColumnLayout", "TableLayout")
        Call AssertR11(menuDocument.LoadXML(SLC_MenuXml(CStr(kind))), "Generated context XML parses")
        Call AssertR11(menuDocument.selectNodes("//slc:checkBox").Length = 3, "Every context has three shared settings: " & CStr(kind))
    Next kind
    n = n + 1
    mStarted = Timer: mCancelled = False
    testStage = "report output and rollback"
    TraceR11 testStage
    reportResult = SLC_ReportTests()
    ws.Range("A1:D4").NumberFormat = "@"
    ws.Range("A1").Value2 = "User@a.test"
    ws.Range("B1").Value2 = "User@b.test"
    For i = 0 To 3
        testStage = "comparison rules " & CStr(i)
    TraceR11 testStage
        full = ((i And 1) <> 0): ignore = ((i And 2) <> 0)
        Call AssertR11(ApplySettings(full, ignore, False, reason), "Apply each rule combination")
        mSettingsLoaded = False: mFullEmail = Not full: mIgnoreCase = Not ignore: mKeepFirst = True
        LoadSettings
        Call AssertR11(mFullEmail = full And mIgnoreCase = ignore And Not mKeepFirst, "Persisted settings reload")
        Call AssertR11((SLC_Normalize("User@a.test", full, ignore) = SLC_Normalize("User@b.test", full, ignore)) = (Not full), "Email range matrix")
        Call AssertR11((SLC_Normalize("User@a.test", full, ignore) = SLC_Normalize("user@a.test", full, ignore)) = ignore, "Case matrix")
        ws.Activate: ws.Range("A1").Select
        RunSelection True, result, True
        Call AssertR11(mPending.CompareFullEmail = full And mPending.IgnoreCase = ignore, "Snapshot carries rules")
        books = Application.Workbooks.Count
        ws.Range("B1").Select
        RunSelection False, result, True
        If full Then
            Call AssertR11(Not result Is Nothing, "Domain difference has output")
            Call AssertR11(result.Worksheets.Count = 1, "Single sheet result")
            result.Close SaveChanges:=False
            Set result = Nothing
        Else
            Call AssertR11(result Is Nothing, "Matching domains need no output")
            Call AssertR11(Application.Workbooks.Count = books, "No workbook on equality")
        End If
        Call AssertR11(mPending Is Nothing, "Default success clears first list")
        n = n + 1
    Next i
    testStage = "invalid stored settings"
    TraceR11 testStage
    SaveSetting SETTINGS_APP, scope, SETTINGS_KEY, "2|1|1|1"
    mSettingsLoaded = False
    LoadSettings
    Call AssertR11(Not mFullEmail And Not mIgnoreCase And Not mKeepFirst, "Unknown settings use defaults")
    Call AssertR11(GetSetting(SETTINGS_APP, scope, SETTINGS_KEY, "") = "2|1|1|1", "Invalid stored value not overwritten by read")
    n = n + 1
    Call AssertR11(ApplySettings(False, False, False, reason), "Reset test defaults")
    testStage = "equal counts and exclusions"
    TraceR11 testStage
    source.Activate
    ws.Range("A1:B3").ClearContents
    ws.Range("A1:A2").Value2 = "same"
    ws.Range("B1:B2").Value2 = "same"
    ws.Range("A3").Value2 = CVErr(xlErrNA)
    source.Saved = True
    ws.Range("A1:A3").Select
    RunSelection True, result, True
    Set captured = mPending
    books = Application.Workbooks.Count
    ws.Range("B1:B3").Select
    RunSelection False, result, True
    Call AssertR11(result Is Nothing And mPending Is Nothing, "Same duplicates and excluded error: no output, clear")
    Call AssertR11(Application.Workbooks.Count = books And source.Saved, "Equal comparison preserves source and documents")
    Call AssertR11(InStr(EqualityMessage(captured, TestSnapshot(ws.Range("B1:B3"))), SLC_U("CCAB 0020 BAA9 B85D 0020 0031 AC1C")) > 0, "Error exclusion notice")
    n = n + 1
    testStage = "different counts and default clearing"
    TraceR11 testStage
    ws.Range("B2").Value2 = "other"
    ws.Range("A1:A2").Select
    RunSelection True, firstResult, True
    ws.Range("B1:B2").Select
    RunSelection False, firstResult, True
    Call AssertR11(Not firstResult Is Nothing, "Different values need output")
    Call AssertR11(mPending Is Nothing, "Difference success clears first list")
    firstResult.Worksheets(1).Range("B1").Value2 = "User result edit sentinel"
    n = n + 1
    testStage = "settings locking and snapshot reuse"
    TraceR11 testStage
    Call AssertR11(ApplySettings(False, False, True, reason), "Enable reuse")
    source.Activate: ws.Range("A1:A2").Select
    RunSelection True, result, True
    Set captured = mPending
    Call AssertR11(Not ApplySettings(True, False, True, reason), "Email rules locked with first list")
    Call AssertR11(Not ApplySettings(False, True, True, reason), "Case rules locked with first list")
    Call AssertR11(ApplySettings(False, False, False, reason), "Keep option remains editable")
    Call AssertR11(ApplySettings(False, False, True, reason), "Keep option can be re-enabled")
    mBusy = True
    Call AssertR11(Not ApplySettings(False, False, False, reason), "All settings locked while busy")
    mBusy = False
    Call AssertR11(InStr(SLC_MenuXml(), "Settings") > 0 And InStr(SLC_MenuXml(), "&amp;") > 0, "Settings and escaped source in context menu")
    n = n + 1
    ws.Range("B2").Value2 = "same"
    ws.Range("A1").Value2 = "source changed after capture"
    ws.Range("B1:B2").Select
    RunSelection False, result, True
    Call AssertR11(result Is Nothing, "Stored snapshot still matches")
    Call AssertR11(mPending Is captured, "Reuse preserves snapshot identity")
    PreviewSnapshot preview, True
    Call AssertR11(preview.Worksheets.Count = 2, "Explicit preview remains available")
    preview.Close SaveChanges:=False: Set preview = Nothing
    n = n + 1
    testStage = "no comparable values"
    TraceR11 testStage
    source.Activate: ws.Range("D1:D3").Select
    RunSelection False, result, True
    Call AssertR11(mPending Is captured And result Is Nothing, "No comparable values preserves first list")
    n = n + 1
    For i = 0 To 1
        testStage = "output failure " & CStr(i)
    TraceR11 testStage
        Call AssertR11(ApplySettings(False, False, CBool(i), reason), "Both completion policies on failure")
        source.Activate: ws.Range("A1").Select
        books = Application.Workbooks.Count
        mTestOutputFailure = True
        On Error Resume Next
        RunSelection False, result, True
        errNo = Err.Number: Err.Clear
        On Error GoTo Failed
        mTestOutputFailure = False
        Call AssertR11(errNo = ERR_DATA, "Injected output failure observed")
        Call AssertR11(mPending Is captured, "Output failure preserves first snapshot")
        Call AssertR11(Application.Workbooks.Count = books, "Failed operation leaked no workbook")
        Call AssertR11(firstResult.Worksheets(1).Range("B1").Value2 = "User result edit sentinel", "Previous result preserved")
        n = n + 1
    Next i
    testStage = "cancel checkpoint"
    TraceR11 testStage
    mBusy = True: mCancelled = False
    SLC_Cancel
    On Error Resume Next
    PollCancellation
    errNo = Err.Number: Err.Clear
    On Error GoTo Failed
    Call AssertR11(errNo = ERR_CANCEL And mCancelled, "Cancel request reaches checkpoint")
    Call AssertR11(mPending Is captured, "Cancel checkpoint preserves snapshot")
    mBusy = False: mCancelled = False
    n = n + 1
    testStage = "clear and reset"
    TraceR11 testStage
    SLC_Clear
    SLC_ResetSettings
    Call AssertR11(mPending Is Nothing, "Explicit clear")
    Call AssertR11(GetSetting(SETTINGS_APP, scope, SETTINGS_KEY, "") = "1|0|0|0", "Reset saves defaults")
    Call AssertR11(ws.Range("A1").Value2 = "source changed after capture", "Clear preserves source")
    n = n + 1
    firstResult.Close SaveChanges:=False: Set firstResult = Nothing
    source.Close SaveChanges:=False: Set source = Nothing
    DeleteSetting SETTINGS_APP, scope
    mSettingsTestSection = ""
    ReleaseStatus
    Set mPending = oldPending
    mSettingsLoaded = savedLoaded: mFullEmail = savedFull: mIgnoreCase = savedIgnore: mKeepFirst = savedKeep
    mBusy = False: mCancelled = oldCancelled: mPhase = oldPhase: mLastOutcome = oldOutcome
    Application.StatusBar = oldStatus
    Application.EnableEvents = oldEvents
    Application.EnableCancelKey = oldCancel
    If Not oldBook Is Nothing Then oldBook.Activate
    RefreshUI
    ThisWorkbook.Worksheets(1).Range("A1").Formula = savedTestTrace
    SLC_UsabilityTests = "PASS: " & CStr(n) & " R11 settings/comparison/state checks; " & reportResult
    Exit Function
Failed:
    errNo = Err.Number: errText = Err.Description
    On Error Resume Next
    TraceR11 "failed: " & testStage & " / " & CStr(errNo) & " / " & errText
    Application.EnableCancelKey = xlDisabled
    mTestOutputFailure = False
    If Not result Is Nothing Then result.Close SaveChanges:=False
    If Not preview Is Nothing Then preview.Close SaveChanges:=False
    If Not firstResult Is Nothing Then firstResult.Close SaveChanges:=False
    If Not source Is Nothing Then source.Close SaveChanges:=False
    TraceR11 "cleanup settings: " & testStage & " / " & CStr(errNo) & " / " & errText
    If Len(mSettingsTestSection) > 0 Then
        If Len(GetSetting(SETTINGS_APP, mSettingsTestSection, SETTINGS_KEY, "")) > 0 Then
            DeleteSetting SETTINGS_APP, mSettingsTestSection
        End If
    End If
    mSettingsTestSection = ""
    ReleaseStatus
    Set mPending = oldPending
    mSettingsLoaded = savedLoaded: mFullEmail = savedFull: mIgnoreCase = savedIgnore: mKeepFirst = savedKeep
    mBusy = False: mCancelled = oldCancelled: mPhase = oldPhase: mLastOutcome = oldOutcome
    TraceR11 "cleanup application state: " & testStage & " / " & CStr(errNo) & " / " & errText
    Application.StatusBar = oldStatus
    Application.EnableEvents = oldEvents
    Application.EnableCancelKey = oldCancel
    If Not oldBook Is Nothing Then oldBook.Activate
    RefreshUI
    TraceR11 "cleanup complete: " & testStage & " / " & CStr(errNo) & " / " & errText
    ThisWorkbook.Worksheets(1).Range("A1").Formula = savedTestTrace
    On Error GoTo 0
    ' Return a failure to the automation owner instead of opening a VBA error UI.
    SLC_UsabilityTests = "FAIL: " & testStage & " / " & CStr(errNo) & " / " & errText
    Exit Function
InitialStateFailed:
    SLC_UsabilityTests = "FAIL: initial application state / " & CStr(Err.Number) & " / " & Err.Description
    On Error Resume Next
    ThisWorkbook.Worksheets(1).Range("A1").Formula = savedTestTrace
End Function

Private Sub TraceR11(ByVal stage As String)
    ' Test-only progress in the add-in's own scratch sheet, never business data.
    ' The original value is restored before returning; the runtime file is read-only.
    ThisWorkbook.Worksheets(1).Range("A1").Value2 = stage
End Sub

Public Function SLC_UiProbe() As String
    ' Developer check: return a diagnostic without raising a modal test failure.
    SLC_AttachUI
    If mUiAttached Then
        SLC_UiProbe = "PASS: toolbar and settings controls initialized"
    Else
        SLC_UiProbe = "FAIL: " & mUiFailure
    End If
End Function

Private Sub AssertR11(ByVal condition As Boolean, ByVal label As String)
    If Not condition Then Err.Raise ERR_DATA, "R11 essential checks", label
End Sub

Private Function IsOwnMacroBinding(ByVal action As String, ByVal procedureName As String) As Boolean
    ' Excel may canonicalize a binding to a full path or omit unnecessary quotes.
    ' The workbook identity and procedure must still match this exact add-in.
    Dim separator As Long, bookName As String
    separator = InStrRev(action, "!")
    If separator = 0 Then Exit Function
    If StrComp(Mid$(action, separator + 1), procedureName, vbTextCompare) <> 0 Then Exit Function
    bookName = Left$(action, separator - 1)
    If Left$(bookName, 1) = "'" And Right$(bookName, 1) = "'" Then
        bookName = Replace(Mid$(bookName, 2, Len(bookName) - 2), "''", "'")
    End If
    IsOwnMacroBinding = (StrComp(bookName, ThisWorkbook.Name, vbTextCompare) = 0 Or _
        StrComp(bookName, ThisWorkbook.FullName, vbTextCompare) = 0)
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
