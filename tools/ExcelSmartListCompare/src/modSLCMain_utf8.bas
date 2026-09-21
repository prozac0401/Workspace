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
    SLC_ReleaseVersion = "0.2.0-rc.12"
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
        xml = xml & MenuButton(prefix & "Cancel", "작업 취소", "SLC_CancelClick")
    Else
        If mPending Is Nothing Then
            xml = xml & MenuButton(prefix & "Capture", "첫 번째 목록 담기", "SLC_CaptureClick")
        Else
            xml = xml & MenuButton(prefix & "Compare", "두 번째 목록 담아 비교", "SLC_CompareClick")
            xml = xml & MenuLabel(prefix & "Count", PendingLabel())
            xml = xml & MenuLabel(prefix & "Source", PendingSource())
            xml = xml & MenuButton(prefix & "Preview", "담은 목록 확인", "SLC_PreviewClick")
            xml = xml & MenuButton(prefix & "Replace", "첫 번째 목록 바꾸기", "SLC_ReplaceClick")
            xml = xml & MenuButton(prefix & "Clear", "첫 번째 목록 비우기", "SLC_ClearClick")
        End If
        If Len(mLastOutcome) > 0 Then xml = xml & MenuLabel(prefix & "Outcome", mLastOutcome)
        xml = xml & SettingsMenuXml(prefix)
        xml = xml & MenuButton(prefix & "About", "사용 안내", "SLC_AboutClick")
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
        PendingLabel = "담아 둔 첫 번째 목록이 없습니다."
    Else
        PendingLabel = "첫 번째 목록: " & Format$(mPending.Total, "#,##0") & "개 항목"
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
        MsgBox "먼저 첫 번째 목록을 선택하고 [첫 번째 목록 담기]를 누르세요.", vbInformation, "명단 비교"
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
    AddButton bar.Controls, "명단 비교", "SLC_Run", "run"
    AddButton bar.Controls, "", "", "pending"
    AddButton bar.Controls, "담은 목록 확인", "SLC_Preview", "preview"
    AddButton bar.Controls, "작업 취소", "SLC_Cancel", "cancel"
    AddButton bar.Controls, "", "", "progress"
    AddButton bar.Controls, "첫 번째 목록 비우기", "SLC_Clear", "clear"
    AddButton bar.Controls, "첫 번째 목록 바꾸기", "SLC_Replace", "replace"
    uiStage = "add settings popup"
    Set settings = bar.Controls.Add(Type:=msoControlPopup, Temporary:=True)
    settings.Caption = "비교 설정"
    settings.Tag = UI_TAG & ".settings"
    uiStage = "add settings buttons"
    AddButton settings.Controls, "메일 전체 주소 비교 (@ 뒤 포함)", "SLC_ToggleFullEmail", "fullEmail"
    AddButton settings.Controls, "대소문자 무시", "SLC_ToggleIgnoreCase", "ignoreCase"
    AddButton settings.Controls, "비교 후 첫 목록 유지", "SLC_ToggleKeepFirst", "keepFirst"
    AddButton settings.Controls, "기본값으로 되돌리기", "SLC_ResetSettings", "resetSettings"
    AddButton settings.Controls, "", "", "settingsNote"
    AddButton bar.Controls, "사용 안내", "SLC_About", "about"
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
    If mPending Is Nothing Then title = "첫 번째 목록 담기" Else title = "두 번째 목록 담아 비교"
    On Error Resume Next
    Set bar = Application.CommandBars(BAR_NAME)
    If bar Is Nothing Then Exit Sub
    For Each ctl In bar.Controls
        Select Case ctl.Tag
            Case UI_TAG & ".run"
                ctl.Caption = title
                ctl.Enabled = Not mBusy
            Case UI_TAG & ".pending"
                ctl.Caption = Replace(PendingLabel() & " · " & PendingSource(), "&", "&&")
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
    mLastOutcome = "첫 번째 목록을 비웠습니다. 원본 셀은 그대로입니다."
    ReleaseStatus
    RefreshUI
