#nullable disable
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Xml;

namespace ExcelPasswordSafe.Crypto
{
    // Read-only eligibility/structure guard, not an Excel schema validator.
    // The caller encrypts the original bytes; this class never saves a package.
    internal static class PackageGuard
    {
        private const int MaxInput = 64 * 1024 * 1024;
        private const long MaxExpanded = 256L * 1024 * 1024;
        private const int MaxMetadata = 16 * 1024 * 1024;
        private const int MaxEntries = 10000;
        private const string TypesNs = "http://schemas.openxmlformats.org/package/2006/content-types";
        private const string RelsNs = "http://schemas.openxmlformats.org/package/2006/relationships";
        private const string MainNs = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
        private const string StrictNs = "http://purl.oclc.org/ooxml/spreadsheetml/main";
        private const string OfficeRels = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/";
        private const string StrictRels = "http://purl.oclc.org/ooxml/officeDocument/relationships/";
        private static readonly uint[] CrcTable = MakeCrcTable();

        internal static string Validate(byte[] packageBytes, string extension)
        {
            if (packageBytes == null || packageBytes.Length == 0) return "PackageValidationFailed";
            // Only this pre-parser limit may be mapped to COM fallback.
            if (packageBytes.Length > MaxInput) return "PackageResourceLimit";
            if (!String.Equals(extension, ".xlsx", StringComparison.OrdinalIgnoreCase) &&
                !String.Equals(extension, ".xlsm", StringComparison.OrdinalIgnoreCase)) return "UnsupportedOrMismatchedFormat";
            try { return Inspect(packageBytes, extension); }
            catch (InvalidDataException) { return "PackageValidationFailed"; }
            catch (XmlException) { return "PackageValidationFailed"; }
            catch (ArgumentException) { return "PackageValidationFailed"; }
            catch (OverflowException) { return "PackageValidationFailed"; }
            catch (IOException) { return "PackageValidationFailed"; }
        }

        private sealed class ZipInfo
        {
            internal uint Crc, Compressed, Expanded;
            internal long Start, End;
        }
        private sealed class Relation
        {
            internal string Type, Target;
            internal bool External;
        }
        private static void Require(bool ok) { if (!ok) throw new InvalidDataException("Invalid OOXML package"); }
        private static ushort U16(byte[] b, int p) { Require(p >= 0 && p <= b.Length - 2); return (ushort)(b[p] | b[p + 1] << 8); }
        private static uint U32(byte[] b, int p) { return (uint)(U16(b, p) | ((uint)U16(b, p + 2) << 16)); }

        // Check the central/local records and CRC ourselves: Framework ZipArchive
        // does not promise CRC validation when an entry is read.
        private static List<ZipInfo> ReadDirectory(byte[] b)
        {
            int end = -1;
            for (int p = b.Length - 22; p >= Math.Max(0, b.Length - 65557); p--)
                if (U32(b, p) == 0x06054b50 && p + 22 + U16(b, p + 20) == b.Length) { end = p; break; }
            Require(end >= 0 && U16(b, end + 4) == 0 && U16(b, end + 6) == 0);
            int count = U16(b, end + 10);
            Require(count > 0 && count <= MaxEntries && U16(b, end + 8) == count);
            long directory = U32(b, end + 16), size = U32(b, end + 12);
            Require(directory + size == end && directory >= 0);
            var result = new List<ZipInfo>();
            int current = checked((int)directory);
            long expanded = 0;
            for (int i = 0; i < count; i++)
            {
                Require(U32(b, current) == 0x02014b50 && current + 46 <= end);
                int flags = U16(b, current + 8), method = U16(b, current + 10);
                Require((flags & ~0x080e) == 0 && (method == 0 || method == 8));
                int nameSize = U16(b, current + 28), extraSize = U16(b, current + 30), commentSize = U16(b, current + 32);
                Require(nameSize > 0 && U16(b, current + 34) == 0);
                int next = checked(current + 46 + nameSize + extraSize + commentSize);
                Require(next <= end);
                long local = U32(b, current + 42);
                Require(local < directory && local <= Int32.MaxValue);
                int lp = (int)local;
                Require(U32(b, lp) == 0x04034b50 && U16(b, lp + 6) == flags && U16(b, lp + 8) == method);
                Require(U16(b, lp + 26) == nameSize);
                for (int j = 0; j < nameSize; j++) Require(lp + 30 + j < directory && b[lp + 30 + j] == b[current + 46 + j]);
                var item = new ZipInfo { Crc = U32(b, current + 16), Compressed = U32(b, current + 20), Expanded = U32(b, current + 24), Start = local };
                long data = local + 30 + nameSize + U16(b, lp + 28);
                item.End = data + item.Compressed;
                Require(item.End <= directory && data <= item.End);
                if ((flags & 8) == 0)
                    Require(U32(b, lp + 14) == item.Crc && U32(b, lp + 18) == item.Compressed && U32(b, lp + 22) == item.Expanded);
                else
                {
                    int dp = checked((int)item.End);
                    if (U32(b, dp) == 0x08074b50) dp += 4;
                    Require(dp + 12 <= directory && U32(b, dp) == item.Crc && U32(b, dp + 4) == item.Compressed && U32(b, dp + 8) == item.Expanded);
                    item.End = dp + 12;
                }
                expanded += item.Expanded;
                Require(expanded <= MaxExpanded);
                result.Add(item); current = next;
            }
            Require(current == end);
            var ranges = new List<ZipInfo>(result); ranges.Sort((a, c) => a.Start.CompareTo(c.Start));
            long previous = 0;
            foreach (var item in ranges) { Require(item.Start == previous); previous = item.End; }
            Require(previous == directory); // no prefixed executable, overlaps, hidden local entries or unexplained gaps
            return result;
        }

