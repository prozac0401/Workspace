using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using VisibleCellsPaste;

internal static class CoreTests
{
    private static int passed, failed;
    private static string Xml(int rows, int columns, string body)
    {
        return "<?xml version=\"1.0\"?><Workbook xmlns=\"urn:schemas-microsoft-com:office:spreadsheet\" xmlns:ss=\"urn:schemas-microsoft-com:office:spreadsheet\"><Worksheet ss:Name=\"Synthetic\"><Table ss:ExpandedRowCount=\"" + rows + "\" ss:ExpandedColumnCount=\"" + columns + "\">" + body + "</Table></Worksheet></Workbook>";
    }
    private static string Cell(string kind, string value) { return "<Cell><Data ss:Type=\"" + kind + "\">" + value + "</Data></Cell>"; }
    private static ClipboardSnapshot Parse(string text) { return SpreadsheetXmlParser.Parse(Encoding.UTF8.GetBytes(text), 9, "synthetic unit input"); }
    private static ClipboardSnapshot Source(int count) { return new ClipboardSnapshot("synthetic", 1, count, 1, true, Enumerable.Range(0, count).Select(i => CellValue.Number(i)), "unit"); }
    private static SelectionSnapshot Selection(int first, int last, IEnumerable<int> rows)
    { return new SelectionSnapshot("sheet-a", first, last, 5, 1, (long)last-first+1, 1, false, false, rows.Select(r => new TargetCell("sheet-a", r, 5, false))); }
    private static void Check(bool result, string message) { if (!result) throw new Exception(message); }
    private static void Reject(Action action, string code)
    {
        try { action(); } catch (ValidationException ex) { Check(ex.Code == code, "Expected " + code + "; got " + ex.Code); Check(ex.Message.Contains("변경된 셀은 없습니다"), "Missing no-change message"); return; }
        throw new Exception("Expected rejection " + code);
    }
    private static void Test(string name, Action action)
    {
        try { action(); passed++; Console.WriteLine("PASS " + name); }
        catch (Exception error) { failed++; Console.WriteLine("FAIL " + name + ": " + error); }
    }
    private static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        Test("D07 Excel real-copy sparse XML retains five slots", delegate {
            Check(args.Length == 1, "Fixture path required");
            ClipboardSnapshot s = SpreadsheetXmlParser.Parse(File.ReadAllBytes(args[0]), 162, "synthetic Excel M0 capture");
            Check(s.SourceRows == 5 && s.SourceColumns == 1 && s.Items.Count == 5, "shape");
            Check(s.Items[0].Equals(CellValue.Number(85)) && s.Items[1].Equals(CellValue.Text("00123")), "types");
            Check(s.Items[2].Kind == CellValueKind.Empty && s.Items[3].Equals(CellValue.Text("한글\n줄바꿈")) && s.Items[4].Kind == CellValueKind.Empty, "sparse empty positions");
        });
        Test("D02 horizontal positions preserve starting and ending empty", delegate {
            ClipboardSnapshot s = Parse(Xml(1, 5, "<Row><Cell ss:Index=\"2\"><Data ss:Type=\"String\">A</Data></Cell><Cell ss:Index=\"4\"><Data ss:Type=\"Number\">2</Data></Cell></Row>"));
            Check(s.Items.Count == 5 && s.Items[0].Kind == CellValueKind.Empty && s.Items[2].Kind == CellValueKind.Empty && s.Items[4].Kind == CellValueKind.Empty, "empty positions");
            Check(s.Items[1].Equals(CellValue.Text("A")) && s.Items[3].Equals(CellValue.Number(2)), "sequence");
        });
        Test("horizontal repeated column formatting does not alter data shape", delegate { var s=Parse(Xml(1,3,"<Column ss:Span=\"2\"/><Row>"+Cell("Number","1")+Cell("String","00123")+"</Row>")); Check(s.Items.Count==3&&s.Items[0].Kind==CellValueKind.Number&&s.Items[1].Kind==CellValueKind.String&&s.Items[2].Kind==CellValueKind.Empty,"column span"); Reject(()=>Parse(Xml(1,3,"<Column ss:Span=\"3\"/>")),"VCP-XML-INDEX-LIMIT"); });
        Test("D08 all empty slots retained", delegate { ClipboardSnapshot s=Parse(Xml(5,1,"")); Check(s.Items.Count==5 && s.Items.All(x=>x.Kind==CellValueKind.Empty),"empty slots"); });
        Test("D03 single empty cell", delegate { Check(Parse(Xml(1,1,"<Row><Cell/></Row>")).Items[0].Kind==CellValueKind.Empty,"empty"); });
        Test("D09 D11 D12 string identity whitespace unicode tabs newline duplicates", delegate {
            string v = " 00123\t한글😀\n12345678901234567890 ";
            ClipboardSnapshot s=Parse(Xml(1,2,"<Row>"+Cell("String",v)+Cell("String",v)+"</Row>"));
            Check(s.Items[0].Equals(CellValue.Text(v)) && s.Items[1].Equals(CellValue.Text(v)),"text changed");
        });
        Test("D10 numeric value ignores display style", delegate { Check(Parse(Xml(1,1,"<Row><Cell ss:StyleID=\"zero5\"><Data ss:Type=\"Number\">123</Data></Cell></Row>")).Items[0].Equals(CellValue.Number(123)),"numeric"); });
        Test("D13 formula cached values use number text boolean error", delegate {
            string body="<Row><Cell ss:Formula=\"=1+1\"><Data ss:Type=\"Number\">2</Data></Cell>"+Cell("String","x")+Cell("Boolean","1")+Cell("Error","#N/A")+"</Row>";
            ClipboardSnapshot s=Parse(Xml(1,4,body));
            Check(s.Items[0].Equals(CellValue.Number(2))&&s.Items[1].Equals(CellValue.Text("x"))&&s.Items[2].Equals(CellValue.Boolean(true))&&s.Items[3].Equals(CellValue.Error(2042)),"types");
        });
        Test("D14 formula-like literals remain text", delegate {
            ClipboardSnapshot s=Parse(Xml(1,3,"<Row>"+Cell("String","=1+1")+Cell("String","+001")+Cell("String","@abc")+"</Row>"));
            Check(s.Items.All(x=>x.Kind==CellValueKind.String),"literal type");
        });
        Test("D15 error and error-like text distinct", delegate { ClipboardSnapshot s=Parse(Xml(1,2,"<Row>"+Cell("Error","#N/A")+Cell("String","#N/A")+"</Row>")); Check(!s.Items[0].Equals(s.Items[1]),"error conflated"); });
        Test("D16 cached empty string distinct from empty", delegate { ClipboardSnapshot s=Parse(Xml(1,2,"<Row><Cell ss:Formula=\"=&quot;&quot;\"><Data ss:Type=\"String\"></Data></Cell><Cell/></Row>")); Check(s.Items[0].Equals(CellValue.Text("")) && s.Items[1].Kind==CellValueKind.Empty,"empty-string contract"); });
        Test("D17 D18 DateTime without numeric serial safely rejected", delegate { Reject(()=>Parse(Xml(1,1,"<Row>"+Cell("DateTime","2026-09-24T00:00:00.000")+"</Row>")),"VCP-XML-DATE-SERIAL"); });
        Test("D19 2D source rejected", delegate { Reject(()=>Parse(Xml(2,2,"")),"VCP-XML-SHAPE"); });
        Test("R09 source merge rejected", delegate { Reject(()=>Parse(Xml(1,2,"<Row><Cell ss:MergeAcross=\"1\"/></Row>")),"VCP-XML-MERGED"); });
        Test("missing dimensions rejected", delegate { Reject(()=>Parse(Xml(1,1,"").Replace("ss:ExpandedRowCount=\"1\"", "")),"VCP-XML-DIMENSIONS"); });
        Test("missing cached formula result rejected", delegate { Reject(()=>Parse(Xml(1,1,"<Row><Cell ss:Formula=\"=1\"/></Row>")),"VCP-XML-FORMULA-RESULT"); });
        Test("R20 giant declaration rejected before allocation", delegate { Reject(()=>Parse(Xml(1,1,"").Replace("ss:ExpandedRowCount=\"1\"","ss:ExpandedRowCount=\"2147483647\"")),"VCP-XML-INDEX-LIMIT"); });
        Test("R20 index outside dimensions rejected", delegate { Reject(()=>Parse(Xml(1,1,"<Row ss:Index=\"2\"/>")),"VCP-XML-INDEX-LIMIT"); });
        Test("R20 duplicate backwards row rejected", delegate { Reject(()=>Parse(Xml(2,1,"<Row/><Row ss:Index=\"1\"/>")),"VCP-XML-INDEX"); });
        Test("R20 inferred row exceeding count rejected", delegate { Reject(()=>Parse(Xml(1,1,"<Row/><Row/>")),"VCP-XML-INDEX"); });
        Test("R20 malformed XML rejected", delegate { Reject(()=>Parse("<Workbook>"),"VCP-XML-INVALID"); });
        Test("R20 unexpected namespace cell rejected", delegate { Reject(()=>Parse(Xml(1,1,"<Row><Cell xmlns=\"untrusted\"/></Row>")),"VCP-XML-ROW-CONTENT"); });
        Test("R21 DTD and external entity disabled", delegate { Reject(()=>Parse("<!DOCTYPE Workbook [<!ENTITY x SYSTEM 'file:///nonexistent'>]>"+Xml(1,1,"<Row>"+Cell("String","&x;")+"</Row>").Replace("<?xml version=\"1.0\"?>", "")),"VCP-XML-INVALID"); });
        Test("R21 external inline structure not executed", delegate { Reject(()=>Parse(Xml(1,1,"<Row>"+Cell("String","<script xmlns=\"http://www.w3.org/TR/REC-html40\">x</script>")+"</Row>")),"VCP-XML-RICH-TEXT"); });
        Test("R17 HTML TSV plaintext never downgraded", delegate { Reject(()=>Parse("<html><table><tr><td>1</td></tr></table></html>"),"VCP-XML-FORMAT"); Reject(()=>Parse("1\t2\n3"),"VCP-XML-INVALID"); });
        Test("nonfinite number rejected", delegate { Reject(()=>Parse(Xml(1,1,"<Row>"+Cell("Number","NaN")+"</Row>")),"VCP-XML-NUMBER"); });
        Test("unknown data type rejected", delegate { Reject(()=>Parse(Xml(1,1,"<Row>"+Cell("Unknown","x")+"</Row>")),"VCP-XML-TYPE"); });
        Test("unknown error rejected", delegate { Reject(()=>Parse(Xml(1,1,"<Row>"+Cell("Error","#UNKNOWN!")+"</Row>")),"VCP-XML-ERROR-TYPE"); });
        Test("UTF16 and terminal null preserve text", delegate {
            string xml=Xml(1,1,"<Row>"+Cell("String","한글")+"</Row>").Replace("version=\"1.0\"","version=\"1.0\" encoding=\"utf-16\"")+"\0";
            var bytes=Encoding.Unicode.GetPreamble().Concat(Encoding.Unicode.GetBytes(xml)).ToArray();
            Check(SpreadsheetXmlParser.Parse(bytes,1,"").Items[0].Equals(CellValue.Text("한글")),"encoding");
        });
        Test("P03 32 MiB payload limit", delegate { Reject(()=>SpreadsheetXmlParser.Parse(new byte[Limits.MaxPayloadBytes+1],1,""),"VCP-XML-LIMIT"); });
        Test("P04 50000 source slots allowed 50001 rejected", delegate { Check(Parse(Xml(50000,1,"")).Items.Count==50000,"boundary"); Reject(()=>Parse(Xml(50001,1,"")),"VCP-XML-INDEX-LIMIT"); });
        Test("immutable source owns caller list", delegate { var input=new List<CellValue>{CellValue.Text("A")}; var s=new ClipboardSnapshot("x",1,1,1,true,input,""); input[0]=CellValue.Text("B"); Check(s.Items[0].Equals(CellValue.Text("A")),"alias"); });
        Test("D01 row sorting and segment mapping", delegate { var p=Planner.Build(Source(3),Selection(2,8,new[]{8,2,5})); Check(p.Targets.Select(x=>x.Row).SequenceEqual(new[]{2,5,8})&&p.Segments.Count==3,"mapping"); });
        Test("D02 horizontal source planner", delegate { var s=Parse(Xml(1,3,"<Row>"+Cell("Number","85")+Cell("Number","90")+Cell("Number","78")+"</Row>")); Check(Planner.Build(s,Selection(2,8,new[]{2,5,8})).Targets.Count==3,"horizontal plan"); });
        Test("D03 R08 single target cannot escape selection", delegate { Check(Planner.Build(Source(1),Selection(5,5,new[]{5})).Targets[0].Row==5,"single"); Reject(()=>Planner.Build(Source(1),Selection(5,5,new[]{6})),"VCP-TARGET-BOUNDARY"); });
        Test("D04 D05 D06 all mismatches rejected without repetition", delegate { Reject(()=>Planner.Build(Source(3),Selection(2,4,new[]{2,3})),"VCP-COUNT-MISMATCH"); Reject(()=>Planner.Build(Source(2),Selection(2,4,new[]{2,3,4})),"VCP-COUNT-MISMATCH"); Reject(()=>Planner.Build(Source(1),Selection(2,4,new[]{2,3,4})),"VCP-COUNT-MISMATCH"); });
        Test("R04 zero visible target rejected", delegate { Reject(()=>Planner.Build(Source(1),Selection(2,5,new int[0])),"VCP-TARGET-EMPTY"); });
        Test("R06 whole column rejected before matching", delegate { Reject(()=>Planner.Build(Source(1),Selection(1,1048576,new[]{1})),"VCP-TARGET-WHOLE"); });
        Test("R07 user multiarea selection rejected", delegate { var s=new SelectionSnapshot("sheet-a",2,5,5,1,4,2,false,false,new[]{new TargetCell("sheet-a",2,5,false)}); Reject(()=>Planner.Build(Source(1),s),"VCP-TARGET-SHAPE"); });
        Test("R10 grouped sheets rejected", delegate { var s=new SelectionSnapshot("sheet-a",2,5,5,1,4,1,false,true,new[]{new TargetCell("sheet-a",2,5,false)}); Reject(()=>Planner.Build(Source(1),s),"VCP-TARGET-SHAPE"); });
        Test("hidden target column rejected", delegate { var s=new SelectionSnapshot("sheet-a",2,5,5,1,4,1,true,false,new[]{new TargetCell("sheet-a",2,5,false)}); Reject(()=>Planner.Build(Source(1),s),"VCP-TARGET-HIDDEN-COLUMN"); });
        Test("R01 hidden row duplicate wrong sheet wrong column all rejected", delegate {
            foreach(var t in new[]{new TargetCell("sheet-a",2,5,true),new TargetCell("other",2,5,false),new TargetCell("sheet-a",2,6,false)})
                Reject(()=>Planner.Build(Source(1),new SelectionSnapshot("sheet-a",2,5,5,1,4,1,false,false,new[]{t})),"VCP-TARGET-BOUNDARY");
            Reject(()=>Planner.Build(Source(2),Selection(2,5,new[]{2,2})),"VCP-TARGET-BOUNDARY");
        });
        Test("P03 P04 selection 200000 boundary", delegate { Check(Planner.Build(Source(1),Selection(1,200000,new[]{1})).Targets.Count==1,"scan boundary"); Reject(()=>Planner.Build(Source(1),Selection(1,200001,new[]{1})),"VCP-TARGET-SCAN-LIMIT"); });
        Test("P02 consecutive segments never bridge hidden rows", delegate { var p=Planner.Build(Source(6),Selection(1,10,new[]{1,2,5,6,7,10})); Check(p.Segments.Count==3&&p.Segments[0].Count==2&&p.Segments[1].Count==3&&p.Segments[2].Count==1,"segments"); });
        Test("P04 20000 segment boundary and 20001 rejection", delegate { var rows=Enumerable.Range(0,20000).Select(i=>i*2+1).ToArray(); Check(Planner.Build(Source(20000),Selection(1,40001,rows)).Segments.Count==20000,"segments limit"); Reject(()=>Planner.Build(Source(20001),Selection(1,40001,Enumerable.Range(0,20001).Select(i=>i*2+1))),"VCP-SEGMENT-LIMIT"); });
        Test("P01 large warning starts at 5000 cells or 1000 segments", delegate { Check(!Planner.Build(Source(4999),Selection(1,4999,Enumerable.Range(1,4999))).RequiresSizeConfirmation,"4999"); Check(Planner.Build(Source(5000),Selection(1,5000,Enumerable.Range(1,5000))).RequiresSizeConfirmation,"5000"); Check(Planner.Build(Source(1000),Selection(1,2000,Enumerable.Range(0,1000).Select(i=>i*2+1))).RequiresSizeConfirmation,"1000 areas"); });
        Test("randomized planner segments exactly cover sorted unique visible rows", delegate {
            var random=new Random(3941);
            for(int trial=0;trial<200;trial++) {
                int[] rows=Enumerable.Range(1,100).Where(x=>random.Next(3)==0).ToArray(); if(rows.Length==0) continue;
                var shuffled=rows.OrderBy(x=>random.Next()).ToArray(); var p=Planner.Build(Source(rows.Length),Selection(1,100,shuffled));
                var flattened=p.Segments.SelectMany(seg=>Enumerable.Range(seg.FirstRow,seg.Count)).ToArray(); Check(flattened.SequenceEqual(rows),"coverage trial "+trial);
                foreach(var seg in p.Segments) Check(seg.FirstRow==p.Targets[seg.StartIndex].Row,"source offset");
            }
        });
        Console.WriteLine("RESULT: " + passed + " passed; " + failed + " failed");
        return failed==0 ? 0 : 1;
    }
}
