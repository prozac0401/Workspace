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

' Snapshot: values only; no Workbook/Worksheet/Range references or disk persistence.
Public Counts As Object
Public Examples As Object
Public Addresses As Object
Public Source As String
Public DisplaySource As String
Public CapturedAt As Date
Public Total As Long
Public DuplicateExcess As Long
Public BlankCount As Long
Public ErrorCount As Long
Public MetadataCount As Long
Public VisibleCellCount As Long
Public FragmentCount As Long
Public RawCharCount As Long
Public CompareFullEmail As Boolean
Public IgnoreCase As Boolean

' Per-list detail budget: 1,200 occurrences + 200 errors. No raw-variant scan.
' Samples are evidence of capture, never a claim that an occurrence is incorrect.
Public OccurrenceSamples As Collection
Public ErrorSamples As Collection
Public OmittedOccurrences As Long
Public OmittedErrors As Long
Private mOccurrenceCounts As Object
Private Const MAX_OCCURRENCES As Long = 1200
Private Const MAX_ERRORS As Long = 200
Private Const MAX_PER_KEY As Long = 5

Private Sub Class_Initialize()
    Set Counts = CreateObject("Scripting.Dictionary")
    Set Examples = CreateObject("Scripting.Dictionary")
    Set Addresses = CreateObject("Scripting.Dictionary")
    Set mOccurrenceCounts = CreateObject("Scripting.Dictionary")
    Counts.CompareMode = vbBinaryCompare
    Examples.CompareMode = vbBinaryCompare
    Addresses.CompareMode = vbBinaryCompare
    mOccurrenceCounts.CompareMode = vbBinaryCompare
    Set OccurrenceSamples = New Collection
    Set ErrorSamples = New Collection
End Sub

' Call after Counts / Examples / Addresses have been updated for this value.
' This method deliberately does not alter the existing comparison aggregates.
Public Sub AddOccurrence(ByVal key As String, ByVal raw As String, ByVal address As String)
    Dim kept As Long
    If mOccurrenceCounts.Exists(key) Then kept = CLng(mOccurrenceCounts(key))
    If OccurrenceSamples.Count < MAX_OCCURRENCES And kept < MAX_PER_KEY Then
        OccurrenceSamples.Add Array(key, raw, address)
        mOccurrenceCounts(key) = kept + 1
    Else
        OmittedOccurrences = OmittedOccurrences + 1
    End If

End Sub

' errorText is a bounded, human-readable error label supplied by the reader.
Public Sub AddError(ByVal address As String, ByVal errorText As String)
    If ErrorSamples.Count < MAX_ERRORS Then
        ErrorSamples.Add Array(address, errorText)
    Else
        OmittedErrors = OmittedErrors + 1
    End If
End Sub
