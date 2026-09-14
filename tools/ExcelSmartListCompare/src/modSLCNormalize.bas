Attribute VB_Name = "modSLCNormalize"
Option Explicit

Public Function SLC_Normalize(ByVal v As Variant) As String
    Dim s As String
    Dim p As Long
    Dim ok As Boolean
    Dim numCanonical As String

    If IsError(v) Or IsEmpty(v) Or IsNull(v) Then Exit Function

    ' Numeric Excel values: normalize independently from cell formatting.
    If IsNumeric(v) And VarType(v) <> vbString And VarType(v) <> vbBoolean Then
        s = NumericValueToInvariantText(v)
        numCanonical = CanonicalizeNumericText(s, ok)
        If ok Then
            SLC_Normalize = "#n:" & numCanonical
            Exit Function
        End If
    End If

    s = CStr(v)
    s = NormalizeWhitespace(s)
    s = SafeNarrow(s)
    s = NormalizeWhitespace(s)

    If Len(s) = 0 Then Exit Function

    ' mailto:user@domain -> user@domain
    If LCase$(Left$(s, 7)) = "mailto:" Then
        s = Mid$(s, 8)
        s = NormalizeWhitespace(s)
    End If

    ' E-mail comparison rule: compare only the local part before @.
    p = InStr(1, s, "@", vbBinaryCompare)
    If p > 1 And p < Len(s) Then
        s = Left$(s, p - 1)
        s = NormalizeWhitespace(s)
    End If

    s = LCase$(s)

    ' Numeric text is normalized unless it contains an explicit significant leading zero.
    If Not HasSignificantLeadingZero(s) Then
        numCanonical = CanonicalizeNumericText(s, ok)
        If ok Then
            SLC_Normalize = "#n:" & numCanonical
            Exit Function
        End If
    End If

    SLC_Normalize = "#t:" & s
End Function

Private Function NormalizeWhitespace(ByVal s As String) As String
    On Error Resume Next
    s = Replace(s, ChrW(&HA0), " ")      ' NBSP
    s = Replace(s, ChrW(&H3000), " ")    ' Ideographic space
    s = Replace(s, ChrW(&H200B), "")     ' Zero-width space
    s = Replace(s, ChrW(&HFEFF), "")     ' BOM / zero-width NBSP
    On Error GoTo 0

    s = Replace(s, vbTab, " ")
    s = Replace(s, vbCr, " ")
    s = Replace(s, vbLf, " ")

    Do While InStr(1, s, "  ", vbBinaryCompare) > 0
        s = Replace(s, "  ", " ")
    Loop

    NormalizeWhitespace = Trim$(s)
End Function

Private Function SafeNarrow(ByVal s As String) As String
    Dim i As Long, code As Long, ch As String, result As String
    For i = 1 To Len(s)
        ch = Mid$(s, i, 1)
        code = AscW(ch)
        If code < 0 Then code = code + 65536
        If code >= &HFF01& And code <= &HFF5E& Then ch = ChrW(code - &HFEE0&)
        result = result & ch
    Next i
    SafeNarrow = result
End Function

Private Function NumericValueToInvariantText(ByVal v As Variant) As String
    ' Str uses a period decimal separator. Range.Value2 numeric values are Double.
    NumericValueToInvariantText = Trim$(Str$(CDbl(v)))
End Function

Private Function HasSignificantLeadingZero(ByVal s As String) As Boolean
    Dim t As String
    Dim ePos As Long, dotPos As Long
    Dim intPart As String

    t = Trim$(s)
    If Len(t) = 0 Then Exit Function

    If Left$(t, 1) = "+" Or Left$(t, 1) = "-" Then t = Mid$(t, 2)
    If Len(t) = 0 Then Exit Function

    ePos = InStr(1, t, "e", vbTextCompare)
    If ePos > 0 Then t = Left$(t, ePos - 1)

    dotPos = InStr(1, t, ".", vbBinaryCompare)
    If dotPos > 0 Then
        intPart = Left$(t, dotPos - 1)
    Else
        intPart = t
    End If

    If Len(intPart) > 1 And Left$(intPart, 1) = "0" Then
        HasSignificantLeadingZero = True
    End If
End Function

