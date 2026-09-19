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

' Per-list detail budget: 1,200 occurrences + 600 variants + 200 errors.
' Samples are evidence of capture, never a claim that an occurrence is incorrect.
Public OccurrenceSamples As Collection
Public VariantSamples As Collection
Public ErrorSamples As Collection
Public OmittedOccurrences As Long
Public OmittedVariantCandidates As Long
Public OmittedErrors As Long
Private mOccurrenceCounts As Object
Private mVariants As Object
Private Const MAX_OCCURRENCES As Long = 1200
Private Const MAX_VARIANTS As Long = 600
Private Const MAX_ERRORS As Long = 200
Private Const MAX_PER_KEY As Long = 5

Private Sub Class_Initialize()
    Set Counts = CreateObject("Scripting.Dictionary")
    Set Examples = CreateObject("Scripting.Dictionary")
    Set Addresses = CreateObject("Scripting.Dictionary")
    Set mOccurrenceCounts = CreateObject("Scripting.Dictionary")
    Set mVariants = CreateObject("Scripting.Dictionary")
    Counts.CompareMode = vbBinaryCompare
    Examples.CompareMode = vbBinaryCompare
    Addresses.CompareMode = vbBinaryCompare
    mOccurrenceCounts.CompareMode = vbBinaryCompare
    mVariants.CompareMode = vbBinaryCompare
    Set OccurrenceSamples = New Collection
    Set VariantSamples = New Collection
    Set ErrorSamples = New Collection
End Sub

' Call after Counts / Examples / Addresses have been updated for this value.
' This method deliberately does not alter the existing comparison aggregates.
Public Sub AddOccurrence(ByVal key As String, ByVal raw As String, ByVal address As String)
    Dim kept As Long, variants As Object
    If mOccurrenceCounts.Exists(key) Then kept = CLng(mOccurrenceCounts(key))
    If OccurrenceSamples.Count < MAX_OCCURRENCES And kept < MAX_PER_KEY Then
        OccurrenceSamples.Add Array(key, raw, address)
        mOccurrenceCounts(key) = kept + 1
    Else
        OmittedOccurrences = OmittedOccurrences + 1
    End If

    If Not Examples.Exists(key) Then Exit Sub
    If StrComp(CStr(Examples(key)), raw, vbBinaryCompare) = 0 Then Exit Sub
    If mVariants.Exists(key) Then
        Set variants = mVariants(key)
        If variants.Exists(raw) Then Exit Sub
        If variants.Count >= MAX_PER_KEY Then
            OmittedVariantCandidates = OmittedVariantCandidates + 1
            Exit Sub
        End If
    End If
    If VariantSamples.Count >= MAX_VARIANTS Then
        OmittedVariantCandidates = OmittedVariantCandidates + 1
        Exit Sub
    End If
    If variants Is Nothing Then
        Set variants = CreateObject("Scripting.Dictionary")
        variants.CompareMode = vbBinaryCompare
        mVariants.Add key, variants
    End If
    variants.Add raw, True
    VariantSamples.Add Array(key, raw, address)
End Sub

' errorText is a bounded, human-readable error label supplied by the reader.
Public Sub AddError(ByVal address As String, ByVal errorText As String)
    If ErrorSamples.Count < MAX_ERRORS Then
        ErrorSamples.Add Array(address, errorText)
    Else
        OmittedErrors = OmittedErrors + 1
    End If
End Sub
