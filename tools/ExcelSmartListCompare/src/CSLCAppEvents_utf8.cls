VERSION 1.0 CLASS
BEGIN
  MultiUse = -1
END
Attribute VB_Name = "CSLCAppEvents"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

' Owns no workbook, worksheet, selection, or snapshot references.
Public WithEvents ExcelApp As Excel.Application

Private Sub ExcelApp_WindowActivate(ByVal Wb As Excel.Workbook, ByVal Wn As Excel.Window)
    SLC_RefreshActiveUI
End Sub

Private Sub ExcelApp_SheetBeforeRightClick(ByVal Sh As Object, ByVal Target As Excel.Range, Cancel As Boolean)
    ' Do not read Target, change Selection, or suppress the user's context menu.
    SLC_RefreshActiveUI
End Sub
