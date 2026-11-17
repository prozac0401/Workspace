using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;
using ExcelPasswordSafe.Crypto;

internal static class PackageGuardTests
{
    private const string MainNamespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    private const string Strict = "http://purl.oclc.org/ooxml/spreadsheetml/main";
    private const string Office = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/";
    private const string StrictOffice = "http://purl.oclc.org/ooxml/officeDocument/relationships/";
    private const string Package = "http://schemas.openxmlformats.org/package/2006/relationships";
    private const string Bad = "PackageValidationFailed";
    private static int count;
    private static string Relationship(string id, string type, string target, string mode)
    { return "<Relationship Id='" + id + "' Type='" + type + "' Target='" + target + "'" + (mode == null ? "" : " TargetMode='" + mode + "'") + "/>"; }
    private static Dictionary<string, string> Fixture(bool strict, bool macro, bool unusual)
    {
        string office = strict ? StrictOffice : Office, main = strict ? Strict : MainNamespace;
        string book = unusual ? "custom/book.xml" : "xl/workbook.xml", sheet = unusual ? "data/sheet.xml" : "xl/worksheets/sheet1.xml";
        string bookRels = unusual ? "custom/_rels/book.xml.rels" : "xl/_rels/workbook.xml.rels";
        return new Dictionary<string, string> {
            { "[Content_Types].xml", "<Types xmlns='http://schemas.openxmlformats.org/package/2006/content-types'><Default Extension='rels' ContentType='application/vnd.openxmlformats-package.relationships+xml'/><Default Extension='xml' ContentType='application/xml'/><Default Extension='bin' ContentType='application/octet-stream'/><Override PartName='/" + book + "' ContentType='" + (macro ? "application/vnd.ms-excel.sheet.macroEnabled.main+xml" : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml") + "'/><Override PartName='/" + sheet + "' ContentType='application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml'/></Types>" },
            { "_rels/.rels", "<Relationships xmlns='" + Package + "'>" + Relationship("r1", office + "officeDocument", book, null) + "</Relationships>" },
            { book, "<workbook xmlns='" + main + "' xmlns:r='" + office.TrimEnd('/') + "'><sheets><sheet name='한글' sheetId='1' r:id='r1'/></sheets></workbook>" },
            { bookRels, "<Relationships xmlns='" + Package + "'>" + Relationship("r1", office + "worksheet", unusual ? "../data/sheet.xml" : "worksheets/sheet1.xml", null) + "</Relationships>" },
            { sheet, "<worksheet xmlns='" + main + "'><sheetData/></worksheet>" }
        };
    }
    private static byte[] Zip(Dictionary<string, string> files, string duplicate)
    {
        using (var buffer = new MemoryStream())
        {
            using (var archive = new ZipArchive(buffer, ZipArchiveMode.Create, true))
            {
                foreach (var file in files) using (var writer = new StreamWriter(archive.CreateEntry(file.Key).Open(), new UTF8Encoding(false))) writer.Write(file.Value);
                if (duplicate != null) using (var writer = new StreamWriter(archive.CreateEntry(duplicate).Open())) writer.Write("duplicate");
            }
            return buffer.ToArray();
        }
    }
    private static void Check(string name, byte[] bytes, string extension, string expected)
    {
        byte[] original = (byte[])bytes.Clone();
        string actual = PackageGuard.Validate(bytes, extension);
        if (actual != expected) throw new Exception(name + ": expected " + (expected ?? "PASS") + ", got " + (actual ?? "PASS"));
        for (int i = 0; i < bytes.Length; i++) if (bytes[i] != original[i]) throw new Exception(name + ": input mutated");
        count++; Console.WriteLine("PASS " + name);
    }
    private static void Check(string name, Dictionary<string, string> files, string expected) { Check(name, Zip(files, null), ".xlsx", expected); }
    private static void Type(Dictionary<string,string> files, string path, string type)
    { files["[Content_Types].xml"] = files["[Content_Types].xml"].Replace("</Types>", "<Override PartName='/" + path + "' ContentType='" + type + "'/></Types>"); }
    private static void RootRel(Dictionary<string,string> files, string relation)
    { files["_rels/.rels"] = files["_rels/.rels"].Replace("</Relationships>", relation + "</Relationships>"); }
    private static int Find(byte[] bytes, uint magic)
    { for (int i = 0; i < bytes.Length - 4; i++) if (BitConverter.ToUInt32(bytes, i) == magic) return i; throw new Exception("test ZIP signature missing"); }
    private static void Put(byte[] bytes, int offset, uint value) { Array.Copy(BitConverter.GetBytes(value), 0, bytes, offset, 4); }
    private static void Sharing(string attributes, string expected)
    {
        var files = Fixture(false, false, false);
        files["xl/workbook.xml"] = files["xl/workbook.xml"].Replace("<sheets>", "<fileSharing " + attributes + "/><sheets>");
        Check("sharing " + attributes, files, expected);
    }
    public static int MainEntry(string[] args)
    {
        try
        {
            Check("Transitional", Fixture(false, false, false), null);
            Check("Strict", Fixture(true, false, false), null);
            Check("nonstandard workbook part and parent relationship", Fixture(false, false, true), null);
            Check("XLSM without VBA is legal", Zip(Fixture(false, true, false), null), ".xlsm", null);
            Check("extension mismatch", Zip(Fixture(false, true, false), null), ".xlsx", "UnsupportedOrMismatchedFormat");
            Check("unsupported extension", Zip(Fixture(false, false, false), null), ".xlsb", "UnsupportedOrMismatchedFormat");
            var files = Fixture(false, true, false); files["xl/vbaProject.bin"] = "preserve opaque VBA"; Type(files, "xl/vbaProject.bin", "application/vnd.ms-office.vbaProject");
            Check("unsigned VBA retained", Zip(files, null), ".xlsm", null);
            Check("VBA in xlsx", Zip(files, null), ".xlsx", "UnsupportedOrMismatchedFormat");
            foreach (string variant in new[] { "", "Agile", "V3" })
            {
                files = Fixture(false, true, false); files["odd/sign.bin"] = "opaque"; Type(files, "odd/sign.bin", "application/vnd.ms-office.vbaProjectSignature" + variant);
                Check("VBA signature " + variant, Zip(files, null), ".xlsm", "SignedWorkbookUnsupported");
            }
            files = Fixture(false, false, false); files["custom/sign.xml"] = "<sig/>";
            RootRel(files, Relationship("sig", "http://schemas.openxmlformats.org/package/2006/relationships/digital-signature/origin", "custom/sign.xml", null));
            Check("OPC signature relocated", files, "SignedWorkbookUnsupported");
            foreach (string feature in new[] { "revisionHeaders", "revisionLog", "userNames" })
            {
                files = Fixture(false, false, false); files["history.xml"] = "<history/>"; RootRel(files, Relationship("h", Office + feature, "history.xml", null));
                Check("shared " + feature, files, "SharedWorkbookUnsupported");
            }
            foreach (string feature in new[] { "xlMacrosheet", "xlIntlMacrosheet" })
            {
                files = Fixture(false, false, false); files["macro.xml"] = "<macro/>"; RootRel(files, Relationship("m", "http://schemas.microsoft.com/office/2006/relationships/" + feature, "macro.xml", null));
                Check(feature, files, "Excel4MacroSheetUnsupported");
            }
            Sharing("readOnlyRecommended='1' userName='Tester'", null);
            foreach (string attr in new[] { "reservationPassword", "algorithmName", "hashValue", "saltValue", "spinCount" }) Sharing(attr + "='1'", "WriteReservedUnsupported");
            files = Fixture(false, false, false); files["xl/workbook.xml"] = files["xl/workbook.xml"].Replace("<sheets>", "<mc:AlternateContent xmlns:mc='http://schemas.openxmlformats.org/markup-compatibility/2006'><mc:Fallback><fileSharing reservationPassword='1234'/></mc:Fallback></mc:AlternateContent><sheets>");
            Check("write reservation in compatibility wrapper", files, "WriteReservedUnsupported");
            files = Fixture(false, false, false); files["xl/sharedStrings.xml"] = "<sst xmlns='" + MainNamespace + "'/>";
            Check("sharedStrings is not shared workbook", files, null);
            files = Fixture(false, false, false); RootRel(files, Relationship("ext", Office + "externalLinkPath", "https://does-not-exist.invalid/a.xlsx", "External"));
            Check("external relationship never resolved", files, null);
            files = Fixture(false, false, false); files["_rels/.rels"] = files["_rels/.rels"].Replace("Target='xl/workbook.xml'", "Target='https://does-not-exist.invalid/book.xml' TargetMode='External'");
            Check("external workbook main rejected", files, Bad);
            files = Fixture(false, false, false); RootRel(files, Relationship("other", Office + "officeDocument", "xl/workbook.xml", null)); Check("duplicate main", files, Bad);
            files = Fixture(false, false, false); RootRel(files, Relationship("r1", Office + "hyperlink", "https://example.invalid/", "External")); Check("duplicate relationship ID", files, Bad);
            files = Fixture(false, false, false); files["xl/_rels/workbook.xml.rels"] = files["xl/_rels/workbook.xml.rels"].Replace("worksheets/sheet1.xml", "../../../outside.xml"); Check("relationship traversal", files, Bad);
            files = Fixture(false, false, false); files["../outside.xml"] = "x"; Check("entry traversal", files, Bad);
            files = Fixture(false, false, false); files["xl/%2e%2e/evil.xml"] = "x"; Check("encoded traversal", files, Bad);
            Check("duplicate ZIP entry", Zip(Fixture(false, false, false), "xl/workbook.xml"), ".xlsx", Bad);
            Check("case alias ZIP entry", Zip(Fixture(false, false, false), "XL/WORKBOOK.XML"), ".xlsx", Bad);
            Check("percent alias ZIP entry", Zip(Fixture(false, false, false), "xl/%77orkbook.xml"), ".xlsx", Bad);
            files = Fixture(false, false, false); files.Remove("xl/worksheets/sheet1.xml"); Check("missing sheet target", files, Bad);
            files = Fixture(false, false, false); files["xl/workbook.xml"] = "<workbook>"; Check("malformed XML", files, Bad);
            files = Fixture(false, false, false); files["xl/workbook.xml"] = "<!DOCTYPE workbook [<!ENTITY ext SYSTEM 'file:///C:/not-read'>]>" + files["xl/workbook.xml"]; Check("DTD prohibited", files, Bad);
            files = Fixture(false, false, false); files["xl/workbook.xml"] = files["xl/workbook.xml"].Replace(MainNamespace, "urn:wrong"); Check("wrong workbook namespace", files, Bad);
            files = Fixture(false, false, false); files["xl/workbook.xml"] = files["xl/workbook.xml"].Replace("r:id='r1'", "r:id='missing'"); Check("missing sheet relationship", files, Bad);
            byte[] zip = Zip(Fixture(false, false, false), null); Array.Resize(ref zip, zip.Length - 1); Check("truncated ZIP", zip, ".xlsx", Bad);
            zip = Zip(Fixture(false, false, false), null); int central = Find(zip, 0x02014b50); zip[central + 16] ^= 1; Check("central local CRC disagreement", zip, ".xlsx", Bad);
            zip = Zip(Fixture(false, false, false), null); central = Find(zip, 0x02014b50); Put(zip, central + 16, 0); Put(zip, 14, 0); Check("stream CRC corrupt", zip, ".xlsx", Bad);
            zip = Zip(Fixture(false, false, false), null); central = Find(zip, 0x02014b50); Put(zip, central + 24, 256U * 1024 * 1024 + 1); Put(zip, 22, 256U * 1024 * 1024 + 1); Check("expanded budget", zip, ".xlsx", Bad);
            files = Fixture(false, false, false); files["xl/workbook.xml"] = files["xl/workbook.xml"].Replace("<sheets>", "<!--" + new string('a', 16 * 1024 * 1024) + "--><sheets>"); Check("metadata budget", files, Bad);
            Check("input budget before parser", new byte[64 * 1024 * 1024 + 1], ".xlsx", "PackageResourceLimit");
            foreach (string fixture in new[] { "picture_ooxml.xlsx", "picture_vba.xlsm" })
                Check("upstream " + fixture, File.ReadAllBytes(Path.Combine(args[0], fixture)), Path.GetExtension(fixture), null);
            Console.WriteLine("PASS total=" + count); return 0;
        }
        catch (Exception exception) { Console.Error.WriteLine(exception.Message); return 1; }
    }
    public static int Main(string[] args) { return MainEntry(args); }
}
