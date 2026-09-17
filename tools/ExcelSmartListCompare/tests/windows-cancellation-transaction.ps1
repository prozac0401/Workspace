[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]$Excel,
    [Parameter(Mandatory=$true)][int]$OwnedPid,
    [Parameter(Mandatory=$true)][string]$ExpectedAddinPath,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [string]$ExpectedSourcePath=(Join-Path (Split-Path $PSScriptRoot -Parent) 'src/modSLCMain.bas'),
    [scriptblock]$CanonicalizeSource
)
# Developer-only, memory-only fault probes. They do not press Esc or prove native
# keyboard cancellation. The host owns Excel, authorizes existing VBA access,
# restores that access, and checks the add-in hash again after Excel exits.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
function Release-ProbeCom($Value) {
    if($null -ne $Value -and [Runtime.InteropServices.Marshal]::IsComObject($Value)) {
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($Value)
    }
}
function Get-ProbeSharedHash([string]$Path) {
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant()}
    finally{$stream.Dispose()}
}
function Normalize-ProbeModule([string]$Text) {
    return (($Text -replace '(?m)^Attribute [^\r\n]+\r?\n','') -replace '\r\n?',"`n").Trim()
}
function Compare-ProbeModule([string]$Left,[string]$Right) {
    if($null -ne $CanonicalizeSource){
        return ([string](& $CanonicalizeSource $Left) -ceq [string](& $CanonicalizeSource $Right))
    }
    return ((Normalize-ProbeModule $Left) -ceq (Normalize-ProbeModule $Right))
}
function Replace-ProbeAnchor([string]$Text,[string]$Anchor,[string]$Replacement,[string]$Label) {
    if([regex]::Matches($Text,[regex]::Escape($Anchor)).Count -ne 1) {
        throw ('Expected exactly one injection anchor: '+$Label)
    }
    return $Text.Replace($Anchor,$Replacement)
}
function Replace-ProbeProcedure([string]$Text,[string]$Name,[scriptblock]$Transform) {
    $pattern='(?ms)^(?:Private|Public) (Sub|Function) '+[regex]::Escape($Name)+'\b.*?^End \1\s*(?=\r?$)'
    $matches=[regex]::Matches($Text,$pattern)
    if($matches.Count -ne 1){throw ('Expected one procedure: '+$Name)}
    $match=$matches[0]
    $replacement=[string](& $Transform $match.Value)
    return $Text.Substring(0,$match.Index)+$replacement+$Text.Substring($match.Index+$match.Length)
}