End Sub

Public Sub SLC_Cancel()
    If Not mBusy Then Exit Sub
    mCancelled = True
    mPhase = "취소 요청됨 · 작업 종료를 기다려 주세요."
    SetStatus "명단 비교: " & mPhase
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
    SetStatus "명단 비교: " & text
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
    SetPhase "담은 첫 목록의 확인용 파일 만드는 중"
    Set completedResult = SLC_WriteSnapshotPreview(mPending)
    operationCommitted = True
    Application.EnableCancelKey = xlDisabled
    mLastOutcome = "담은 첫 목록의 확인용 파일을 열었습니다. 이어서 두 번째 목록과 비교할 수 있습니다."
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
        mLastOutcome = "확인 자료 생성 완료 · Excel 상태 복원 확인 필요"
    ElseIf errNo = 18 Or errNo = ERR_CANCEL Then
        mLastOutcome = "취소 완료 · 첫 번째 목록 유지"
    Else
        mLastOutcome = "확인 자료 작성 실패 · 첫 번째 목록 유지"
    End If
    Application.EnableCancelKey = oldCancel
    RefreshUI
    On Error GoTo 0
    If raiseTestError Then Err.Raise errNo, "PreviewSnapshot", errText
    MsgBox mLastOutcome & vbCrLf & PendingSummary() & vbCrLf & errText, vbInformation, "명단 비교"
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
        MsgBox "비교할 셀 범위를 선택해 주세요.", vbInformation, "명단 비교"
        Exit Sub
    End If
    Set selected = Application.Selection
    If Application.ActiveWindow.SelectedSheets.Count > 1 Then
        MsgBox "여러 시트가 함께 선택되어 있습니다. 시트 하나만 선택한 뒤 비교할 셀을 선택해 주세요.", vbInformation, "명단 비교"
        Exit Sub
    End If
    If Application.CalculationState <> xlDone Then
        MsgBox "Excel이 계산 중입니다. 계산이 끝난 뒤 다시 실행해 주세요.", vbInformation, "명단 비교"
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
    SetPhase "선택 범위 확인 중"
    Set parts = PrepareParts(selected, True, combining)
    If parts Is Nothing Then
        mLastOutcome = "작업을 시작하지 않았습니다. " & PendingLabel()
        GoTo Finished
    End If
    mStarted = Timer
    ' Keep keyboard input available so EnableCancelKey can handle Esc.
    ' The selected Range is already captured and mBusy rejects re-entry.
    Set exclusions = MetadataRects(selected.Worksheet)
    SetPhase "선택한 값 읽는 중"
    Set current = ReadParts(selected, parts, exclusions)
    ' A cancellation queued during the last partial chunk must precede commit.
    Checkpoint
    If current.Total = 0 Then
        mLastOutcome = "비교할 값 없음 · 이전 첫 목록 유지"
        ReleaseStatus
        If Not raiseTestError Then MsgBox "선택한 셀에 비교할 값이 없습니다." & vbCrLf & NoValuesSummary(current) & vbCrLf & _
               "숨긴 셀과 필터로 가려진 셀은 읽지 않습니다." & vbCrLf & PendingSummary(), _
               vbInformation, "명단 비교"
        GoTo Finished
    End If
    If Not combining Then
        SetPhase "첫 번째 목록 담기 마무리 중"
        Checkpoint
        ' No event dispatch or dialogs between the final check and commit.
        Application.EnableCancelKey = xlDisabled
        Set mPending = current
        operationCommitted = True
        mLastOutcome = "첫 목록을 담았습니다. [담은 목록 확인]에서 값과 원본 위치를 볼 수 있습니다."
    Else
        Set completedResult = ShowComparison(mPending, current)
        ' Output completion or the last equality checkpoint precedes this commit.
        Application.EnableCancelKey = xlDisabled
        If Not keepFirst Then Set mPending = Nothing
        operationCommitted = True
        If keepFirst Then
            mLastOutcome = "비교 완료 · 같은 첫 목록으로 이어서 비교할 수 있습니다."
        Else
            mLastOutcome = "비교 완료 · 첫 목록을 비웠습니다. 새 첫 목록을 담으세요."
        End If
        ReleaseStatus
        If completedResult Is Nothing And Not raiseTestError Then
            MsgBox EqualityMessage(previousPending, current), vbInformation, "명단 비교"
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
        mLastOutcome = "작업 완료 · Excel 상태 복원 확인 필요"
        RefreshUI
        MsgBox "작업 결과는 만들어졌지만 Excel 상태를 복원하는 중 문제가 생겼습니다." & vbCrLf & _
               "결과를 확인하고 필요한 파일을 저장한 뒤 Excel을 다시 실행해 주세요." & vbCrLf & _
               "오류 코드: " & CStr(errNo), vbExclamation, "명단 비교"
    ElseIf errNo = 18 Or errNo = ERR_CANCEL Then
        mLastOutcome = "취소 완료 · 이전 첫 목록 유지"
        RefreshUI
        MsgBox "작업을 취소했습니다." & vbCrLf & PendingSummary() & vbCrLf & _
               "이번 작업의 미완성 결과는 정리했습니다. 원본은 바뀌지 않았습니다.", vbInformation, "명단 비교"
    Else
        mLastOutcome = "작업 실패 · 이전 첫 목록 유지"
        RefreshUI
        MsgBox errText & vbCrLf & vbCrLf & PendingSummary() & vbCrLf & _
               "원본 내용은 바뀌지 않았습니다." & vbCrLf & "오류 코드: " & CStr(errNo), vbExclamation, "명단 비교"
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
        Err.Raise ERR_LIMIT, , "따로 선택한 영역이 5,000개를 넘습니다. 선택 범위를 줄여 주세요."
    End If
    ' Intersect, not Find: never changes the user's Find/Replace settings.
    Set bounded = Application.Intersect(sel, sel.Worksheet.UsedRange)
    If bounded Is Nothing Then
        Set PrepareParts = parts
        Exit Function
    End If
    scanCount = CDbl(bounded.CountLarge)
    If scanCount > MAX_SCAN Then
        Err.Raise ERR_LIMIT, , "숨김 여부를 확인할 셀이 2,000,000개를 넘습니다." & vbCrLf & _
            "행이나 열 전체를 선택했다면 값이 있는 부분만 다시 선택해 주세요."
    End If
    If bounded.Areas.Count > MAX_AREAS Then
        Err.Raise ERR_LIMIT, , "선택한 범위가 5,000개가 넘는 영역으로 나뉘어 있습니다. 선택 범위를 줄여 주세요."
    End If
    If scanCount >= WARN_SCAN Or bounded.Areas.Count >= WARN_AREAS Then
        text = "선택한 셀이 많아 숨김 여부를 확인하는 데 시간이 걸릴 수 있습니다." & vbCrLf & _
            "확인할 셀: " & Format$(scanCount, "#,##0") & "개" & vbCrLf & _
            "숨긴 셀과 필터로 가려진 셀은 비교에서 뺍니다." & vbCrLf & _
            "이 시험 버전에서는 Esc를 눌러도 작업이 취소되지 않을 수 있습니다." & vbCrLf & _
            "계속할까요? 범위를 줄이려면 [아니요]를 누르세요."
        If ask Then
            If MsgBox(text, vbYesNo + vbExclamation + vbDefaultButton2, "명단 비교 - 선택 범위 확인") <> vbYes Then Exit Function
        End If
        warned = True
        mStarted = Timer
    End If
    For Each ar In bounded.Areas
        Checkpoint
        mergeState = ar.MergeCells
        If IsNull(mergeState) Then
            Err.Raise ERR_DATA, , "선택한 범위에 병합된 셀이 있습니다. 병합된 셀을 빼고 다시 선택해 주세요."
        ElseIf CBool(mergeState) Then
            Err.Raise ERR_DATA, , "병합된 셀은 비교할 수 없습니다. 병합되지 않은 셀을 선택해 주세요."
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
                    Err.Raise specialErr, , "어떤 셀이 숨겨져 있는지 확인하지 못했습니다. 다시 실행해 주세요."
                ElseIf Not EntirelyHidden(ar) Then
                    ' 1004 is ambiguous: do not silently turn a visibility failure into an empty list.
                    Err.Raise ERR_DATA, , "어떤 셀이 숨겨져 있는지 확인하지 못했습니다. 선택 범위를 줄여 다시 실행해 주세요."
                End If
            End If
            If Not vis Is Nothing Then Set vis = Application.Intersect(ar, vis)
        End If
        If Not vis Is Nothing Then
            If parts.Count + vis.Areas.Count > MAX_AREAS Then
                Err.Raise ERR_LIMIT, , "비교할 셀이 5,000개가 넘는 영역에 나뉘어 있습니다. 선택 범위를 줄여 주세요."
            End If
            visibleCount = visibleCount + CDbl(vis.CountLarge)
            If visibleCount > MAX_VISIBLE Then
                Err.Raise ERR_LIMIT, , "한 목록에 담을 수 있는 셀은 100,000개까지입니다. 선택 범위를 줄여 주세요." & vbCrLf & _
                    "빈칸도 이 개수에 포함합니다. 숨긴 셀과 필터로 가려진 셀은 세지 않습니다."
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
            text = "선택한 값을 읽고 결과를 만드는 데 시간이 걸릴 수 있습니다." & vbCrLf & _
                   "이번에 선택한 범위: 숨기지 않은 셀 " & Format$(visibleCount, "#,##0") & "개 / " & _
                   Format$(parts.Count, "#,##0") & "개 영역" & vbCrLf & _
                   "이번 작업에서 다룰 셀: " & Format$(combinedCount, "#,##0") & "개" & vbCrLf & _
                   "이 시험 버전에서는 Esc를 눌러도 작업이 취소되지 않을 수 있습니다." & vbCrLf & _
                   "계속할까요? 범위를 줄이려면 [아니요]를 누르세요."
            If ask Then
                If MsgBox(text, vbYesNo + vbExclamation + vbDefaultButton2, "명단 비교 - 선택 범위 확인") <> vbYes Then Exit Function
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
                        SetStatus "명단 비교: 읽는 중 · " & Format$(result.VisibleCellCount, "#,##0") & "셀 확인 / " & _
                            Format$(result.Total, "#,##0") & "개 항목 담음"
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
        Err.Raise ERR_LIMIT, , address & " 셀의 내용이 4,096자를 넘습니다. 이 셀을 빼고 다시 선택해 주세요."
    End If
    list.RawCharCount = list.RawCharCount + Len(raw)
    If list.RawCharCount > MAX_RAW_CHARS Then
        Err.Raise ERR_LIMIT, , "선택한 셀의 내용을 모두 합치면 5,000,000자를 넘습니다. 선택 범위를 줄여 주세요."
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
    result = "제외: 빈칸 " & list.BlankCount & "개 / 오류 " & list.ErrorCount & _
        "개 / 제목·합계 " & list.MetadataCount & "개"
    For Each sample In list.ErrorSamples
        shown = shown + 1
        If shown > 5 Then Exit For
        result = result & vbCrLf & CStr(sample(0)) & ": " & CStr(sample(1))
    Next sample
    If list.ErrorCount > 5 Then result = result & vbCrLf & "오류 위치는 처음 5개만 표시했습니다."
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
    If rng.Areas.Count > 1 Then label = label & " 외 " & CStr(rng.Areas.Count - 1) & "개 영역"
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
    If rng.Areas.Count > 6 Then s = s & " ... (총 " & CStr(rng.Areas.Count) & "개 영역)"
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
        Err.Raise ERR_TIME, , "작업 시간이 길어져 중단했습니다." & vbCrLf & _
            "두 목록을 행 번호로 나누면 잘못된 차이가 나올 수 있습니다." & vbCrLf & _
            "전체 비교가 필요하면 값을 빠뜨리지 않는 비교 방법을 사용해 주세요."
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
    SetPhase "값과 개수 비교 중"
    ' One pass is sufficient: total minus matched gives each list's excess.
    ' Do not partition by row or allocate a second union of all comparison keys.
    For Each k In a.Counts.Keys
        ca = CLng(a.Counts(CStr(k)))
        cb = CountOf(b, CStr(k))
        If ca < cb Then matched = matched + ca Else matched = matched + cb
        tick = tick + 1
        If tick Mod CANCEL_POLL_ITEMS = 0 Then PollCancellation
        If tick Mod 1024 = 0 Then
            SetStatus "명단 비교: 값과 개수 비교 중 · " & Format$(tick, "#,##0") & "종류 확인"
            Checkpoint
        End If
    Next k
    Checkpoint
    If matched = a.Total And matched = b.Total Then Exit Function
    SetPhase "결과 작성 중"
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
        reason = "작업이 끝난 뒤 설정을 바꿔 주세요."
        Exit Function
    End If
    If Not mPending Is Nothing Then
        If fullEmail <> mPending.CompareFullEmail Or ignoreCase <> mPending.IgnoreCase Then
            reason = "비교 기준을 바꾸려면 첫 목록을 비워 주세요."
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
    reason = "설정을 저장하지 못했습니다. 기존 설정은 유지됩니다."
    If Len(mSettingsTestSection) > 0 Then reason = reason & " / " & CStr(Err.Number) & " / " & Err.Description