        private static string PartName(string name)
        {
            Require(!String.IsNullOrEmpty(name) && !name.StartsWith("/", StringComparison.Ordinal));
            string[] segments = name.Split('/');
            for (int i = 0; i < segments.Length; i++)
            {
                string raw = segments[i];
                for (int j = 0; j < raw.Length; j++) if (raw[j] == '%')
                { Require(j + 2 < raw.Length && Uri.IsHexDigit(raw[j + 1]) && Uri.IsHexDigit(raw[j + 2])); j += 2; }
                string value = Uri.UnescapeDataString(raw);
                Require(value.Length > 0 && value != "." && value != ".." && value.IndexOfAny(new[] { '/', '\\', ':', '?', '#' }) < 0);
                foreach (char c in value) Require(!Char.IsControl(c) && c != '\0');
                segments[i] = value;
            }
            return String.Join("/", segments);
        }
        private static string ResolveTarget(string source, string target)
        {
            Require(!String.IsNullOrEmpty(target) && target.IndexOfAny(new[] { '\\', ':', '?', '#' }) < 0 && !target.StartsWith("//", StringComparison.Ordinal));
            var parts = new List<string>();
            if (!target.StartsWith("/", StringComparison.Ordinal) && source.LastIndexOf('/') >= 0)
                parts.AddRange(source.Substring(0, source.LastIndexOf('/')).Split('/'));
            foreach (string piece in target.TrimStart('/').Split('/'))
            {
                if (piece == ".") continue;
                if (piece == "..") { Require(parts.Count > 0); parts.RemoveAt(parts.Count - 1); }
                else parts.Add(PartName(piece));
            }
            Require(parts.Count > 0); return String.Join("/", parts);
        }
        private static string RelationshipSource(string name)
        {
            if (String.Equals(name, "_rels/.rels", StringComparison.OrdinalIgnoreCase)) return "";
            int index = name.LastIndexOf("/_rels/", StringComparison.OrdinalIgnoreCase);
            Require(index >= 0 && name.EndsWith(".rels", StringComparison.OrdinalIgnoreCase));
            return name.Substring(0, index + 1) + name.Substring(index + 7, name.Length - index - 12);
        }
        private static string Feature(string value)
        {
            string v = value.ToLowerInvariant();
            if (v.Contains("digital-signature") || v.Contains("vbaprojectsignature")) return "SignedWorkbookUnsupported";
            if (v.Contains("revisionheaders") || v.Contains("revisionlog") || v.EndsWith("/usernames") || v.Contains("spreadsheetml.usernames")) return "SharedWorkbookUnsupported";
            if (v.Contains("macrosheet") || v.Contains("intlmacrosheet")) return "Excel4MacroSheetUnsupported";
            return null;
        }
        private static bool OfficeType(string type, string suffix) { return type == OfficeRels + suffix || type == StrictRels + suffix; }
        private static XmlDocument Metadata(ZipArchiveEntry entry, HashSet<string> charged, ref long budget)
        {
            if (charged.Add(entry.FullName)) { budget += entry.Length; Require(budget <= MaxMetadata); }
            Require(entry.Length <= MaxMetadata);
            byte[] bytes;
            using (var input = entry.Open()) using (var memory = new MemoryStream()) { input.CopyTo(memory); bytes = memory.ToArray(); }
            var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = MaxMetadata, MaxCharactersFromEntities = 0 };
            using (var stream = new MemoryStream(bytes)) using (var reader = XmlReader.Create(stream, settings))
                while (reader.Read()) Require(reader.Depth <= 64);
            var document = new XmlDocument { XmlResolver = null };
            using (var stream = new MemoryStream(bytes)) using (var reader = XmlReader.Create(stream, settings)) document.Load(reader);
            Require(document.DocumentElement != null); return document;
        }
        private static IEnumerable<XmlElement> Children(XmlElement element)
        {
            foreach (XmlNode node in element.ChildNodes)
                if (node is XmlElement) yield return (XmlElement)node;
                else Require(node.NodeType == XmlNodeType.Comment || node.NodeType == XmlNodeType.Whitespace || node.NodeType == XmlNodeType.SignificantWhitespace || (node.NodeType == XmlNodeType.Text && String.IsNullOrWhiteSpace(node.Value)));
        }

