param([Parameter(Mandatory=$true)]$Excel,[Parameter(Mandatory=$true)][string]$OutputPath)
# The owning developer host authorizes temporary VBA access, owns Excel,
# restores access, and verifies the unchanged XLAM hash after Excel exits.
$ErrorActionPreference='Stop'
$book=$Excel.Workbooks.Item('ExcelSmartListCompare.xlam')
$project=$book.GetType().InvokeMember('VBProject',[Reflection.BindingFlags]::GetProperty,$null,$book,$null)
$component=$project.VBComponents.Item('modSLCMain')
$module=$component.CodeModule
$original=[string]$module.Lines(1,$module.CountOfLines)
$originalSaved=[bool]$book.Saved
$report=[ordered]@{status='RUNNING';assertions=0;result=$null;error=$null;rawVbaObservations=@();comAfterMacro=$null;rawSetterControl=$null;comAfterRawSetterControl=$null;comAfterModuleRestore=$null;cleanupErrors=@();testScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash.ToLowerInvariant()}
$primaryFailure=$null
$probe=@'
Public Function SLC_StatusCheckpointTrace(Optional ByVal stage As String = "") As String
    Static trace As String
    Dim value As Variant
    On Error GoTo Failed
    If stage = "begin" Then trace = ""
    If Len(stage) > 0 Then
        value = Application.StatusBar
        trace = trace & stage & vbTab & CStr(VarType(value)) & vbTab & TypeName(value) & vbTab & CStr(value) & vbLf
    End If
    SLC_StatusCheckpointTrace = trace
    Exit Function
Failed:
    trace = trace & stage & vbTab & "-1" & vbTab & "ERROR" & vbTab & CStr(Err.Number) & ": " & Err.Description & vbLf
    SLC_StatusCheckpointTrace = trace
End Function

Public Function SLC_StatusRawSetterControl() As String
    ' Diagnostic control: no SetStatus/ReleaseStatus/PreviousStatus/Checkpoint.
    ' Normal Excel event dispatch can still occur during DoEvents.
    On Error GoTo Failed
    Call SLC_StatusCheckpointTrace("raw-control-before")
    Application.StatusBar = "SLC raw setter control"
    Call SLC_StatusCheckpointTrace("raw-control-after-custom-text")
    Application.StatusBar = False
    Call SLC_StatusCheckpointTrace("raw-control-after-literal-false")
    DoEvents
    Call SLC_StatusCheckpointTrace("raw-control-after-doevents")
    SLC_StatusRawSetterControl = "Diagnostic only; does not classify product restoration"
    Exit Function
Failed:
    SLC_StatusRawSetterControl = "FAIL: raw setter control: " & CStr(Err.Number) & ": " & Err.Description
End Function

Public Function SLC_StatusCheckpointProbe() As String
    Dim oldCancel As Long, answer As String, rawDefaultRestored As Boolean
    Dim cancelSaved As Boolean, failureNumber As Long, failureText As String
    On Error GoTo Failed
    oldCancel = Application.EnableCancelKey
    cancelSaved = True
    Call SLC_StatusCheckpointTrace("begin")
    Application.StatusBar = False
    Call SLC_StatusCheckpointTrace("after-initial-literal-false")
    SetStatus "SLC synthetic processing"
    Call SLC_StatusCheckpointTrace("after-default-setstatus")
    If VarType(mPreviousStatus) <> vbBoolean Then
        SLC_StatusCheckpointProbe = "FAIL: Default status was captured as text"
        Exit Function
    End If
    ReleaseStatus
    Call SLC_StatusCheckpointTrace("after-default-releasestatus")
    rawDefaultRestored = (VarType(Application.StatusBar) = vbBoolean)
    Application.StatusBar = "External synthetic status"
    SetStatus "SLC synthetic processing"
    ReleaseStatus
    Call SLC_StatusCheckpointTrace("after-prior-text-releasestatus")
    If Application.StatusBar <> "External synthetic status" Then
        SLC_StatusCheckpointProbe = "FAIL: Prior status lost"
        Exit Function
    End If
    SetStatus "SLC synthetic processing"
    Application.StatusBar = "External update during processing"
    ReleaseStatus
    Call SLC_StatusCheckpointTrace("after-external-update-releasestatus")
    If Application.StatusBar <> "External update during processing" Then
        SLC_StatusCheckpointProbe = "FAIL: External update lost"
        Exit Function
    End If
    Application.StatusBar = False
    Call SLC_StatusCheckpointTrace("after-final-literal-false")
    Application.EnableCancelKey = xlDisabled
    mStarted = Timer
    mCancelled = False
    Checkpoint
    Call SLC_StatusCheckpointTrace("after-checkpoint")
    If Application.EnableCancelKey <> xlErrorHandler Then
        Application.EnableCancelKey = oldCancel
        SLC_StatusCheckpointProbe = "FAIL: Cancellation handler not rearmed"
        Exit Function
    End If
    Application.EnableCancelKey = oldCancel
    Call SLC_StatusCheckpointTrace("after-cancel-setting-restore")
    ' Inspect the raw property. PreviousStatus intentionally normalizes text
    ' FALSE, so using it here would hide a type-preservation failure.
    If Not rawDefaultRestored Then
        SLC_StatusCheckpointProbe = "FAIL: Default status raw property was not restored as Boolean"
        Exit Function
    End If
    SLC_StatusCheckpointProbe = "PASS: default status, previous text, external update, checkpoint rearm"
    Exit Function
