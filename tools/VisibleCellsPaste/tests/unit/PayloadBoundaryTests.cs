using System;
using System.Diagnostics;
using System.Text;
using System.Linq;
using VisibleCellsPaste;
// Pure parser boundary proof. No clipboard/COM/Excel/UI/file payload access.
class PayloadBoundaryTests {
 static int passed, failed;
 static byte[] Payload(int size) {
  byte[] start=Encoding.ASCII.GetBytes("<?xml version=\"1.0\"?><Workbook xmlns=\"urn:schemas-microsoft-com:office:spreadsheet\" xmlns:ss=\"urn:schemas-microsoft-com:office:spreadsheet\"><!--");
  byte[] end=Encoding.ASCII.GetBytes("--><Worksheet ss:Name=\"Synthetic\"><Table ss:ExpandedRowCount=\"1\" ss:ExpandedColumnCount=\"1\"><Row><Cell><Data ss:Type=\"String\">00123</Data></Cell></Row></Table></Worksheet></Workbook>");
  byte[] result=new byte[size]; Buffer.BlockCopy(start,0,result,0,start.Length); for(int i=start.Length;i<size-end.Length;i++)result[i]=(byte)'p'; Buffer.BlockCopy(end,0,result,size-end.Length,end.Length); return result;
 }
 static void Test(int bytes,bool accepted) {
  var timer=Stopwatch.StartNew();
  try {
   byte[] payload=Payload(bytes); string rejection=null; ClipboardSnapshot parsed=null;
   try { parsed=SpreadsheetXmlParser.Parse(payload,0,"synthetic exact-size parser boundary"); } catch(ValidationException e) { rejection=e.Code; }
   if(accepted) { if(parsed==null || parsed.Items.Count!=1 || !parsed.Items[0].Equals(CellValue.Text("00123")) || parsed.SourceRows!=1 || parsed.SourceColumns!=1)throw new Exception("Expected exact one typed item; rejection="+rejection); }
   else if(rejection!="VCP-XML-LIMIT")throw new Exception("Expected VCP-XML-LIMIT; got "+rejection);
   passed++;Console.WriteLine("PASS P04 payload_bytes="+bytes+";accepted="+accepted+";elapsed_ms="+timer.ElapsedMilliseconds);
  } catch(Exception e) { failed++;Console.WriteLine("FAIL P04 payload_bytes="+bytes+";"+e); }
 }
 static byte[] Slots(int rows) { return Encoding.UTF8.GetBytes("<Workbook xmlns=\"urn:schemas-microsoft-com:office:spreadsheet\" xmlns:ss=\"urn:schemas-microsoft-com:office:spreadsheet\"><Worksheet ss:Name=\"Synthetic\"><Table ss:ExpandedRowCount=\""+rows+"\" ss:ExpandedColumnCount=\"1\"/></Worksheet></Workbook>"); }
 static void SourceBoundary(int count,bool accepted) { try { ClipboardSnapshot s=null;string code=null;try{s=SpreadsheetXmlParser.Parse(Slots(count),0,"synthetic source item boundary");}catch(ValidationException e){code=e.Code;}if(accepted){if(s==null||s.Items.Count!=count||s.Items.Any(v=>v.Kind!=CellValueKind.Empty))throw new Exception("Sparse item boundary did not preserve exact Empty count");}else if(code!="VCP-XML-INDEX-LIMIT")throw new Exception("Unexpected source refusal "+code);passed++;Console.WriteLine("PASS P04 source_items="+count+";accepted="+accepted);}catch(Exception e){failed++;Console.WriteLine("FAIL P04 source_items="+count+";"+e);} }
 static void SegmentBoundary(int count,bool accepted) { try {var source=new ClipboardSnapshot("synthetic",0,count,1,true,Enumerable.Range(0,count).Select(i=>CellValue.Number(i)),"pure segment boundary");var cells=Enumerable.Range(0,count).Select(i=>new TargetCell("owned",i*2+1,5,false));var selection=new SelectionSnapshot("owned",1,count*2-1,5,1,count*2-1,1,false,false,cells);PastePlan plan=null;string code=null;try{plan=Planner.Build(source,selection);}catch(ValidationException e){code=e.Code;}if(accepted){if(plan==null||plan.Segments.Count!=count||plan.Targets.Count!=count||plan.Targets.Last().Row!=count*2-1)throw new Exception("Segment boundary changed target count/order");}else if(code!="VCP-SEGMENT-LIMIT")throw new Exception("Unexpected segment refusal "+code);passed++;Console.WriteLine("PASS P04 segments="+count+";accepted="+accepted);}catch(Exception e){failed++;Console.WriteLine("FAIL P04 segments="+count+";"+e);} }
 static int Main(){Console.OutputEncoding=new UTF8Encoding(false);Console.WriteLine("Pure XML parser byte boundary. Synthetic comment padding, one String 00123. No Excel or clipboard access.");Test(Limits.MaxPayloadBytes-1,true);Test(Limits.MaxPayloadBytes,true);Test(Limits.MaxPayloadBytes+1,false);SourceBoundary(49999,true);SourceBoundary(50000,true);SourceBoundary(50001,false);SegmentBoundary(19999,true);SegmentBoundary(20000,true);SegmentBoundary(20001,false);Console.WriteLine("SUMMARY passed="+passed+" failed="+failed);return failed==0?0:1;}
}