$output=[IO.Path]::GetFullPath($OutputPath)
if(Test-Path -LiteralPath $output){throw 'Use a new evidence output path.'}
$parent=Split-Path -Parent $output
if(-not (Test-Path -LiteralPath $parent -PathType Container)){throw 'Evidence parent must already exist.'}
$expected=[IO.Path]::GetFullPath($ExpectedAddinPath)
if(-not (Test-Path -LiteralPath $expected -PathType Leaf)){throw 'Expected add-in file is missing.'}
if(-not ('SlcTransactionProbe.Native' -as [type])) {
    Add-Type 'using System;using System.Runtime.InteropServices;namespace SlcTransactionProbe {public static class Native {[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);}}'
}
[uint32]$actualPid=0
[void][SlcTransactionProbe.Native]::GetWindowThreadProcessId([IntPtr]$Excel.Hwnd,[ref]$actualPid)
if($actualPid -ne $OwnedPid){throw 'Different Excel process; no changes made.'}
$book=$null;$project=$null;$component=$null;$module=$null
$original=$null;$savedBefore=$false;$mutated=$false;$restored=$false
$errorText=$null;$restoreError=$null;$errorDetails=$null;$failureStack=$null
$activeCase=$null;$failedCase=$null
$cleanupErrors=[Collections.Generic.List[string]]::new()
$checks=[Collections.Generic.List[object]]::new()
$hashBefore=Get-ProbeSharedHash $expected
$hashAfter=$null
try {
    $book=$Excel.Workbooks.Item([IO.Path]::GetFileName($expected))
    if([IO.Path]::GetFullPath([string]$book.FullName) -ine $expected){throw 'Loaded add-in path differs from expected owned file.'}
    if(-not [bool]$book.IsAddin){throw 'Expected workbook is not an add-in.'}
    $savedBefore=[bool]$book.Saved
    if(-not $savedBefore){throw 'Add-in has existing unsaved changes; refusing source injection.'}
    $qualified="'"+([string]$book.Name).Replace("'","''")+"'!"
    $menu=[string]$Excel.Run($qualified+'SLC_MenuXml','Cell')
    if($menu -notmatch 'slc68CellCapture' -or $menu -match 'slc68CellCompare') {
        throw 'Existing pending snapshot; use a fresh owned developer Excel session.'
    }
    $project=$book.GetType().InvokeMember('VBProject',[Reflection.BindingFlags]::GetProperty,$null,$book,$null)
    $component=$project.VBComponents.Item('modSLCMain')
    $module=$component.CodeModule
    $original=[string]$module.Lines(1,$module.CountOfLines)
    $current=[IO.File]::ReadAllText([IO.Path]::GetFullPath($ExpectedSourcePath),[Text.Encoding]::ASCII)
    if(-not (Compare-ProbeModule $original $current)) {
        throw 'Loaded main module differs from current ASCII source; rebuild and audit this candidate first.'
    }
    # Once equivalence is verified, use the source snapshot's identifier spelling
    # for exact injection anchors; VBE may have recased the equivalent live code.
    $injected=Normalize-ProbeModule $current
    $declarations=@'
Private mProbeStage As String
Private mProbeReadCount As Long
Private mProbeFired As Boolean
Private mProbeError As Long
Private mProbeMessages As Long
Private mProbeLastMessage As String
Private mProbeLastButtons As Long
Private mProbeAssertions As Long
Private mProbeResultBook As Workbook
Private mProbeOutputNoFormula As Boolean
'@
    $injected=Replace-ProbeAnchor $injected 'Option Explicit' ("Option Explicit`n"+$declarations) 'module declarations'
    # Replace only executable calls, never message text/comments. Check the
    # count against the source read above, and verify none remain afterward.
    $messagePattern='(?m)^(\s*)(MsgBox\b|If MsgBox\()'
    $messageCalls=[regex]::Matches($injected,$messagePattern).Count
    if($messageCalls -lt 10 -or $messageCalls -gt 14){throw 'Unexpected message-call surface; review probe instrumentation.'}
    $injected=[regex]::Replace($injected,$messagePattern,[Text.RegularExpressions.MatchEvaluator]{param($m) $m.Value.Replace('MsgBox','SLC_ProbeMessage')})
    if([regex]::Matches($injected,$messagePattern).Count -ne 0){throw 'Message instrumentation incomplete.'}
    if([regex]::Matches($injected,'(?m)^\s*(SLC_ProbeMessage\b|If SLC_ProbeMessage\()').Count -ne $messageCalls) {
        throw 'Message instrumentation count differs from the original source.'
    }
    $injected=Replace-ProbeProcedure $injected 'RunSelection' {
        param($body)
        Replace-ProbeAnchor $body '    errNo = Err.Number' "    errNo = Err.Number`n    mProbeError = errNo" 'operation error observation'
    }
    $injected=Replace-ProbeProcedure $injected 'AddValue' {
        param($body)
        Replace-ProbeAnchor $body 'End Sub' "    SLC_ProbeAfterValue`nEnd Sub" 'last value cancellation'
    }
    $injected=Replace-ProbeProcedure $injected 'WriteResults' {
        param($body)
        Replace-ProbeAnchor $body '    ws.Range("A1").Select' "    ws.Range(`"A1`").Select`n    SLC_ProbeAfterOutput wb, ws" 'late output cancellation'
    }
    $injected=Replace-ProbeProcedure $injected 'SetStatus' {
        param($body)
        Replace-ProbeAnchor $body '    Application.StatusBar = text' "    Application.StatusBar = text`n    If mProbeStage = `"status-error`" Then`n        mProbeFired = True`n        Err.Raise vbObjectError + 2198, `"SLC transaction probe`", `"Synthetic staged status failure`"`n    End If" 'staged status error'
    }
    $injected=Replace-ProbeProcedure $injected 'OwnForegroundEscapeHeld' {
        param($body)
        Replace-ProbeAnchor $body '    If Not mBusy Then Exit Function' "    If Not mBusy Then Exit Function`n    SLC_ProbeApiFailure" 'API failure after busy guard'
    }
    $probe=@'

Private Function SLC_ProbeMessage(ByVal prompt As Variant, Optional ByVal buttons As Long = 0, _
                                  Optional ByVal title As String = "") As Long
    mProbeMessages = mProbeMessages + 1
    mProbeLastMessage = CStr(prompt)
    mProbeLastButtons = buttons
    ' Every fixture is below the warning threshold. An unexpected warning is
    ' declined; assertions must fail rather than silently accepting a warning.
    If (buttons And 7) = vbYesNo Then SLC_ProbeMessage = vbNo Else SLC_ProbeMessage = vbOK
End Function

Private Sub SLC_ProbeApiFailure()
    ' Synthetic exceptions test the actual VBA error path, never an ASR policy.
    Select Case mProbeStage
        Case "api-unavailable"
            mProbeFired = True
            Err.Raise 453, "SLC API availability probe", "Synthetic unavailable Win32 API"
        Case "api-interruption"
            mProbeFired = True
            Err.Raise 18, "SLC API interruption probe", "Synthetic native interruption"
    End Select
End Sub

Private Sub SLC_ProbeAfterValue()
    If mProbeStage = "read-tail" Then
        mProbeReadCount = mProbeReadCount + 1
        If mProbeReadCount = 6 Then
            mProbeFired = True
            mCancelled = True
        End If
    End If
End Sub

Private Sub SLC_ProbeAfterOutput(ByVal wb As Workbook, ByVal ws As Worksheet)
    Set mProbeResultBook = wb
    If mProbeStage = "output-tail" Then
        mProbeOutputNoFormula = (ws.UsedRange.HasFormula = False)
        mProbeFired = True
        mCancelled = True
    End If
End Sub

Private Sub SLC_ProbeAssert(ByVal condition As Boolean, ByVal label As String)
    If Not condition Then Err.Raise vbObjectError + 2199, "SLC transaction probe", label
    mProbeAssertions = mProbeAssertions + 1
End Sub

Private Function SLC_ProbeBookOpen(ByVal target As Workbook) As Boolean
    Dim item As Workbook
    If target Is Nothing Then Exit Function
    For Each item In Application.Workbooks
        If item Is target Then SLC_ProbeBookOpen = True: Exit Function
    Next item
End Function

Public Function SLC_CancellationTransactionProbe(ByVal caseName As String) As String
    Dim source As Workbook, prior As Workbook, previousBook As Workbook, ws As Worksheet
    Dim savedPending As CSLCList, savedSource As String, savedCaptured As Date
    Dim oldScreen As Boolean, oldEvents As Boolean, oldInteractive As Boolean
    Dim oldCancel As Long, oldCalculation As Long, oldStatus As Variant
    Dim booksBefore As Long, expectedError As Long, errorNo As Long, errorText As String
    Dim priorSaved As Boolean, stateCaptured As Boolean
    Dim values(1 To 3, 1 To 2) As Variant, r As Long, c As Long
    On Error GoTo Failed
    If mBusy Or Not mPending Is Nothing Then Err.Raise 5, , "Probe requires idle empty product state"
    oldScreen = Application.ScreenUpdating
    oldEvents = Application.EnableEvents
    oldInteractive = Application.Interactive
    oldCancel = Application.EnableCancelKey
    oldCalculation = Application.Calculation
    oldStatus = Application.StatusBar
    Set previousBook = Application.ActiveWorkbook
    booksBefore = Application.Workbooks.Count
    stateCaptured = True
    mProbeStage = ""
    mProbeError = 0
    mProbeMessages = 0
    mProbeAssertions = 0
    mProbeReadCount = 0
    mProbeFired = False
    mProbeOutputNoFormula = False
    Set mProbeResultBook = Nothing
    Set prior = Application.Workbooks.Add(xlWBATWorksheet)
    prior.Worksheets(1).Range("A1:A2").NumberFormat = "@"
    prior.Worksheets(1).Range("A1").Value2 = "USER_EDIT_SENTINEL"
    prior.Worksheets(1).Range("A2").Value2 = "=KEEP_AS_TEXT"
    priorSaved = prior.Saved
    Set source = Application.Workbooks.Add(xlWBATWorksheet)
    Set ws = source.Worksheets(1)
    ws.Range("C3:C5").NumberFormat = "@"
    ws.Range("C3").Value2 = "alpha"
    ws.Range("C4").Value2 = "alpha"
    ws.Range("C5").Value2 = "beta"
    For r = 1 To 3
        For c = 1 To 2
            values(r, c) = "new_" & CStr(r) & "_" & CStr(c)
        Next c
    Next r
    values(3, 2) = "=2+2"
    ws.Range("F7:G9").NumberFormat = "@"
    ws.Range("F7:G9").Value2 = values
    ws.Range("C3:C5").Select
    SLC_Capture
    SLC_ProbeAssert Not mPending Is Nothing, "Baseline capture did not create snapshot"
    SLC_ProbeAssert mProbeMessages = 0, "Unexpected baseline message"
    Set savedPending = mPending
    savedSource = mPending.Source
    savedCaptured = mPending.CapturedAt
    ReleaseStatus
    Application.StatusBar = "EXTERNAL_SYNTHETIC_STATUS"
    mProbeMessages = 0
    mProbeLastMessage = ""
    mProbeLastButtons = 0
    ws.Range("F7:G9").Select
    Select Case caseName
        Case "replacement-tail", "comparison-tail"
            mProbeStage = "read-tail"
            expectedError = ERR_CANCEL
        Case "output-tail"
            mProbeStage = "output-tail"
            expectedError = ERR_CANCEL
        Case "staged-status-error"
            mProbeStage = "status-error"
            expectedError = vbObjectError + 2198
        Case "api-unavailable-replacement", "api-unavailable-comparison"
            mProbeStage = "api-unavailable"
            expectedError = 453
        Case "api-interruption-replacement", "api-interruption-comparison"
            mProbeStage = "api-interruption"
            expectedError = 18
        Case Else
            Err.Raise 5, , "Unknown transaction probe case"
    End Select
    If caseName = "replacement-tail" Or caseName = "staged-status-error" Or _
        caseName = "api-unavailable-replacement" Or caseName = "api-interruption-replacement" Then
        SLC_Replace
    Else
        SLC_Compare
    End If
    mProbeStage = ""
    SLC_ProbeAssert mProbeFired, "Fault site was not reached"
    SLC_ProbeAssert mProbeError = expectedError, "Public error handler did not observe expected error"
    SLC_ProbeAssert mProbeMessages = 1, "Expected exactly one public outcome message"
    If Left$(caseName, 16) = "api-unavailable-" Then
        SLC_ProbeAssert mProbeLastButtons = vbExclamation, "API failure was not reported as an error"
        SLC_ProbeAssert InStr(1, mProbeLastMessage, "453", vbBinaryCompare) > 0, "API failure code missing from outcome"
    ElseIf Left$(caseName, 17) = "api-interruption-" Then
        SLC_ProbeAssert mProbeLastButtons = vbInformation, "Native interruption was not reported as cancellation"
    End If
    SLC_ProbeAssert Not mPending Is Nothing, "Original snapshot lost"
    SLC_ProbeAssert (mPending Is savedPending), "Original snapshot object replaced"
    SLC_ProbeAssert mPending.Total = 3, "Original item count changed"
    SLC_ProbeAssert mPending.Counts.Count = 2, "Original unique keys changed"
    SLC_ProbeAssert mPending.Counts("#t:alpha") = 2, "Original duplicate count changed"
    SLC_ProbeAssert mPending.Counts("#t:beta") = 1, "Original beta count changed"
    SLC_ProbeAssert mPending.Examples("#t:alpha") = "alpha", "Original alpha example changed"
    SLC_ProbeAssert mPending.Examples("#t:beta") = "beta", "Original beta example changed"
    SLC_ProbeAssert mPending.Addresses("#t:alpha") = "C3", "Original alpha address changed"
    SLC_ProbeAssert mPending.Addresses("#t:beta") = "C5", "Original beta address changed"
    SLC_ProbeAssert mPending.Source = savedSource, "Original source label changed"
    SLC_ProbeAssert mPending.CapturedAt = savedCaptured, "Original capture time changed"
    SLC_ProbeAssert Application.ScreenUpdating = oldScreen, "ScreenUpdating not restored"
    SLC_ProbeAssert Application.EnableEvents = oldEvents, "EnableEvents not restored"
    SLC_ProbeAssert Application.Interactive = oldInteractive, "Interactive not restored"
    SLC_ProbeAssert Application.EnableCancelKey = oldCancel, "EnableCancelKey not restored"
    SLC_ProbeAssert Application.Calculation = oldCalculation, "Calculation changed"
    SLC_ProbeAssert Not mBusy, "Operation remains busy"
    SLC_ProbeAssert Application.Workbooks.Count = booksBefore + 2, "Partial result workbook leaked"
    SLC_ProbeAssert prior.Worksheets(1).Range("A1").Value2 = "USER_EDIT_SENTINEL", "Previous result edit changed"
    SLC_ProbeAssert prior.Worksheets(1).Range("A2").Value2 = "=KEEP_AS_TEXT", "Previous result text changed"
    SLC_ProbeAssert prior.Worksheets(1).UsedRange.HasFormula = False, "Previous result gained formula"
    SLC_ProbeAssert prior.Saved = priorSaved, "Previous result Saved state changed"
    For r = 1 To 3
        For c = 1 To 2
            SLC_ProbeAssert ws.Cells(r + 6, c + 5).Value2 = values(r, c), "Source replacement value changed"
        Next c
    Next r
    SLC_ProbeAssert ws.Range("C3").Value2 = "alpha", "Source alpha changed"
    SLC_ProbeAssert ws.Range("C4").Value2 = "alpha", "Source duplicate changed"
    SLC_ProbeAssert ws.Range("C5").Value2 = "beta", "Source beta changed"
    SLC_ProbeAssert ws.UsedRange.HasFormula = False, "Source gained formula"
    SLC_ProbeAssert Application.StatusBar = "EXTERNAL_SYNTHETIC_STATUS", "External status not restored"
    SLC_ProbeAssert Not SLC_ProbeBookOpen(mProbeResultBook), "Owned output workbook remains open"
    If caseName = "output-tail" Then
        SLC_ProbeAssert Not mProbeResultBook Is Nothing, "Output cancellation never reached created result"
        SLC_ProbeAssert mProbeOutputNoFormula, "Provisional output contains formulas"
    End If
    SLC_CancellationTransactionProbe = "PASS|" & caseName & "|" & CStr(mProbeAssertions)
    GoTo Cleanup
Failed:
    errorNo = Err.Number
    errorText = Err.Description
Cleanup:
    If Not stateCaptured Then
        If errorNo <> 0 Then Err.Raise errorNo, "SLC_CancellationTransactionProbe", errorText
        Exit Function
    End If
    On Error Resume Next
    Application.EnableCancelKey = xlDisabled
    mProbeStage = ""
    If SLC_ProbeBookOpen(mProbeResultBook) Then mProbeResultBook.Close SaveChanges:=False
    Set mProbeResultBook = Nothing
    Set mPending = Nothing
    mBusy = False
    mCancelled = False
    ReleaseStatus
    If Not source Is Nothing Then source.Close SaveChanges:=False
    If Not prior Is Nothing Then prior.Close SaveChanges:=False
    Application.ScreenUpdating = oldScreen
    Application.EnableEvents = oldEvents
    Application.Interactive = oldInteractive
    If VarType(oldStatus) = vbBoolean Then
        Application.StatusBar = False
    Else
        Application.StatusBar = oldStatus
    End If
    If Not previousBook Is Nothing Then previousBook.Activate
    RefreshUI
    Application.EnableCancelKey = oldCancel
    On Error GoTo 0
    If errorNo <> 0 Then Err.Raise errorNo, "SLC_CancellationTransactionProbe", errorText
    If Application.Workbooks.Count <> booksBefore Then Err.Raise 5, , "Probe cleanup left a workbook"
End Function

Public Function SLC_TransactionGeometryProbe() As String
    Dim wb As Workbook, ws As Worksheet, previousBook As Workbook, snap As CSLCList
    Dim values(1 To 4100, 1 To 2) As Variant, parts As Collection, exclusions As Collection
    Dim r As Long, c As Long, oldCancel As Long, oldStatus As Variant
    Dim errorNo As Long, errorText As String, booksBefore As Long, stateCaptured As Boolean
    On Error GoTo Failed
    If mBusy Or Not mPending Is Nothing Then Err.Raise 5, , "Geometry probe requires idle empty product state"
    oldCancel = Application.EnableCancelKey
    oldStatus = Application.StatusBar
    Set previousBook = Application.ActiveWorkbook
    booksBefore = Application.Workbooks.Count
    stateCaptured = True
    mProbeStage = ""
    mProbeAssertions = 0
    mCancelled = False
    Set wb = Application.Workbooks.Add(xlWBATWorksheet)
    Set ws = wb.Worksheets(1)
    For r = 1 To 4100
        For c = 1 To 2
            values(r, c) = "v_" & CStr(r) & "_" & CStr(c)
        Next c
    Next r
    ws.Range("C3:D4102").NumberFormat = "@"
    ws.Range("C3:D4102").Value2 = values
    Set snap = TestSnapshot(ws.Range("C3:D4102"))
    SLC_ProbeAssert snap.Total = 8200, "Multi-chunk total mismatch"
    SLC_ProbeAssert snap.Counts.Count = 8200, "Multi-chunk distinct keys mismatch"
    SLC_ProbeAssert snap.Addresses("#t:v_1_1") = "C3", "First coordinate mismatch"
    SLC_ProbeAssert snap.Addresses("#t:v_1_2") = "D3", "Second column coordinate mismatch"
    SLC_ProbeAssert snap.Addresses("#t:v_4096_2") = "D4098", "Chunk boundary coordinate mismatch"
    SLC_ProbeAssert snap.Addresses("#t:v_4097_1") = "C4099", "Second chunk coordinate mismatch"
    SLC_ProbeAssert snap.Addresses("#t:v_4100_2") = "D4102", "Final coordinate mismatch"
    Set parts = New Collection
    parts.Add ws.Range("C3:C5")
    parts.Add ws.Range("C4:C6")
    Set exclusions = New Collection
    mStarted = Timer
    Set snap = ReadParts(ws.Range("C3:C6"), parts, exclusions)
    SLC_ProbeAssert snap.Total = 4, "Overlapping parts counted twice"
    SLC_ProbeAssert snap.VisibleCellCount = 4, "Overlapping visible count mismatch"
    SLC_ProbeAssert snap.Counts("#t:v_2_1") = 1, "Overlapping key count mismatch"
    SLC_ProbeAssert snap.Addresses("#t:v_4_1") = "C6", "Overlapping tail address mismatch"
    SLC_ProbeAssert SLC_Normalize(ChrW(&HFF21&) & ChrW(&HFF22&) & ChrW(&HFF23&)) = "#t:abc", "Full-width letters mismatch"
    SLC_ProbeAssert SLC_Normalize(ChrW(&HFF10&) & ChrW(&HFF10&) & ChrW(&HFF13&)) = "#t:003", "Full-width leading zeros lost"
    SLC_ProbeAssert SLC_Normalize(ChrW(&H4E2D&) & ChrW(&H6587&)) = "#t:" & ChrW(&H4E2D&) & ChrW(&H6587&), "CJK text changed"
    SLC_ProbeAssert SLC_Normalize("e" & ChrW(&H301&)) = "#t:e" & ChrW(&H301&), "Combining character changed"
    SLC_ProbeAssert SLC_Normalize(ChrW(-10179) & ChrW(-8704)) = "#t:" & ChrW(-10179) & ChrW(-8704), "Surrogate pair changed"
    SLC_ProbeAssert SLC_Normalize(String$(4096, "x")) = "#t:" & String$(4096, "x"), "Long string changed"
    SLC_ProbeAssert SLC_Normalize("USER@example.invalid") = "#t:user", "Email normalization changed"
    SLC_ProbeAssert SLC_Normalize("00123") = "#t:00123", "Leading zeros changed"
    SLC_TransactionGeometryProbe = "PASS|geometry-normalization|" & CStr(mProbeAssertions)
    GoTo Cleanup
Failed:
    errorNo = Err.Number
    errorText = Err.Description
Cleanup:
    If Not stateCaptured Then
        If errorNo <> 0 Then Err.Raise errorNo, "SLC_TransactionGeometryProbe", errorText
        Exit Function
    End If
    On Error Resume Next
    Application.EnableCancelKey = xlDisabled
    mCancelled = False
    ReleaseStatus
    If Not wb Is Nothing Then wb.Close SaveChanges:=False
    If VarType(oldStatus) = vbBoolean Then
        Application.StatusBar = False
    Else
        Application.StatusBar = oldStatus
    End If
    If Not previousBook Is Nothing Then previousBook.Activate
    Application.EnableCancelKey = oldCancel
    On Error GoTo 0
    If errorNo <> 0 Then Err.Raise errorNo, "SLC_TransactionGeometryProbe", errorText
    If Application.Workbooks.Count <> booksBefore Then Err.Raise 5, , "Geometry cleanup left a workbook"
End Function
'@
    $injected+="`n"+$probe
    $mutated=$true
    $module.DeleteLines(1,$module.CountOfLines)
    $module.AddFromString($injected)
    foreach($caseName in @('replacement-tail','comparison-tail','output-tail','staged-status-error',
        'api-unavailable-replacement','api-unavailable-comparison','api-interruption-replacement','api-interruption-comparison','geometry-normalization')) {
        $activeCase=$caseName
        if($caseName -eq 'geometry-normalization') {
            $answer=[string]$Excel.Run($qualified+'SLC_TransactionGeometryProbe')
        } else {
            $answer=[string]$Excel.Run($qualified+'SLC_CancellationTransactionProbe',$caseName)
        }
        $pattern='^PASS\|'+[regex]::Escape($caseName)+'\|([1-9][0-9]*)$'
        if($answer -notmatch $pattern){throw ('Unexpected probe result: '+$answer)}
        $checks.Add([ordered]@{id=$caseName;status='PASS';assertions=[int]$Matches[1];evidenceLayer='memory-only deterministic probe';nativeEsc=$false})
    }
    $activeCase=$null
} catch {
    # Preserve the original probe failure before any restoration/report work.
    $errorText=$_.Exception.Message
    $errorDetails=$_.Exception.ToString()
    $failureStack=$_.ScriptStackTrace
    $failedCase=$activeCase
} finally {
    if($mutated) {
        try {
            $module.DeleteLines(1,$module.CountOfLines)
            $module.AddFromString($original)
            $actual=[string]$module.Lines(1,$module.CountOfLines)
            if(-not (Compare-ProbeModule $actual $original)){throw 'Original module restoration comparison failed.'}
            # This was clean on entry; never suppress pre-existing dirty edits.
            # Running an unchanged public function also checks restored compilation.
            $restoredVersion=[string]$Excel.Run($qualified+'SLC_ReleaseVersion')
            if([string]::IsNullOrWhiteSpace($restoredVersion)){throw 'Restored module did not execute.'}
            $book.Saved=$savedBefore
            $restored=$true
        } catch {
            $restoreError=$_.Exception.Message
        }
    }
    try {
        $hashAfter=Get-ProbeSharedHash $expected
    } catch {
        if($null -eq $restoreError){$restoreError='Cannot verify add-in disk hash: '+$_.Exception.Message}
    }
    foreach($value in @($module,$component,$project,$book)){
        try{Release-ProbeCom $value}catch{$cleanupErrors.Add($_.Exception.Message)}
    }
    # Windows PowerShell 5.1 does not reliably adapt ordered dictionary keys
    # for Measure-Object -Property. Read each verified numeric value directly.
    [int]$assertionTotal=0
    foreach($check in $checks){$assertionTotal += [int]$check.assertions}
    $passed=($null -eq $errorText -and $null -eq $restoreError -and $cleanupErrors.Count -eq 0 -and $restored -and $checks.Count -eq 9 -and $hashBefore -ceq $hashAfter)
    [ordered]@{
        status=if($passed){'PASS'}else{'FAIL'}
        nativeEscVerified=$false
        apiPolicyBlockReproduced=$false
        scope='Memory-only deterministic cancellation, synthetic API errors, rollback, coordinates and normalization; no keyboard/UI or actual policy-block proof.'
        ownedPid=$OwnedPid
        checks=@($checks.ToArray())
        assertions=$assertionTotal
        originalModuleRestored=$restored
        initiallySaved=$savedBefore
        diskSha256Before=$hashBefore
        diskSha256After=$hashAfter
        diskUnchanged=($hashBefore -ceq $hashAfter)
        error=$errorText
        errorDetails=$errorDetails
        failureStack=$failureStack
        failedCase=$failedCase
        restorationError=$restoreError
        cleanupErrors=@($cleanupErrors.ToArray())
        requiresHostPostExitHashCheck=$true
    } | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $output -Encoding UTF8
}
if($null -ne $restoreError){throw ('PROBE RESTORATION FAILED: '+$restoreError)}
if($null -ne $errorText){throw $errorText}
if($cleanupErrors.Count -gt 0){throw ('PROBE COM CLEANUP FAILED: '+($cleanupErrors -join '; '))}
if(-not $restored -or $hashBefore -cne $hashAfter){throw 'Probe restoration/hash verification failed.'}
Write-Output 'PASS: deterministic memory-only cancellation/rollback and geometry probes; native Esc is not verified.'