Private Function CanonicalizeNumericText(ByVal inputText As String, ByRef ok As Boolean) As String
    Dim s As String, mantissa As String, expText As String
    Dim signText As String, expSign As Long, exponent As Long
    Dim ePos1 As Long, ePos2 As Long, ePos As Long
    Dim dotPos As Long
    Dim intPart As String, fracPart As String, digits As String
    Dim decimalPos As Long
    Dim result As String, resultInt As String, resultFrac As String
    Dim i As Long, ch As String

    ok = False
    s = Trim$(inputText)
    If Len(s) = 0 Then Exit Function

    If Left$(s, 1) = "+" Or Left$(s, 1) = "-" Then
        If Left$(s, 1) = "-" Then signText = "-"
        s = Mid$(s, 2)
        If Len(s) = 0 Then Exit Function
    End If

    ePos1 = InStr(1, s, "e", vbBinaryCompare)
    ePos2 = InStr(1, s, "E", vbBinaryCompare)
    If ePos1 > 0 And ePos2 > 0 Then
        ePos = IIf(ePos1 < ePos2, ePos1, ePos2)
    ElseIf ePos1 > 0 Then
        ePos = ePos1
    Else
        ePos = ePos2
    End If

    If ePos > 0 Then
        If InStr(ePos + 1, s, "e", vbTextCompare) > 0 Then Exit Function
        mantissa = Left$(s, ePos - 1)
        expText = Mid$(s, ePos + 1)
        If Len(expText) = 0 Then Exit Function

        expSign = 1
        If Left$(expText, 1) = "+" Or Left$(expText, 1) = "-" Then
            If Left$(expText, 1) = "-" Then expSign = -1
            expText = Mid$(expText, 2)
        End If
        If Len(expText) = 0 Then Exit Function
        If Len(expText) > 4 Then Exit Function

        For i = 1 To Len(expText)
            ch = Mid$(expText, i, 1)
            If ch < "0" Or ch > "9" Then Exit Function
        Next i

        exponent = CLng(expText) * expSign
        If Abs(exponent) > 1000 Then Exit Function
    Else
        mantissa = s
        exponent = 0
    End If

    dotPos = InStr(1, mantissa, ".", vbBinaryCompare)
    If dotPos > 0 Then
        If InStr(dotPos + 1, mantissa, ".", vbBinaryCompare) > 0 Then Exit Function
        intPart = Left$(mantissa, dotPos - 1)
        fracPart = Mid$(mantissa, dotPos + 1)
    Else
        intPart = mantissa
        fracPart = vbNullString
    End If

    If Len(intPart) = 0 And Len(fracPart) = 0 Then Exit Function

    For i = 1 To Len(intPart)
        ch = Mid$(intPart, i, 1)
        If ch < "0" Or ch > "9" Then Exit Function
    Next i
    For i = 1 To Len(fracPart)
        ch = Mid$(fracPart, i, 1)
        If ch < "0" Or ch > "9" Then Exit Function
    Next i

    digits = intPart & fracPart
    If Len(digits) = 0 Then Exit Function

    decimalPos = Len(intPart) + exponent

    If decimalPos <= 0 Then
        result = "0." & String$(-decimalPos, "0") & digits
    ElseIf decimalPos >= Len(digits) Then
        result = digits & String$(decimalPos - Len(digits), "0")
    Else
        result = Left$(digits, decimalPos) & "." & Mid$(digits, decimalPos + 1)
    End If

    dotPos = InStr(1, result, ".", vbBinaryCompare)
    If dotPos > 0 Then
        resultInt = Left$(result, dotPos - 1)
        resultFrac = Mid$(result, dotPos + 1)
    Else
        resultInt = result
        resultFrac = vbNullString
    End If

    Do While Len(resultInt) > 1 And Left$(resultInt, 1) = "0"
        resultInt = Mid$(resultInt, 2)
    Loop
    If Len(resultInt) = 0 Then resultInt = "0"

    Do While Len(resultFrac) > 0 And Right$(resultFrac, 1) = "0"
        resultFrac = Left$(resultFrac, Len(resultFrac) - 1)
    Loop

    If Len(resultFrac) > 0 Then
        result = resultInt & "." & resultFrac
    Else
        result = resultInt
    End If

    If result = "0" Then signText = vbNullString

    CanonicalizeNumericText = signText & result
    ok = True
End Function


Public Function SLC_U(ByVal codeUnits As String) As String
    Dim tokens As Variant, token As Variant, code As Long, result As String
    tokens = Split(codeUnits, " ")
    For Each token In tokens
        If Len(CStr(token)) > 0 Then
            code = CLng("&H" & CStr(token))
            If code > 32767 Then code = code - 65536
            result = result & ChrW(code)
        End If
    Next token
    SLC_U = result
End Function

Public Sub SLC_NormalizeTests()
    CheckEqual SLC_Normalize(123), SLC_Normalize("123"), "number/text"
    CheckEqual SLC_Normalize(123), SLC_Normalize("123.0"), "decimal zero"
    CheckDifferent SLC_Normalize(123), SLC_Normalize("00123"), "leading zero"
    CheckEqual SLC_Normalize("USER@A.COM"), SLC_Normalize("user@b.com"), "email ID"
    CheckEqual SLC_Normalize("user"), SLC_Normalize("mailto: user@a.com"), "mailto"
    CheckEqual SLC_Normalize(SLC_U("0020 D64D AE38 B3D9 0020")), SLC_Normalize(SLC_U("D64D AE38 B3D9")), "trim"
    CheckDifferent SLC_Normalize(SLC_U("D64D 0020 AE38 B3D9")), SLC_Normalize(SLC_U("D64D AE38 B3D9")), "internal space"
    CheckEqual SLC_Normalize(SLC_U("FF21 FF22 FF23 FF11 FF12 FF13")), SLC_Normalize("abc123"), "fullwidth ASCII"
    CheckEqual SLC_Normalize("1.23e2"), SLC_Normalize(123), "exponent"
    CheckEqual SLC_Normalize("-0.00"), SLC_Normalize(0), "negative zero"
    CheckDifferent SLC_Normalize("1,234"), SLC_Normalize(1234), "comma literal"
    CheckDifferent SLC_Normalize(True), SLC_Normalize(-1), "boolean"
    CheckEqual SLC_Normalize(" " & ChrW(160)), "", "empty normalized"
    CheckEqual SLC_Normalize("9007199254740993"), "#n:9007199254740993", "long text precision"
End Sub

Private Sub CheckEqual(ByVal a As String, ByVal b As String, ByVal label As String)
    If StrComp(a, b, vbBinaryCompare) <> 0 Then Err.Raise vbObjectError + 2199, , label
End Sub

Private Sub CheckDifferent(ByVal a As String, ByVal b As String, ByVal label As String)
    If StrComp(a, b, vbBinaryCompare) = 0 Then Err.Raise vbObjectError + 2199, , label
End Sub