End Function

Private Sub ChangeSettings(ByVal fullEmail As Boolean, ByVal ignoreCase As Boolean, ByVal keepFirst As Boolean)
    Dim reason As String
    If Not ApplySettings(fullEmail, ignoreCase, keepFirst, reason) Then
        If Len(mSettingsTestSection) > 0 Then Err.Raise ERR_DATA, "R11 setting action", reason
        MsgBox reason, vbInformation, "비교 설정"
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
        MsgBox "기본값으로 되돌리려면 첫 목록을 비워 주세요.", vbInformation, "비교 설정"
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
    xml = "<menu id=""" & prefix & "Settings"" label=""비교 설정"">"
    xml = xml & SettingsCheck(prefix, "fullEmail", "메일 전체 주소 비교 (@ 뒤 포함)", rulesEnabled)
    xml = xml & SettingsCheck(prefix, "ignoreCase", "대소문자 무시", rulesEnabled)
    xml = xml & SettingsCheck(prefix, "keepFirst", "비교 후 첫 목록 유지", Not mBusy)
    xml = xml & "<button id=""" & prefix & "ResetSettings"" label=""기본값으로 되돌리기"" enabled=""" & _
        XmlBoolean(rulesEnabled) & """ onAction=""SLC_ResetSettingsClick""/>"
    If mPending Is Nothing Then
        xml = xml & MenuLabel(prefix & "SettingsNote", "설정은 다음 Excel 실행에도 기억합니다.")
    Else
        xml = xml & MenuLabel(prefix & "SettingsNote", "비교 기준을 바꾸려면 첫 목록을 비워 주세요.")
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
                    button.Caption = "설정은 다음 Excel 실행에도 기억합니다."
                Else
                    button.Caption = "비교 기준을 바꾸려면 첫 목록을 비워 주세요."
                End If
        End Select
        If checked Then button.State = msoButtonDown Else button.State = msoButtonUp
    Next button
End Sub

Public Function SLC_RulesText(ByVal fullEmail As Boolean, ByVal ignoreCase As Boolean) As String
    If fullEmail Then SLC_RulesText = "메일: 전체 주소 비교" Else SLC_RulesText = "메일: @ 앞부분만 비교"
    If ignoreCase Then SLC_RulesText = SLC_RulesText & " / 대문자·소문자: 같게 봄" Else SLC_RulesText = SLC_RulesText & " / 대문자·소문자: 구분함"
End Function

Public Function SLC_CompletionPolicyText() As String
    If mKeepFirst Then
        SLC_CompletionPolicyText = "비교가 끝나면 첫 목록을 남깁니다."
    Else
        SLC_CompletionPolicyText = "비교가 끝나면 첫 목록을 비웁니다."
    End If
End Function

Private Function EqualityMessage(ByVal a As CSLCList, ByVal b As CSLCList) As String
    If a.ErrorCount + b.ErrorCount > 0 Then
        EqualityMessage = "오류 셀을 뺀 나머지 값과 개수가 같습니다." & vbCrLf & _
            "제외한 오류: 첫 목록 " & CStr(a.ErrorCount) & "개 / 두 번째 목록 " & CStr(b.ErrorCount) & "개"
    Else
        EqualityMessage = "선택한 비교 기준으로 두 목록의 값과 개수가 같습니다."
    End If
    EqualityMessage = EqualityMessage & vbCrLf & "결과 파일은 만들지 않았습니다."
End Function

Public Sub SLC_About()
    If mBusy Then Exit Sub
    MsgBox "Excel 명단 비교 " & SLC_ReleaseVersion() & vbCrLf & vbCrLf & _
        "1. 첫 목록의 셀을 선택하고 [첫 번째 목록 담기]를 누르세요." & vbCrLf & _
        "2. [담은 목록 확인]에서 담은 값의 일부와 원본 위치를 확인하세요." & vbCrLf & _
        "3. 두 번째 목록을 선택하고 [두 번째 목록 담아 비교]를 누르세요." & vbCrLf & vbCrLf & _
        "선택한 셀 전체가 목록 하나입니다. 순서와 방향은 무시하고 값별 개수를 비교합니다." & vbCrLf & _
        "[비교 설정]에서 메일 전체 주소·대소문자 무시·첫 목록 유지를 선택하세요." & vbCrLf & _
        "기본값은 @ 앞부분 비교, 대소문자 구분, 비교 후 첫 목록 비우기입니다." & vbCrLf & _
        "같으면 결과 파일을 만들지 않습니다. 차이가 있으면 결과를 직접 저장하세요." & vbCrLf & _
        "설정은 자동으로 기억합니다. [기본값으로 되돌리기]로 초기화할 수 있습니다." & vbCrLf & _
        "담은 뒤 원본을 고쳐도 이미 담긴 값은 바뀌지 않습니다. Excel 종료 시 사라집니다." & vbCrLf & _
        "[작업 취소] 또는 Esc로 취소를 요청한 뒤 완료 안내를 확인하세요." & vbCrLf & _
        "100,000셀은 입력 한도이며 완료 보장량이 아닙니다. 행 번호로 임의 분할하지 마세요.", _
        vbInformation, "명단 비교 - 사용 안내"
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
    ws.Range("D2").Value2 = " 홍길동 "
    ws.Range("E2").Value2 = "00123"
    ws.Range("H3:H6").NumberFormat = "@"
    ws.Range("H3").Value2 = "00123"
    ws.Range("H4").Value2 = "홍길동"
    ws.Range("H5").Value2 = "USER@b.com"
    ws.Range("H6").Value2 = "123"
    Set a = TestSnapshot(ws.Range("B2:E2"))
    Set b = TestSnapshot(ws.Range("H3:H6"))
    AssertSame a, b, "horizontal -> vertical"
    AssertSame b, a, "vertical -> horizontal"
    n = n + 2
    arr(1, 1) = "00123": arr(1, 2) = "홍길동"
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
    Call AssertR11(InStr(EqualityMessage(captured, TestSnapshot(ws.Range("B1:B3"))), "첫 목록 1개") > 0, "Error exclusion notice")
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
