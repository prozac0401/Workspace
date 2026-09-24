using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using System.Xml.Linq;

namespace VisibleCellsPaste
{
    public static class SpreadsheetXmlParser
    {
        private static readonly XNamespace Ss = "urn:schemas-microsoft-com:office:spreadsheet";
        private static readonly Dictionary<string, int> Errors = new Dictionary<string, int>(StringComparer.Ordinal)
        {
            { "#NULL!", 2000 }, { "#DIV/0!", 2007 }, { "#VALUE!", 2015 }, { "#REF!", 2023 },
            { "#NAME?", 2029 }, { "#NUM!", 2036 }, { "#N/A", 2042 }, { "#GETTING_DATA", 2043 }
        };

        public static ClipboardSnapshot Parse(byte[] bytes, uint sequence, string evidence)
        { return ParseInternal(bytes, null, sequence, evidence); }

        public static ClipboardSnapshot ParseWithNative(byte[] bytes, byte[] biff12, uint sequence, string evidence)
        {
            if (biff12 == null || bytes == null || (long)bytes.Length + biff12.Length > Limits.MaxPayloadBytes)
                throw Fail("LIMIT", "읽을 클립보드 데이터 합계는 최대 32 MiB입니다.");
            return ParseInternal(bytes, biff12, sequence, evidence);
        }