Failed:
    failureNumber = Err.Number
    failureText = Err.Description
    On Error Resume Next
    If cancelSaved Then Application.EnableCancelKey = oldCancel
    Call SLC_StatusCheckpointTrace("probe-caught-error")
    SLC_StatusCheckpointProbe = "FAIL: caught probe error " & CStr(failureNumber) & ": " & failureText
End Function
'@
try {
    $module.AddFromString($probe)
    $result=[string]$Excel.Run("'ExcelSmartListCompare.xlam'!SLC_StatusCheckpointProbe")
    $report.result=$result
    if(-not $result.StartsWith('PASS:')){throw ('Status checkpoint probe returned: '+$result)}
    $report.status='PASS';$report.assertions=4;$report.result=$result
} catch {
    $primaryFailure=$_;$report.status='FAIL';$report.error=$_.Exception.Message
} finally {
    try {
        $value=$Excel.StatusBar
        $report.comAfterMacro=[ordered]@{value=$value;typeName=$value.GetType().FullName}
        try{
            $report.rawSetterControl=[string]$Excel.Run("'ExcelSmartListCompare.xlam'!SLC_StatusRawSetterControl")
            if($report.rawSetterControl.StartsWith('FAIL:')){$report.cleanupErrors+=@($report.rawSetterControl)}
        }
        catch{$report.cleanupErrors+=@('Raw setter diagnostic failed: '+$_.Exception.Message)}
        $value=$Excel.StatusBar
        $report.comAfterRawSetterControl=[ordered]@{value=$value;typeName=$value.GetType().FullName}
        $trace=[string]$Excel.Run("'ExcelSmartListCompare.xlam'!SLC_StatusCheckpointTrace")
        foreach($line in ($trace -split "`n")){
            if(-not $line){continue};$fields=$line -split "`t",4
            if($fields.Count -ne 4){throw 'Malformed VBA status observation.'}
            $report.rawVbaObservations+=@([ordered]@{stage=$fields[0];variantType=[int]$fields[1];typeName=$fields[2];valueText=$fields[3]})
        }
    }catch{$report.cleanupErrors+=@('Could not collect raw status diagnostics: '+$_.Exception.Message)}
    try {
        $module.DeleteLines(1,$module.CountOfLines)
        $module.AddFromString($original)
        $book.Saved=$originalSaved
        $value=$Excel.StatusBar
        $report.comAfterModuleRestore=[ordered]@{value=$value;typeName=$value.GetType().FullName}
    }catch{$report.cleanupErrors+=@('Could not restore probe module: '+$_.Exception.Message)}
    foreach($obj in @($module,$component,$project,$book)){
        try{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($obj)}catch{$report.cleanupErrors+=@('Could not release probe reference: '+$_.Exception.Message)}
    }
    if($report.cleanupErrors.Count){$report.status='FAIL'}
    $report|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $OutputPath -Encoding UTF8
}
if($null -ne $primaryFailure){throw $primaryFailure}
if($report.status -cne 'PASS'){throw 'Status checkpoint diagnostics or cleanup failed.'}
Write-Output $report.result
