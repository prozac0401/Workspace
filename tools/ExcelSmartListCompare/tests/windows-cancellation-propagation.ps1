param(
    [Parameter(Mandatory=$true)]$Excel,
    [Parameter(Mandatory=$true)][string]$BeforeSource,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
# Called only from an owned developer session with an installed, loaded add-in
# and existing VBA access. Never save the temporary injected code to the add-in.
# Inject Excel interruption error 18 into the real normalization routine.
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputDirectory){throw 'Use a fresh probe directory.'}
[void](New-Item -ItemType Directory -Path $OutputDirectory)
$current=Join-Path (Split-Path $PSScriptRoot -Parent) 'src/modSLCNormalize.bas'
$probeFunction=@'

Public Function SLC_CancellationProbe() As Long
    Dim value As String
    On Error GoTo Interrupted
    value = SLC_Normalize(" alpha ")
    SLC_CancellationProbe = 0
    Exit Function
Interrupted:
    SLC_CancellationProbe = Err.Number
End Function
'@
$checks=@()
$installed=Join-Path $env:LOCALAPPDATA 'ExcelSmartListCompare/ExcelSmartListCompare.xlam'
$book=$Excel.Workbooks.Item('ExcelSmartListCompare.xlam')
if([string]$book.FullName -ine $installed){throw 'Unexpected loaded add-in.'}
$project=$book.GetType().InvokeMember('VBProject',[Reflection.BindingFlags]::GetProperty,$null,$book,$null)
$component=$project.VBComponents.Item('modSLCNormalize')
$module=$component.CodeModule
$original=[string]$module.Lines(1,$module.CountOfLines)
try {
foreach($case in @(@{name='before';source=$BeforeSource;expected=0},@{name='after';source=$current;expected=18})){
    $source=Get-Content -LiteralPath $case.source -Raw -Encoding ASCII
    $anchor='    s = Replace(s, ChrW(&HA0), " ")'
    if(-not $source.Contains($anchor)){throw 'Fault injection anchor missing.'}
    $source=$source.Replace($anchor,('    Err.Raise 18'+"`r`n"+$anchor))+$probeFunction
    $injected=Join-Path $OutputDirectory ($case.name+'.bas')
    [IO.File]::WriteAllText($injected,$source,[Text.Encoding]::ASCII)
    $module.DeleteLines(1,$module.CountOfLines)
    $module.AddFromString(($source -replace '(?m)^Attribute [^\r\n]+\r?\n',''))
    $actual=[int]$Excel.Run("'ExcelSmartListCompare.xlam'!SLC_CancellationProbe")
    $checks+=@{case=$case.name;expected=$case.expected;actual=$actual;pass=($actual -eq $case.expected)}
    if($actual -ne $case.expected){throw ('Unexpected interruption behavior: '+$case.name+' returned '+$actual)}
}
} finally {
    $module.DeleteLines(1,$module.CountOfLines)
    $module.AddFromString($original)
    $book.Saved=$true
    foreach($obj in @($module,$component,$project,$book)){[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($obj)}
    # The owning host verifies the disk hash after Excel releases its file lock.
}
$checks|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputDirectory 'interruption-propagation.json') -Encoding UTF8
Write-Output 'PASS: original routine swallows error 18; changed routine propagates it to caller.'