        private static ClipboardSnapshot ParseInternal(byte[] bytes, byte[] biff12, uint sequence, string evidence)
        {
            if (bytes == null || bytes.Length == 0 || bytes.Length > Limits.MaxPayloadBytes)
                throw Fail("LIMIT", "복사 데이터의 크기가 허용 범위를 벗어납니다.");
            try
            {
                // HGLOBAL-backed clipboard text includes a terminal NUL. Remove only complete trailing NUL code units.
                int length = bytes.Length;
                bool wide = (length >= 2 && ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff) || (bytes[0] == '<' && bytes[1] == 0) || (bytes[0] == 0 && bytes[1] == '<')));
                if (wide)
                {
                    if (length % 2 != 0) throw Fail("ENCODING", "복사 데이터의 문자 인코딩을 확인할 수 없습니다.");
                    while (length >= 2 && bytes[length - 1] == 0 && bytes[length - 2] == 0) length -= 2;
                }
                else while (length > 0 && bytes[length - 1] == 0) length--;
                var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null,
                    MaxCharactersInDocument = Limits.MaxPayloadBytes, IgnoreWhitespace = false, IgnoreComments = true };
                XDocument document;
                using (var stream = new MemoryStream(bytes, 0, length, false))
                using (XmlReader reader = XmlReader.Create(stream, settings)) document = XDocument.Load(reader, LoadOptions.PreserveWhitespace);
                if (document.Root == null || document.Root.Name != Ss + "Workbook") throw Fail("FORMAT", "Excel XML 복사 형식이 아닙니다.");
                List<XElement> sheets = document.Root.Elements(Ss + "Worksheet").Take(2).ToList();
                if (sheets.Count != 1) throw Fail("SHEETS", "하나의 원본 워크시트만 지원합니다.");
                List<XElement> tables = sheets[0].Elements(Ss + "Table").Take(2).ToList();
                if (tables.Count != 1) throw Fail("TABLE", "복사한 셀 범위를 정확히 확인할 수 없습니다.");
                XElement table = tables[0];
                int rows = RequiredPositive(table, "ExpandedRowCount", Limits.MaxItems);
                int columns = RequiredPositive(table, "ExpandedColumnCount", Limits.ExcelColumns);
                if (rows != 1 && columns != 1) throw Fail("SHAPE", "원본은 한 행 또는 한 열이어야 합니다.");
                if ((long)rows * columns > Limits.MaxItems) throw Fail("LIMIT", "복사 항목은 최대 50,000개입니다.");
                if (OptionalPositive(table, "TopCell", 1, Limits.ExcelRows) != 1 || OptionalPositive(table, "LeftCell", 1, Limits.ExcelColumns) != 1)
                    throw Fail("OFFSET", "복사 범위의 시작 위치를 확정할 수 없습니다.");
                int previousMetadataColumn = 0;
                foreach (XElement column in table.Elements(Ss + "Column"))
                {
                    int firstColumn = OptionalPositive(column, "Index", previousMetadataColumn + 1, columns);
                    int span = 0;
                    XAttribute spanAttribute = column.Attribute(Ss + "Span");
                    if (spanAttribute != null && (!Int32.TryParse(spanAttribute.Value, NumberStyles.None, CultureInfo.InvariantCulture, out span) || span < 0))
                        throw Fail("INDEX-LIMIT", "복사 열 서식의 범위를 확인할 수 없습니다.");
                    if (firstColumn <= previousMetadataColumn || (long)firstColumn + span > columns)
                        throw Fail("INDEX-LIMIT", "복사 열 서식이 선언한 범위를 벗어납니다.");
                    // Column Span repeats formatting only; it never expands or synthesizes source data.
                    previousMetadataColumn = firstColumn + span;
                }
                if (table.Elements().Any(delegate(XElement child) { return child.Name != Ss + "Column" && child.Name != Ss + "Row"; }))
                    throw Fail("TABLE-CONTENT", "복사 표의 구조를 확정할 수 없습니다.");
                int count = rows * columns;
                var items = new CellValue[count];
                var dates = new bool[count];
                for (int i = 0; i < count; i++) items[i] = CellValue.Empty();
                int previousRow = 0;
                foreach (XElement row in table.Elements(Ss + "Row"))
                {
                    int rowIndex = OptionalPositive(row, "Index", previousRow + 1, rows);
                    if (rowIndex <= previousRow || rowIndex > rows) throw Fail("INDEX", "복사 데이터의 행 인덱스가 일치하지 않습니다.");
                    RejectNonzero(row, "Span");
                    previousRow = rowIndex;
                    if (row.Elements().Any(delegate(XElement child) { return child.Name != Ss + "Cell"; }))
                        throw Fail("ROW-CONTENT", "복사 행의 구조를 확정할 수 없습니다.");
                    int previousColumn = 0;
                    foreach (XElement cell in row.Elements(Ss + "Cell"))
                    {
                        int columnIndex = OptionalPositive(cell, "Index", previousColumn + 1, columns);
                        if (columnIndex <= previousColumn || columnIndex > columns) throw Fail("INDEX", "복사 데이터의 열 인덱스가 일치하지 않습니다.");
                        previousColumn = columnIndex;
                        RejectNonzero(cell, "MergeAcross"); RejectNonzero(cell, "MergeDown");
                        int index = rows == 1 ? columnIndex - 1 : rowIndex - 1;
                        items[index] = ParseCell(cell, biff12 != null, out dates[index]);
                    }
                }
                bool hasDates = dates.Any(delegate(bool date) { return date; });
                if (hasDates) items = XlsbDateSupplement.Complete(biff12, rows, columns, items, dates);
                return new ClipboardSnapshot(hasDates ? "XML Spreadsheet + Biff12" : "XML Spreadsheet", sequence, rows, columns, true, items,
                    "SpreadsheetML ExpandedRowCount/ExpandedColumnCount; sparse Index preserves all empty positions. " +
                    (hasDates ? "XLSB BrtOleSize/cell coordinates cross-checked against all XML positions; raw numeric dates, no calendar conversion. " : "") + (evidence ?? ""));
            }
            catch (ValidationException) { throw; }
            catch (XmlException ex) { throw new ValidationException("VCP-XML-INVALID", "복사 데이터 XML을 안전하게 해석할 수 없습니다. 변경된 셀은 없습니다.", ex); }
            catch (ArgumentException ex) { throw new ValidationException("VCP-XML-INVALID", "복사 데이터를 안전하게 해석할 수 없습니다. 변경된 셀은 없습니다.", ex); }
        }

        private static CellValue ParseCell(XElement cell, bool nativeAvailable, out bool isDate)
        {
            isDate = false;
            if (cell.Elements().Any(delegate(XElement child) { return child.Name != Ss + "Data" && child.Name != Ss + "Comment" && child.Name != Ss + "NamedCell"; }))
                throw Fail("CELL-CONTENT", "복사 셀의 구조를 확정할 수 없습니다.");
            List<XElement> data = cell.Elements(Ss + "Data").Take(2).ToList();
            if (data.Count == 0)
            {
                if (cell.Attribute(Ss + "Formula") != null) throw Fail("FORMULA-RESULT", "원본 수식의 계산 결과가 복사 데이터에 없습니다.");
                return CellValue.Empty();
            }
            if (data.Count != 1) throw Fail("DATA", "원본 셀의 데이터가 중복되었습니다.");
            XAttribute type = data[0].Attribute(Ss + "Type");
            if (type == null) throw Fail("TYPE", "원본 셀의 자료형을 확인할 수 없습니다.");
            if (data[0].Descendants().Any(delegate(XElement child) { return child.Name.NamespaceName != "http://www.w3.org/TR/REC-html40" || (child.Name.LocalName != "Font" && child.Name.LocalName != "B" && child.Name.LocalName != "I" && child.Name.LocalName != "U" && child.Name.LocalName != "S" && child.Name.LocalName != "Sub" && child.Name.LocalName != "Sup"); }))
                throw Fail("RICH-TEXT", "복사 셀 내부 구조를 손실 없이 해석할 수 없습니다.");
            string value = data[0].Value;
            switch (type.Value)
            {
                case "String":
                    if (value.Length > 32767) throw Fail("STRING-LIMIT", "Excel 셀 문자열 길이를 초과한 입력입니다.");
                    return CellValue.Text(value);
                case "Number":
                    double number;
                    if (!Double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out number) || Double.IsInfinity(number) || Double.IsNaN(number))
                        throw Fail("NUMBER", "원본 숫자를 정확히 해석할 수 없습니다.");
                    return CellValue.Number(number);
                case "Boolean":
                    if (value == "1" || value == "true") return CellValue.Boolean(true);
                    if (value == "0" || value == "false") return CellValue.Boolean(false);
                    throw Fail("BOOLEAN", "원본 논리 값을 정확히 해석할 수 없습니다.");
                case "Error":
                    int error;
                    if (!Errors.TryGetValue(value, out error)) throw Fail("ERROR-TYPE", "이 Excel 오류 종류는 아직 지원하지 않습니다.");
                    return CellValue.Error(error);
                case "DateTime":
                    if (nativeAvailable) { isDate = true; return CellValue.Empty(); }
                    throw Fail("DATE-SERIAL", "이 날짜 복사 형식에는 원래 Excel 숫자 값이 없어 지원하지 않습니다. 원본 날짜 체계를 추측하여 변환하지 않았습니다.");
                default: throw Fail("TYPE", "지원하지 않는 원본 자료형입니다.");
            }
        }

        private static void RejectNonzero(XElement element, string name)
        {
            XAttribute attr = element.Attribute(Ss + name);
            if (attr == null) return;
            int number;
            if (!Int32.TryParse(attr.Value, NumberStyles.None, CultureInfo.InvariantCulture, out number) || number != 0)
                throw Fail(name.StartsWith("Merge", StringComparison.Ordinal) ? "MERGED" : "SPAN", "병합 셀 또는 모호한 확장 범위는 지원하지 않습니다.");
        }
        private static int RequiredPositive(XElement element, string name, int limit)
        {
            XAttribute attr = element.Attribute(Ss + name);
            if (attr == null) throw Fail("DIMENSIONS", "복사한 셀의 전체 행·열 개수를 확인할 수 없습니다.");
            return ParsePositive(attr.Value, limit);
        }
        private static int OptionalPositive(XElement element, string name, int fallback, int limit)
        {
            XAttribute attr = element.Attribute(Ss + name);
            return attr == null ? fallback : ParsePositive(attr.Value, limit);
        }
        private static int ParsePositive(string value, int limit)
        {
            int result;
            if (!Int32.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out result) || result < 1 || result > limit)
                throw Fail("INDEX-LIMIT", "복사 데이터의 차원·인덱스가 허용 범위를 벗어납니다.");
            return result;
        }
        private static ValidationException Fail(string code, string text) { return new ValidationException("VCP-XML-" + code, text + " 변경된 셀은 없습니다."); }
    }
}
