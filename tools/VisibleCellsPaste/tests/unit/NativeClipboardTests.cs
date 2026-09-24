using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using VisibleCellsPaste;

internal static class NativeClipboardTests
{
    private static int passed, failed;
    private static byte[] Join(params byte[][] values) { return values.SelectMany(x => x).ToArray(); }
    private static byte[] I(int value) { return BitConverter.GetBytes(value); }
    private static byte[] S(string value) { return Join(I(value.Length), Encoding.Unicode.GetBytes(value)); }
    private static byte[] R(int type, params byte[][] value)
    {
        byte[] body = Join(value); var prefix = new List<byte>();
        if (type >= 128) { prefix.Add((byte)((type & 127) | 128)); prefix.Add((byte)(type >> 7)); } else prefix.Add((byte)type);
        int length = body.Length;
        do { byte b = (byte)(length & 127); length >>= 7; prefix.Add((byte)(b | (length > 0 ? 128 : 0))); } while (length > 0);
        return Join(prefix.ToArray(), body);
    }
    private static byte[] Rect(int firstRow, int lastRow, int firstColumn, int lastColumn) { return Join(I(firstRow), I(lastRow), I(firstColumn), I(lastColumn)); }
    private static byte[] Book(int firstRow, int lastRow, int firstColumn, int lastColumn)
    { return Join(R(131), R(143), R(156, I(0), I(1), S("rId1"), S("Synthetic")), R(144), R(549, Rect(firstRow, lastRow, firstColumn, lastColumn)), R(132)); }
    private static byte[] Row(int row, int firstColumn, int lastColumn)
    { return R(0, I(row), I(0), new byte[5], I(1), I(firstColumn), I(lastColumn)); }
    private static byte[] Real(int col, double value) { return R(5, I(col), I(0), BitConverter.GetBytes(value)); }
    private static byte[] Rk(int col, uint value) { return R(2, I(col), I(0), BitConverter.GetBytes(value)); }
    private static byte[] Sheet(byte[] dimensions, params byte[][] records) { return Join(R(129), R(148, dimensions), R(145), Join(records), R(146), R(130)); }
    private static byte[] Xml(int rows, int cols, params string[] values)
    {
        string content = "";
        if (rows == 1) content = "<Row>" + String.Join("", values) + "</Row>";
        else foreach (string value in values) content += "<Row>" + value + "</Row>";
        return Encoding.UTF8.GetBytes("<Workbook xmlns='urn:schemas-microsoft-com:office:spreadsheet' xmlns:ss='urn:schemas-microsoft-com:office:spreadsheet'><Worksheet ss:Name='Synthetic'><Table ss:ExpandedRowCount='"+rows+"' ss:ExpandedColumnCount='"+cols+"'>"+content+"</Table></Worksheet></Workbook>");
    }
    private static string Date { get { return "<Cell><Data ss:Type='DateTime'>1900-01-01T00:00:00.000</Data></Cell>"; } }
    private static string Text(string kind, string value) { return "<Cell><Data ss:Type='"+kind+"'>"+value+"</Data></Cell>"; }
    private static string Relationships(string body) { return "<Relationships xmlns='http://schemas.openxmlformats.org/package/2006/relationships'>"+body+"</Relationships>"; }
    private static string Relation(string id, string type, string target) { return "<Relationship Id='"+id+"' Type='http://schemas.openxmlformats.org/officeDocument/2006/relationships/"+type+"' Target='"+target+"'/>"; }
    private static byte[] Package(byte[] book, byte[] sheet, byte[] strings = null, string rels = null)
    {
        var files = new List<KeyValuePair<string,byte[]>>();
        files.Add(new KeyValuePair<string,byte[]>("_rels/.rels", Encoding.UTF8.GetBytes(Relationships(Relation("rId1","officeDocument","xl/workbook.bin")))));
        files.Add(new KeyValuePair<string,byte[]>("xl/workbook.bin", book));
        files.Add(new KeyValuePair<string,byte[]>("xl/_rels/workbook.bin.rels", Encoding.UTF8.GetBytes(rels ?? Relationships(Relation("rId1","worksheet","worksheets/sheet1.bin") + (strings != null ? Relation("rId2","sharedStrings","sharedStrings.bin") : "")))));
        files.Add(new KeyValuePair<string,byte[]>("xl/worksheets/sheet1.bin", sheet));
        if(strings != null) files.Add(new KeyValuePair<string,byte[]>("xl/sharedStrings.bin",strings));
        return Zip(files, false);
    }
    private static uint Crc(byte[] value) { uint crc=0xffffffff; foreach(byte b in value) { crc ^= b; for(int bit=0;bit<8;bit++)crc=(crc&1)!=0?0xedb88320^(crc>>1):crc>>1; } return crc^0xffffffff; }
    private static byte[] Zip(List<KeyValuePair<string,byte[]>> files, bool compress)
    {
        using(var stream = new MemoryStream()) using(var w = new BinaryWriter(stream)) using(var directory = new MemoryStream()) using(var d=new BinaryWriter(directory))
        {
            foreach(var entry in files)
            {
                byte[] name=Encoding.UTF8.GetBytes(entry.Key), raw=entry.Value, packed=raw;
                if(compress) using(var temp=new MemoryStream()) { using(var deflate=new DeflateStream(temp,CompressionMode.Compress,true))deflate.Write(raw,0,raw.Length);packed=temp.ToArray(); }
                uint offset=(uint)stream.Position, crc=Crc(raw);
                w.Write(0x04034b50u);w.Write((ushort)20);w.Write((ushort)0);w.Write((ushort)(compress?8:0));w.Write(0u);w.Write(crc);w.Write(packed.Length);w.Write(raw.Length);w.Write((ushort)name.Length);w.Write((ushort)0);w.Write(name);w.Write(packed);
                d.Write(0x02014b50u);d.Write((ushort)20);d.Write((ushort)20);d.Write((ushort)0);d.Write((ushort)(compress?8:0));d.Write(0u);d.Write(crc);d.Write(packed.Length);d.Write(raw.Length);d.Write((ushort)name.Length);d.Write((ushort)0);d.Write((ushort)0);d.Write((ushort)0);d.Write((ushort)0);d.Write(0u);d.Write(offset);d.Write(name);
            }
            uint start=(uint)stream.Position;byte[] central=directory.ToArray();w.Write(central);w.Write(0x06054b50u);w.Write((ushort)0);w.Write((ushort)0);w.Write((ushort)files.Count);w.Write((ushort)files.Count);w.Write(central.Length);w.Write(start);w.Write((ushort)0);return stream.ToArray();
        }
    }
    private static ClipboardSnapshot Parse(byte[] xml, byte[] package) { return SpreadsheetXmlParser.ParseWithNative(xml,package,1,"synthetic unit fixture"); }
    private static void Check(bool value) { if(!value)throw new Exception("assertion failed"); }
    private static void Reject(Action action) { try{action();}catch(ValidationException ex){Check(ex.Message.Contains("변경된 셀은 없습니다"));return;}throw new Exception("expected ValidationException"); }
    private static void Test(string name, Action test) { try{test();passed++;Console.WriteLine("PASS "+name);}catch(Exception ex){failed++;Console.WriteLine("FAIL "+name+": "+ex);} }
    private static byte[] Simple(double value=45200) { return Package(Book(0,0,18,18),Sheet(Rect(0,0,18,18),Row(0,18,18),Real(18,value))); }
    private static int Main(string[] args)
    {
        Console.OutputEncoding=new UTF8Encoding(false);
        Test("actual Excel native date RK yields raw45200",delegate{var s=Parse(File.ReadAllBytes(Path.Combine(args[0],"date.xml")),File.ReadAllBytes(Path.Combine(args[0],"date.xlsb")));Check(s.Items[0].Equals(CellValue.Number(45200)));Check(s.SourceFormat=="XML Spreadsheet + Biff12");});
        Test("actual filtered copied cells map compact coordinates not selection extent",delegate{var values=new[]{CellValue.Number(85),CellValue.Number(78)};var s=XlsbDateSupplement.Complete(File.ReadAllBytes(Path.Combine(args[0],"filtered.xlsb")),2,1,values,new bool[2]);Check(s.SequenceEqual(values));});
        Test("dates do not infer calendar or workbook date system",delegate{Check(Parse(Xml(1,1,Date),Simple(45200)).Items[0].Equals(CellValue.Number(45200)));Check(Parse(Xml(1,1,Date),Simple(43738)).Items[0].Equals(CellValue.Number(43738)));});
        Test("first middle trailing blanks and raw time percent formula result retained",delegate{
            var native=Package(Book(4,10,2,2),Sheet(Rect(5,9,2,2),Row(5,2,2),Real(2,45200),Row(7,2,2),Rk(2,0x3fe00000),Row(8,2,2),Real(2,0.12),Row(9,2,2),R(9,I(2),I(0),BitConverter.GetBytes(45200.125),new byte[2],I(1),new byte[]{0x1e},I(0))));
            var s=Parse(Xml(7,1,"<Cell/>",Date,"<Cell/>",Date,Text("Number","0.12"),Date,"<Cell/>"),native);
            Check(s.Items[0].Kind==CellValueKind.Empty&&s.Items[2].Kind==CellValueKind.Empty&&s.Items[6].Kind==CellValueKind.Empty&&s.Items[1].Equals(CellValue.Number(45200))&&s.Items[3].Equals(CellValue.Number(0.5))&&s.Items[5].Equals(CellValue.Number(45200.125)));
        });
        Test("horizontal positions preserve blanks",delegate{var s=Parse(Xml(1,4,"<Cell/>",Date,Date,"<Cell/>"),Package(Book(10,10,8,11),Sheet(Rect(10,10,9,10),Row(10,9,10),Real(9,45200),Real(10,0.25))));Check(s.Items[1].Equals(CellValue.Number(45200))&&s.Items[2].Equals(CellValue.Number(0.25))&&s.Items[3].Kind==CellValueKind.Empty);});
        Test("modern row and column positions not BIFF8 truncated",delegate{var s=Parse(Xml(1,1,Date),Package(Book(999999,999999,16000,16000),Sheet(Rect(999999,999999,16000,16000),Row(999999,16000,16000),Real(16000,45200))));Check(s.Items[0].Equals(CellValue.Number(45200)));});
        Test("RK signed integer and divide by100",delegate{var s=Parse(Xml(1,2,Date,Date),Package(Book(0,0,0,1),Sheet(Rect(0,0,0,1),Row(0,0,1),Rk(0,unchecked((uint)(-123<<2))|3),Rk(1,(45200u<<2)|2))));Check(s.Items[0].Equals(CellValue.Number(-1.23))&&s.Items[1].Equals(CellValue.Number(45200)));});
        Test("all XML nondate types crosschecked including shared strings",delegate{
            byte[] strings=Join(R(159,I(1),I(1)),R(19,new byte[]{0},S("00123")),R(160));
            var s=Parse(Xml(1,6,Date,Text("String","00123"),Text("Boolean","1"),Text("Error","#N/A"),Text("String",""),Text("Number","85")),Package(Book(0,0,0,5),Sheet(Rect(0,0,0,5),Row(0,0,5),Real(0,45200),R(7,I(1),I(0),I(0)),R(4,I(2),I(0),new byte[]{1}),R(3,I(3),I(0),new byte[]{42}),R(6,I(4),I(0),S("")),Real(5,85)),strings));Check(s.Items[1].Equals(CellValue.Text("00123"))&&s.Items[4].Kind==CellValueKind.String);
        });
        Test("cached formula string boolean error raw values only",delegate{
            var suffix=Join(new byte[2],I(1),new byte[]{0x1e},I(0));var s=Parse(Xml(1,4,Date,Text("String",""),Text("Boolean","0"),Text("Error","#N/A")),Package(Book(0,0,0,3),Sheet(Rect(0,0,0,3),Row(0,0,3),Real(0,45200),R(8,I(1),I(0),S(""),suffix),R(10,I(2),I(0),new byte[]{0},suffix),R(11,I(3),I(0),new byte[]{42},suffix))));Check(s.Items[1].Equals(CellValue.Text(""))&&s.Items[2].Equals(CellValue.Boolean(false)));
        });
        Test("rich text underlying string crosschecked",delegate{var s=Parse(Xml(1,2,Date,Text("String","abc")),Package(Book(0,0,0,1),Sheet(Rect(0,0,0,1),Row(0,0,1),Real(0,45200),R(62,I(1),I(0),new byte[]{1},S("abc"),I(1),new byte[4]))));Check(s.Items[1].Equals(CellValue.Text("abc")));});
        Test("phonetic runs preserve base text and bounds",delegate{var phonetic=Join(new byte[]{2},S("漢字"),S("かんじ"),I(1),new byte[]{0,0,0,0,2,0,0,0,0,0});var s=Parse(Xml(1,2,Date,Text("String","漢字")),Package(Book(0,0,0,1),Sheet(Rect(0,0,0,1),Row(0,0,1),Real(0,45200),R(62,I(1),I(0),phonetic))));Check(s.Items[1].Equals(CellValue.Text("漢字")));phonetic[phonetic.Length-6]=9;Reject(()=>Parse(Xml(1,2,Date,Text("String","漢字")),Package(Book(0,0,0,1),Sheet(Rect(0,0,0,1),Row(0,0,1),Real(0,45200),R(62,I(1),I(0),phonetic)))));});
        Test("MS XLSB fourth length-byte high bit ignored with body boundary intact",delegate{
            byte[] body=Join(I(0),I(0),BitConverter.GetBytes(45200.0));
            byte[] extended=Join(new byte[]{5,0x90,0x80,0x80,0x80},body);
            Check(Parse(Xml(1,1,Date),Package(Book(0,0,0,0),Sheet(Rect(0,0,0,0),Row(0,0,0),extended))).Items[0].Equals(CellValue.Number(45200)));
            byte[] corrupt=Join(new byte[]{5,0x90,0x80,0x80,0x80,0},body);
            Reject(()=>Parse(Xml(1,1,Date),Package(Book(0,0,0,0),Sheet(Rect(0,0,0,0),Row(0,0,0),corrupt))));
        });
        Test("MS XLSB RichStr unused bits ignored but run bounds enforced",delegate{
            byte[] rich=Join(new byte[]{0xfd},S("abc"),I(1),new byte[4]);
            Check(Parse(Xml(1,2,Date,Text("String","abc")),Package(Book(0,0,0,1),Sheet(Rect(0,0,0,1),Row(0,0,1),Real(0,45200),R(62,I(1),I(0),rich)))).Items[1].Equals(CellValue.Text("abc")));
            rich[rich.Length-4]=9;Reject(()=>Parse(Xml(1,2,Date,Text("String","abc")),Package(Book(0,0,0,1),Sheet(Rect(0,0,0,1),Row(0,0,1),Real(0,45200),R(62,I(1),I(0),rich)))));
        });
        Test("missing date raw number rejects",delegate{Reject(()=>Parse(Xml(1,1,Date),Package(Book(0,0,0,0),Sheet(Rect(0,0,0,0),Row(0,0,0),R(1,I(0),I(0))))));});
        Test("number disagreement rejects",delegate{Reject(()=>Parse(Xml(1,2,Date,Text("Number","84")),Package(Book(0,0,0,1),Sheet(Rect(0,0,0,1),Row(0,0,1),Real(0,45200),Real(1,85)))));});
        Test("empty versus empty string disagreement rejects",delegate{Reject(()=>Parse(Xml(1,2,Date,"<Cell/>"),Package(Book(0,0,0,1),Sheet(Rect(0,0,0,1),Row(0,0,1),Real(0,45200),R(6,I(1),I(0),S(""))))));});
        Test("duplicate or backwards native cells reject",delegate{Reject(()=>Parse(Xml(1,1,Date),Package(Book(0,0,0,0),Sheet(Rect(0,0,0,0),Row(0,0,0),Real(0,1),Real(0,2)))));});
        Test("native cell outside XML shape rejects",delegate{Reject(()=>Parse(Xml(1,1,Date),Package(Book(0,0,0,1),Sheet(Rect(0,0,0,1),Row(0,0,1),Real(0,1),Real(1,2)))));});
        Test("ambiguous2D embedded range rejects",delegate{Reject(()=>Parse(Xml(1,1,Date),Package(Book(0,1,0,1),Sheet(Rect(0,0,0,0),Row(0,0,0),Real(0,1)))));});
        Test("shifted native origin rejects rather than matching values",delegate{Reject(()=>Parse(Xml(1,1,Date),Package(Book(1,1,0,0),Sheet(Rect(0,0,0,0),Row(0,0,0),Real(0,1)))));});
        Test("unknown cell table record rejects",delegate{Reject(()=>Parse(Xml(1,1,Date),Package(Book(0,0,0,0),Sheet(Rect(0,0,0,0),Row(0,0,0),R(49,I(1)),Real(0,1)))));});
        Test("nonfinite raw double rejects",delegate{Reject(()=>Parse(Xml(1,1,Date),Simple(Double.NaN)));Reject(()=>Parse(Xml(1,1,Date),Simple(Double.PositiveInfinity)));});
        Test("formula token length bounded without execution",delegate{Reject(()=>Parse(Xml(1,1,Date),Package(Book(0,0,0,0),Sheet(Rect(0,0,0,0),Row(0,0,0),R(9,I(0),I(0),BitConverter.GetBytes(45200.0),new byte[2],I(Int32.MaxValue))))));});
        Test("second workbook sheet rejects",delegate{byte[] book=Join(R(131),R(143),R(156,I(0),I(1),S("rId1"),S("one")),R(156,I(0),I(2),S("rId2"),S("two")),R(144),R(549,Rect(0,0,0,0)),R(132));Reject(()=>Parse(Xml(1,1,Date),Package(book,Sheet(Rect(0,0,0,0),Row(0,0,0),Real(0,1)))));});
        Test("missing native origin rejects",delegate{Reject(()=>Parse(Xml(1,1,Date),Package(Join(R(131),R(143),R(156,I(0),I(1),S("rId1"),S("one")),R(144),R(132)),Sheet(Rect(0,0,0,0),Row(0,0,0),Real(0,1)))));});
        Test("external worksheet relationship never fetched",delegate{var rel=Relationships(Relation("rId1","worksheet","worksheets/sheet1.bin").Replace("/>"," TargetMode='External'/>"));Reject(()=>Parse(Xml(1,1,Date),Package(Book(0,0,0,0),Sheet(Rect(0,0,0,0),Row(0,0,0),Real(0,1)),null,rel)));});
        Test("relationship DTD rejected",delegate{var rel="<!DOCTYPE Relationships [<!ENTITY x SYSTEM 'https://example.invalid/no'>]>"+Relationships(Relation("rId1","worksheet","worksheets/sheet1.bin"));Reject(()=>Parse(Xml(1,1,Date),Package(Book(0,0,0,0),Sheet(Rect(0,0,0,0),Row(0,0,0),Real(0,1)),null,rel)));});
        Test("record truncated at every byte rejects",delegate{byte[] body=Sheet(Rect(0,0,0,0),Row(0,0,0),Real(0,1));for(int i=0;i<body.Length;i++){byte[] truncated=body.Take(i).ToArray();Reject(()=>Parse(Xml(1,1,Date),Package(Book(0,0,0,0),truncated)));}});
        Test("native plus XML payload bounded",delegate{Reject(()=>Parse(Xml(1,1,Date),new byte[Limits.MaxPayloadBytes]));});
        Test("ZIP deflate known value and CRC",delegate{var files=new List<KeyValuePair<string,byte[]>>{new KeyValuePair<string,byte[]>("one",Encoding.UTF8.GetBytes("test value"))};var zip=new BoundedZip(Zip(files,true));Check(Encoding.UTF8.GetString(zip.Read("one"))=="test value");});
        Test("ZIP corrupted CRC rejects",delegate{var files=new List<KeyValuePair<string,byte[]>>{new KeyValuePair<string,byte[]>("one",new byte[]{1,2,3})};byte[] zip=Zip(files,false);zip[33]^=1;Reject(()=>new BoundedZip(zip).Read("one"));});
        Test("ZIP duplicate names and traversal reject",delegate{Reject(()=>new BoundedZip(Zip(new List<KeyValuePair<string,byte[]>>{new KeyValuePair<string,byte[]>("one",new byte[0]),new KeyValuePair<string,byte[]>("one",new byte[0])},false)));Reject(()=>new BoundedZip(Zip(new List<KeyValuePair<string,byte[]>>{new KeyValuePair<string,byte[]>("../one",new byte[0])},false)));});
        Test("ZIP encryption flags and forged length reject",delegate{byte[] zip=Simple();int central=BitConverter.ToInt32(zip,zip.Length-6);zip[6]=1;zip[central+8]=1;Reject(()=>new BoundedZip(zip));zip=Simple();central=BitConverter.ToInt32(zip,zip.Length-6);Buffer.BlockCopy(I(Limits.MaxPayloadBytes+1),0,zip,central+24,4);Reject(()=>new BoundedZip(zip));});
        Test("ZIP truncated archive rejects",delegate{byte[] zip=Simple();for(int i=0;i<zip.Length;i+=17){byte[] bad=zip.Take(i).ToArray();Reject(()=>new BoundedZip(bad));}});
        Test("ZIP bounded fuzz throws validation not arbitrary exceptions",delegate{var random=new Random(941);for(int i=0;i<1000;i++){byte[] bad=new byte[random.Next(0,1024)];random.NextBytes(bad);Reject(()=>new BoundedZip(bad));}});
        Console.WriteLine("RESULT: "+passed+" passed; "+failed+" failed"); return failed==0?0:1;
    }
}
