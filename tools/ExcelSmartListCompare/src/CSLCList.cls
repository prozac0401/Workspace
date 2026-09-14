VERSION 1.0 CLASS
BEGIN
  MultiUse = -1
END
Attribute VB_Name = "CSLCList"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

' Snapshot: no Workbook/Worksheet/Range references and no disk persistence.
Public Counts As Object
Public Examples As Object
Public Addresses As Object
Public Source As String
Public CapturedAt As Date
Public Total As Long
Public DuplicateExcess As Long
Public BlankCount As Long
Public ErrorCount As Long
Public MetadataCount As Long
Public VisibleCellCount As Long
Public FragmentCount As Long
Public RawCharCount As Long

Private Sub Class_Initialize()
    Set Counts = CreateObject("Scripting.Dictionary")
    Set Examples = CreateObject("Scripting.Dictionary")
    Set Addresses = CreateObject("Scripting.Dictionary")
    Counts.CompareMode = vbBinaryCompare
    Examples.CompareMode = vbBinaryCompare
    Addresses.CompareMode = vbBinaryCompare
End Sub
