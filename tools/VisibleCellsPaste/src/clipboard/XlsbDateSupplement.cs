using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using System.Xml.Linq;

namespace VisibleCellsPaste
{
    // A supplemental clipboard reader, not an XLSB workbook opener. Formula tokens and styles are never executed.
    internal static class XlsbDateSupplement
    {
        private const string RelNamespace = "http://schemas.openxmlformats.org/package/2006/relationships";
        private const string OfficeRelationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/";
        private sealed class Rectangle
        {
            internal int FirstRow, LastRow, FirstColumn, LastColumn;
            internal int Rows { get { return LastRow - FirstRow + 1; } }
            internal int Columns { get { return LastColumn - FirstColumn + 1; } }
            internal bool Contains(int row, int column) { return row >= FirstRow && row <= LastRow && column >= FirstColumn && column <= LastColumn; }
        }
        private sealed class Record
        {
            internal byte[] Bytes; internal int Type, Start, Length;
            internal int End { get { return Start + Length; } }
            internal void Need(int relative, int count) { Require(relative >= 0 && count >= 0 && relative + (long)count <= Length); }
            internal int I32(int offset) { Need(offset, 4); return BitConverter.ToInt32(Bytes, Start + offset); }
            internal uint U32(int offset) { Need(offset, 4); return BitConverter.ToUInt32(Bytes, Start + offset); }
            internal int U16(int offset) { Need(offset, 2); return BitConverter.ToUInt16(Bytes, Start + offset); }
            internal byte Byte(int offset) { Need(offset, 1); return Bytes[Start + offset]; }
            internal string Text(ref int offset, int max)
            {
                uint count = U32(offset); offset += 4; Require(count <= max); Need(offset, (int)count * 2);
                string value;
                try { value = new UnicodeEncoding(false, false, true).GetString(Bytes, Start + offset, (int)count * 2); }
                catch (DecoderFallbackException) { throw Invalid(); }
                offset += (int)count * 2; return value;
            }
        }
        internal static CellValue[] Complete(byte[] package, int rows, int columns, CellValue[] xml, bool[] dates)
        {
            Require(rows > 0 && columns > 0 && (rows == 1 || columns == 1) && (long)rows * columns <= Limits.MaxItems);
            Require(xml != null && dates != null && xml.Length == rows * columns && dates.Length == xml.Length);
            var zip = new BoundedZip(package);
            Require(Relationship(zip.Read("_rels/.rels"), null, "officeDocument") == "xl/workbook.bin");
            Rectangle origin = null; string sheetId = null; bool began = false, ended = false, inSheets = false;
            foreach (Record record in Records(zip.Read("xl/workbook.bin")))
            {
                Require(!ended);
                if (!began) { Require(record.Type == 131 && record.Length == 0); began = true; continue; }
                switch (record.Type)
                {
                    case 131: throw Invalid();
                    case 132: Require(record.Length == 0 && !inSheets); ended = true; break;
                    case 143: Require(!inSheets); inSheets = true; break;
                    case 144: Require(inSheets); inSheets = false; break;
                    case 156:
                        Require(inSheets && sheetId == null && record.Length >= 16 && record.I32(0) == 0 && record.U32(4) >= 1 && record.U32(4) <= 65535);
                        int offset = 8; sheetId = record.Text(ref offset, 255); string sheetName = record.Text(ref offset, 31);
                        Require(sheetId.Length > 0 && sheetName.Length > 0 && offset == record.Length); break;
                    case 549: Require(origin == null); origin = ReadRectangle(record); break;
                }
            }
            Require(began && ended && origin != null && sheetId != null && (origin.Rows == 1 || origin.Columns == 1));
            // BrtOleSize establishes the copy origin. Filtered copies can have a larger original extent;
            // native cell coordinates are compacted at this origin, and every XML position is cross-checked below.
            Require(origin.Rows >= rows && origin.Columns >= columns && (columns == 1 ? origin.Columns == 1 : origin.Rows == 1));
            var expected = new Rectangle { FirstRow = origin.FirstRow, LastRow = origin.FirstRow + rows - 1,
                FirstColumn = origin.FirstColumn, LastColumn = origin.FirstColumn + columns - 1 };
            Require(expected.LastRow < Limits.ExcelRows && expected.LastColumn < Limits.ExcelColumns);
            byte[] relationships = zip.Read("xl/_rels/workbook.bin.rels");
            string sheetTarget = Relationship(relationships, sheetId, "worksheet");
            Require(sheetTarget == "worksheets/sheet1.bin");
            foreach (string name in zip.Names)
                if (name.StartsWith("xl/worksheets/", StringComparison.Ordinal) && name.EndsWith(".bin", StringComparison.Ordinal) && name != "xl/worksheets/binaryIndex1.bin") Require(name == "xl/worksheets/sheet1.bin");
            List<string> strings = new List<string>();
            if (zip.Contains("xl/sharedStrings.bin"))
            {
                Require(Relationship(relationships, null, "sharedStrings") == "sharedStrings.bin");
                strings = ReadStrings(zip.Read("xl/sharedStrings.bin"));
            }
            CellValue[] native = ReadSheet(zip.Read("xl/worksheets/sheet1.bin"), expected, strings);
            var result = (CellValue[])xml.Clone();
            for (int i = 0; i < xml.Length; i++)
            {
                if (dates[i]) { Require(native[i].Kind == CellValueKind.Number); result[i] = native[i]; }
                else Require(xml[i].Equals(native[i]));
            }
            return result;
        }
        private static CellValue[] ReadSheet(byte[] bytes, Rectangle expected, List<string> strings)
        {
            var result = new CellValue[expected.Rows * expected.Columns]; var seen = new bool[result.Length];
            for (int i = 0; i < result.Length; i++) result[i] = CellValue.Empty();
            bool began = false, ended = false, data = false, finished = false; Rectangle dimension = null;
            int row = -1, column = -1, alternativeDepth = 0, rowCount = 0; Record rowHeader = null;
            foreach (Record record in Records(bytes))
            {
                Require(!ended);
                if (!began) { Require(record.Type == 129 && record.Length == 0); began = true; continue; }
                switch (record.Type)
                {
                    case 129: throw Invalid();
                    case 130: Require(record.Length == 0 && finished && !data && alternativeDepth == 0); ended = true; continue;
                    case 148:
                        Require(!data && !finished && dimension == null); dimension = ReadRectangle(record);
                        // Used cells may omit leading/trailing empty cells, but may never escape the declared copied shape.
                        Require(expected.Contains(dimension.FirstRow, dimension.FirstColumn) && expected.Contains(dimension.LastRow, dimension.LastColumn)); continue;
                    case 145: Require(!data && !finished && dimension != null && record.Length == 0); data = true; continue;
                    case 146: Require(data && record.Length == 0 && alternativeDepth == 0); data = false; finished = true; continue;
                    case 37: Require(alternativeDepth == 0); alternativeDepth = 1; continue;
                    case 38: Require(alternativeDepth == 1 && record.Length == 0); alternativeDepth = 0; continue;
                }
                if (!data)
                {
                    Require(!(record.Type >= 0 && record.Type <= 11) && record.Type != 62);
                    continue; // Presentation-only records outside the cell table cannot supply values.
                }
                if (record.Type == 1024) { Require(record.Length == 2 && alternativeDepth == 1); continue; } // row descent metadata
                Require(alternativeDepth == 0);
                if (record.Type == 0)
                {
                    Require(record.Length >= 17 && record.U32(13) <= 16 && record.Length == 17 + record.U32(13) * 8);
                    int nextRow = record.I32(0); Require(nextRow > row && nextRow >= expected.FirstRow && nextRow <= expected.LastRow && ++rowCount <= expected.Rows);
                    row = nextRow; column = -1; rowHeader = record;
                    int lastSpan = -1;
                    for (int span = 0; span < record.U32(13); span++)
                    {
                        int first = record.I32(17 + span * 8), last = record.I32(21 + span * 8);
                        Require(first >= 0 && last >= first && last < Limits.ExcelColumns && first > lastSpan); lastSpan = last;
                    }
                    continue;
                }
                Require((record.Type >= 1 && record.Type <= 11) || record.Type == 62);
                Require(rowHeader != null && record.Length >= 8);
                int nextColumn = record.I32(0); Require(nextColumn > column && expected.Contains(row, nextColumn));
                bool inSpan = false;
                for (int span = 0; span < rowHeader.U32(13); span++)
                    if (nextColumn >= rowHeader.I32(17 + span * 8) && nextColumn <= rowHeader.I32(21 + span * 8)) inSpan = true;
                Require(inSpan); column = nextColumn;
                int index = expected.Rows == 1 ? column - expected.FirstColumn : row - expected.FirstRow;
                Require(!seen[index]); seen[index] = true; result[index] = ReadCell(record, strings);
            }
            Require(began && ended && finished && dimension != null); return result;
        }
        private static CellValue ReadCell(Record r, List<string> strings)
        {
            int offset = 8; CellValue value;
            switch (r.Type)
            {
                case 1: value = CellValue.Empty(); break;
                case 2:
                    uint rk = r.U32(offset); offset += 4;
                    double compact = (rk & 2) != 0 ? ((int)rk >> 2) : BitConverter.Int64BitsToDouble((long)(rk & 0xfffffffc) << 32);
                    if ((rk & 1) != 0) compact /= 100.0;
                    Require(!Double.IsNaN(compact) && !Double.IsInfinity(compact)); value = CellValue.Number(compact); break;
                case 5: case 9:
                    r.Need(offset, 8); double number = BitConverter.ToDouble(r.Bytes, r.Start + offset); offset += 8;
                    Require(!Double.IsNaN(number) && !Double.IsInfinity(number)); value = CellValue.Number(number); break;
                case 3: case 11: value = Error(r.Byte(offset++)); break;
                case 4: case 10: int boolean = r.Byte(offset++); Require(boolean == 0 || boolean == 1); value = CellValue.Boolean(boolean == 1); break;
                case 6: case 8: value = CellValue.Text(r.Text(ref offset, 32767)); break;
                case 7: uint index = r.U32(offset); offset += 4; Require(index < strings.Count); value = CellValue.Text(strings[(int)index]); break;
                case 62: value = CellValue.Text(RichText(r, ref offset)); break;
                default: throw Invalid();
            }
            if (r.Type >= 8 && r.Type <= 11)
            {
                r.Need(offset, 2); offset += 2; uint tokens = r.U32(offset); offset += 4;
                Require(tokens > 0 && tokens <= 16384); r.Need(offset, (int)tokens); offset += (int)tokens;
                uint extra = r.U32(offset); offset += 4; Require(extra <= Limits.MaxPayloadBytes); r.Need(offset, (int)extra); offset += (int)extra;
            }
            Require(offset == r.Length); return value;
        }
        private static List<string> ReadStrings(byte[] bytes)
        {
            var strings = new List<string>(); bool begin = false, end = false; int unique = -1;
            foreach (Record r in Records(bytes))
            {
                Require(!end);
                if (!begin) { Require(r.Type == 159 && r.Length == 8 && r.U32(4) <= r.U32(0) && r.U32(0) <= Limits.MaxItems); unique = (int)r.U32(4); begin = true; continue; }
                if (r.Type == 160) { Require(r.Length == 0 && strings.Count == unique); end = true; continue; }
                Require(r.Type == 19 && strings.Count < unique); int offset = 0; strings.Add(RichText(r, ref offset)); Require(offset == r.Length);
            }
            Require(begin && end); return strings;
        }
        private static string RichText(Record r, ref int offset)
        {
            int flags = r.Byte(offset++); string value = r.Text(ref offset, 32767);
            if ((flags & 1) != 0)
            {
                uint count = r.U32(offset); offset += 4; Require(count <= 32767); int last = -1;
                for (int i = 0; i < count; i++) { int position = r.U16(offset); r.Need(offset, 4); offset += 4; Require(position > last && position < value.Length); last = position; }
            }
            if ((flags & 2) != 0)
            {
                string phonetic = r.Text(ref offset, 32767); uint count = r.U32(offset); offset += 4; Require(count <= 32767);
                int previousPhonetic = -1, previousText = -1, total = 0;
                for (int i = 0; i < count; i++)
                {
                    r.Need(offset, 10); int first = r.U16(offset), text = r.U16(offset + 2), length = r.U16(offset + 4); offset += 10;
                    Require(first > previousPhonetic && first < phonetic.Length && text > previousText && text < value.Length && text + length <= value.Length);
                    total += length; Require(total <= value.Length); previousPhonetic = first; previousText = text;
                }
            }
            return value;
        }
        private static CellValue Error(byte error)
        {
            int code;
            switch (error) { case 0: code = 2000; break; case 7: code = 2007; break; case 15: code = 2015; break; case 23: code = 2023; break; case 29: code = 2029; break; case 36: code = 2036; break; case 42: code = 2042; break; case 43: code = 2043; break; default: throw Invalid(); }
            return CellValue.Error(code);
        }
        private static Rectangle ReadRectangle(Record record)
        {
            Require(record.Length == 16); var r = new Rectangle { FirstRow = record.I32(0), LastRow = record.I32(4), FirstColumn = record.I32(8), LastColumn = record.I32(12) };
            Require(r.FirstRow >= 0 && r.LastRow >= r.FirstRow && r.LastRow < Limits.ExcelRows && r.FirstColumn >= 0 && r.LastColumn >= r.FirstColumn && r.LastColumn < Limits.ExcelColumns); return r;
        }
        private static IEnumerable<Record> Records(byte[] bytes)
        {
            int offset = 0, count = 0;
            while (offset < bytes.Length)
            {
                Require(++count <= Limits.MaxItems * 8 + 4096);
                int first = bytes[offset++], type = first & 127;
                if ((first & 128) != 0) { Require(offset < bytes.Length); int second = bytes[offset++]; Require((second & 128) == 0); type += second << 7; Require(type >= 128); }
                int size = 0, shift = 0, part;
                do { Require(offset < bytes.Length && shift < 28); part = bytes[offset++]; size |= (part & 127) << shift; shift += 7; } while ((part & 128) != 0 && shift < 28);
                Require(size >= 0 && offset + (long)size <= bytes.Length);
                var r = new Record { Bytes = bytes, Start = offset, Length = size, Type = type }; offset += size; yield return r;
            }
        }
        private static string Relationship(byte[] bytes, string id, string type)
        {
            XDocument doc;
            try
            {
                using (var stream = new MemoryStream(bytes, false))
                using (XmlReader reader = XmlReader.Create(stream, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = Limits.MaxPayloadBytes })) doc = XDocument.Load(reader);
            }
            catch (XmlException) { throw Invalid(); }
            XNamespace ns = RelNamespace; Require(doc.Root != null && doc.Root.Name == ns + "Relationships");
            string found = null; var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (XElement relation in doc.Root.Elements())
            {
                Require(relation.Name == ns + "Relationship"); string actualId = (string)relation.Attribute("Id"); Require(actualId != null && ids.Add(actualId));
                if ((id == null || id == actualId) && (string)relation.Attribute("Type") == OfficeRelationships + type)
                {
                    Require(found == null && ((string)relation.Attribute("TargetMode") == null || (string)relation.Attribute("TargetMode") == "Internal"));
                    found = (string)relation.Attribute("Target"); Require(found != null);
                }
            }
            Require(found != null); return found;
        }
        private static void Require(bool condition) { if (!condition) throw Invalid(); }
        private static ValidationException Invalid() { return new ValidationException("VCP-NATIVE-MAPPING", "날짜의 원래 Excel 숫자 값과 복사한 셀 위치를 일치시킬 수 없습니다. 추측하여 변환하지 않았습니다. 변경된 셀은 없습니다."); }
    }
}
