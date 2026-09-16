param([Parameter(Mandatory=$true)]$Excel,[Parameter(Mandatory=$true)][string]$OutputPath)
# The owning developer host authorizes temporary VBA access, owns Excel,
# restores access, and verifies the unchanged XLAM hash after Excel exits.
$ErrorActionPreference='Stop'
$book=$Excel.Workbooks.Item('ExcelSmartListCompare.xlam')
$project=$book.GetType().InvokeMember('VBProject',[Reflection.BindingFlags]::GetProperty,$null,$book,$null)
$component=$project.VBComponents.Item('modSLCMain')
$module=$component.CodeModule
$original=[string]$module.Lines(1,$module.CountOfLines)
$probe=@'
Public Function SLC_StatusCheckpointProbe() As String
    Dim oldCancel As Long, answer As String
    Application.StatusBar = False
    SetStatus "SLC synthetic processing"
    If VarType(mPreviousStatus) <> vbBoolean Then Err.Raise 5, , "Default status was captured as text"
    ReleaseStatus
    If VarType(PreviousStatus()) <> vbBoolean Then Err.Raise 5, , "Default status was not restored"
    Application.StatusBar = "External synthetic status"
    SetStatus "SLC synthetic processing"
    ReleaseStatus
    If Application.StatusBar <> "External synthetic status" Then Err.Raise 5, , "Prior status lost"
    SetStatus "SLC synthetic processing"
    Application.StatusBar = "External update during processing"
    ReleaseStatus
    If Application.StatusBar <> "External update during processing" Then Err.Raise 5, , "External update lost"
    Application.StatusBar = False
    oldCancel = Application.EnableCancelKey
    Application.EnableCancelKey = xlDisabled
    mStarted = Timer
    mCancelled = False
    Checkpoint
    If Application.EnableCancelKey <> xlErrorHandler Then Err.Raise 5, , "Cancellation handler not rearmed"
    Application.EnableCancelKey = oldCancel
    SLC_StatusCheckpointProbe = "PASS: default status, previous text, external update, checkpoint rearm"
End Function
'@
try {
    $module.AddFromString($probe)
    $result=[string]$Excel.Run("'ExcelSmartListCompare.xlam'!SLC_StatusCheckpointProbe")
    if(-not $result.StartsWith('PASS:')){throw 'Unexpected probe result.'}
    @{status='PASS';assertions=4;result=$result}|ConvertTo-Json|Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Output $result
} finally {
    $module.DeleteLines(1,$module.CountOfLines)
    $module.AddFromString($original)
    $book.Saved=$true
    foreach($obj in @($module,$component,$project,$book)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($obj)}
}