        private static string Inspect(byte[] bytes, string extension)
        {
            List<ZipInfo> infos = ReadDirectory(bytes);
            using (var memory = new MemoryStream(bytes, false)) using (var zip = new ZipArchive(memory, ZipArchiveMode.Read, false))
            {
                Require(zip.Entries.Count == infos.Count);
                var entries = new Dictionary<string, ZipArchiveEntry>(StringComparer.OrdinalIgnoreCase);
                var allNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                byte[] buffer = new byte[65536];
                for (int i = 0; i < zip.Entries.Count; i++)
                {
                    ZipArchiveEntry entry = zip.Entries[i]; ZipInfo info = infos[i];
                    bool directory = entry.FullName.EndsWith("/", StringComparison.Ordinal);
                    string name = PartName(directory ? entry.FullName.Substring(0, entry.FullName.Length - 1) : entry.FullName);
                    Require(allNames.Add(name) && entry.Length == info.Expanded && entry.CompressedLength == info.Compressed);
                    uint crc = 0xffffffff; long read = 0;
                    using (var input = entry.Open())
                    {
                        int n; while ((n = input.Read(buffer, 0, buffer.Length)) > 0)
                        {
                            read += n; Require(read <= info.Expanded);
                            for (int j = 0; j < n; j++) crc = CrcTable[(crc ^ buffer[j]) & 255] ^ (crc >> 8);
                        }
                    }
                    Require(read == info.Expanded && (crc ^ 0xffffffff) == info.Crc);
                    if (directory) Require(read == 0); else entries.Add(name, entry);
                }
                Require(entries.ContainsKey("[Content_Types].xml") && entries.ContainsKey("_rels/.rels"));
                long metadataBytes = 0; var charged = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                XmlElement types = Metadata(entries["[Content_Types].xml"], charged, ref metadataBytes).DocumentElement;
                Require(types.LocalName == "Types" && types.NamespaceURI == TypesNs);
                var defaults = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                var overrides = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                string excluded = null;
                foreach (XmlElement type in Children(types))
                {
                    Require(type.NamespaceURI == TypesNs && !String.IsNullOrEmpty(type.GetAttribute("ContentType")));
                    string value = type.GetAttribute("ContentType"); excluded = excluded ?? Feature(value);
                    if (type.LocalName == "Default")
                    {
                        string ext = type.GetAttribute("Extension"); Require(ext.Length > 0 && ext.IndexOfAny(new[] { '.', '/', '\\', ':', '%' }) < 0 && !defaults.ContainsKey(ext)); defaults.Add(ext, value);
                    }
                    else
                    {
                        Require(type.LocalName == "Override" && type.GetAttribute("PartName").StartsWith("/", StringComparison.Ordinal));
                        string name = PartName(type.GetAttribute("PartName").Substring(1)); Require(entries.ContainsKey(name) && !overrides.ContainsKey(name)); overrides.Add(name, value);
                    }
                }
                var contentTypes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (string name in entries.Keys)
                {
                    if (name == "[Content_Types].xml") continue;
                    string type;
                    if (!overrides.TryGetValue(name, out type))
                    {
                        int dot = name.LastIndexOf('.'); Require(dot > name.LastIndexOf('/') && defaults.TryGetValue(name.Substring(dot + 1), out type));
                    }
                    contentTypes.Add(name, type);
                    if (name.StartsWith("_xmlsignatures/", StringComparison.OrdinalIgnoreCase) || name.IndexOf("vbaProjectSignature", StringComparison.OrdinalIgnoreCase) >= 0) excluded = "SignedWorkbookUnsupported";
                }
                var relations = new Dictionary<string, Dictionary<string, Relation>>(StringComparer.OrdinalIgnoreCase);
                foreach (var pair in entries)
                {
                    if (!pair.Key.EndsWith(".rels", StringComparison.OrdinalIgnoreCase)) continue;
                    Require(contentTypes[pair.Key] == "application/vnd.openxmlformats-package.relationships+xml");
                    string source = RelationshipSource(pair.Key); Require(source == "" || entries.ContainsKey(source));
                    Require(!relations.ContainsKey(source));
                    var map = new Dictionary<string, Relation>(StringComparer.Ordinal);
                    XmlElement root = Metadata(pair.Value, charged, ref metadataBytes).DocumentElement;
                    Require(root.LocalName == "Relationships" && root.NamespaceURI == RelsNs);
                    foreach (XmlElement element in Children(root))
                    {
                        string id = element.GetAttribute("Id"), type = element.GetAttribute("Type"), mode = element.GetAttribute("TargetMode"), target = element.GetAttribute("Target");
                        Require(element.LocalName == "Relationship" && element.NamespaceURI == RelsNs && id.Length > 0 && type.Length > 0 && target.Length > 0 && !map.ContainsKey(id));
                        Require(mode == "" || mode == "Internal" || mode == "External");
                        bool external = mode == "External";
                        if (!external) { target = ResolveTarget(source, target); Require(entries.ContainsKey(target)); }
                        map.Add(id, new Relation { Type = type, Target = target, External = external }); excluded = excluded ?? Feature(type);
                    }
                    relations.Add(source, map);
                }
                Require(relations.ContainsKey("")); string workbook = null;
                foreach (Relation relation in relations[""].Values) if (OfficeType(relation.Type, "officeDocument"))
                { Require(workbook == null && !relation.External); workbook = relation.Target; }
                Require(workbook != null);
                string wanted = String.Equals(extension, ".xlsx", StringComparison.OrdinalIgnoreCase)
                    ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml" : "application/vnd.ms-excel.sheet.macroEnabled.main+xml";
                if (contentTypes[workbook] != wanted) return "UnsupportedOrMismatchedFormat";
                XmlElement book = Metadata(entries[workbook], charged, ref metadataBytes).DocumentElement;
                Require(book.LocalName == "workbook" && (book.NamespaceURI == MainNs || book.NamespaceURI == StrictNs));
                if (String.Equals(extension, ".xlsx", StringComparison.OrdinalIgnoreCase))
                    foreach (string type in contentTypes.Values) if (type.IndexOf("vbaProject", StringComparison.OrdinalIgnoreCase) >= 0) return "UnsupportedOrMismatchedFormat";
                if (excluded != null) return excluded;
                // Markup-compatibility wrappers must not hide a write reservation.
                foreach (XmlElement sharing in book.GetElementsByTagName("fileSharing", book.NamespaceURI))
                    foreach (string attribute in new[] { "reservationPassword", "algorithmName", "hashValue", "saltValue", "spinCount" })
                        if (sharing.HasAttribute(attribute)) return "WriteReservedUnsupported";
                XmlElement sheets = null;
                foreach (XmlElement element in Children(book))
                {
                    if (element.NamespaceURI != book.NamespaceURI) continue; // preserve unknown extension markup unchanged
                    if (element.LocalName == "sheets") { Require(sheets == null); sheets = element; }
                }
                Require(sheets != null && relations.ContainsKey(workbook));
                int sheetCount = 0; var sheetIds = new HashSet<string>(StringComparer.Ordinal); var sheetNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (XmlElement sheet in Children(sheets))
                {
                    Require(sheet.NamespaceURI == book.NamespaceURI && sheet.LocalName == "sheet");
                    string id = sheet.GetAttribute("id", book.NamespaceURI == StrictNs ? StrictRels.TrimEnd('/') : OfficeRels.TrimEnd('/'));
                    uint sheetId; Require(UInt32.TryParse(sheet.GetAttribute("sheetId"), out sheetId) && sheetId > 0 && sheetIds.Add(sheetId.ToString()) && sheet.GetAttribute("name").Length > 0 && sheetNames.Add(sheet.GetAttribute("name")));
                    Relation relation; Require(relations[workbook].TryGetValue(id, out relation) && !relation.External);
                    Require(OfficeType(relation.Type, "worksheet") || OfficeType(relation.Type, "chartsheet") || OfficeType(relation.Type, "dialogsheet")); sheetCount++;
                }
                Require(sheetCount > 0); return null;
            }
        }
        private static uint[] MakeCrcTable()
        {
            var table = new uint[256];
            for (uint i = 0; i < table.Length; i++) { uint c = i; for (int j = 0; j < 8; j++) c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1; table[i] = c; }
            return table;
        }
    }
}
