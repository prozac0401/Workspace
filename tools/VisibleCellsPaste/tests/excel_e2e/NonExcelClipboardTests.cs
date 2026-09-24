using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using VisibleCellsPaste;
internal static class NonExcelClipboardTests {
 [DllImport("user32.dll",SetLastError=true)]static extern bool OpenClipboard(IntPtr owner);
 [DllImport("user32.dll")]static extern bool CloseClipboard();
 [DllImport("user32.dll")]static extern bool EmptyClipboard();
 [DllImport("user32.dll")]static extern IntPtr SetClipboardData(uint format,IntPtr memory);
 [DllImport("user32.dll")]static extern IntPtr GetClipboardData(uint format);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern uint RegisterClipboardFormat(string name);
 [DllImport("kernel32.dll")]static extern IntPtr GlobalAlloc(uint flags,UIntPtr count);
 [DllImport("kernel32.dll")]static extern IntPtr GlobalFree(IntPtr memory);
 [DllImport("kernel32.dll")]static extern IntPtr GlobalLock(IntPtr memory);
 [DllImport("kernel32.dll")]static extern bool GlobalUnlock(IntPtr memory);
 [DllImport("kernel32.dll")]static extern UIntPtr GlobalSize(IntPtr memory);
 static void Check(bool ok,string message){if(!ok)throw new Exception(message);}
 static void Open(IntPtr owner){for(int i=0;i<4;i++){if(OpenClipboard(owner))return;Thread.Sleep(25);}throw new Exception("Clipboard busy");}
 static void Set(IntPtr owner,uint format,byte[] bytes){
  Open(owner);IntPtr memory=IntPtr.Zero;
  try{Check(EmptyClipboard(),"Synthetic clipboard empty failed");memory=GlobalAlloc(2,new UIntPtr((uint)bytes.Length));Check(memory!=IntPtr.Zero,"GlobalAlloc failed");IntPtr pointer=GlobalLock(memory);Check(pointer!=IntPtr.Zero,"GlobalLock failed");try{Marshal.Copy(bytes,0,pointer,bytes.Length);}finally{GlobalUnlock(memory);}Check(SetClipboardData(format,memory)!=IntPtr.Zero,"SetClipboardData failed");memory=IntPtr.Zero;}
  finally{if(memory!=IntPtr.Zero)GlobalFree(memory);CloseClipboard();}
 }
 static byte[] Read(uint format){Open(IntPtr.Zero);try{IntPtr memory=GetClipboardData(format);Check(memory!=IntPtr.Zero,"Test payload unavailable");int size=checked((int)GlobalSize(memory).ToUInt64());Check(size>0&&size<65536,"Unexpected synthetic payload size");IntPtr pointer=GlobalLock(memory);Check(pointer!=IntPtr.Zero,"Payload lock failed");try{var data=new byte[size];Marshal.Copy(pointer,data,0,size);return data;}finally{GlobalUnlock(memory);}}finally{CloseClipboard();}}
 static string Hash(byte[] bytes){using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","").ToLowerInvariant();}
 static byte[] Html(){string body="<html><body><!--StartFragment--><table><tr><td>85</td><td>00123</td></tr></table><!--EndFragment--></body></html>";string header="Version:1.0\r\nStartHTML:{0:D10}\r\nEndHTML:{1:D10}\r\nStartFragment:{2:D10}\r\nEndFragment:{3:D10}\r\n";int start=Encoding.UTF8.GetByteCount(String.Format(header,0,0,0,0));int fragment=start+Encoding.UTF8.GetByteCount(body.Substring(0,body.IndexOf("<!--StartFragment-->")+20));int end=start+Encoding.UTF8.GetByteCount(body.Substring(0,body.IndexOf("<!--EndFragment-->")));return Encoding.UTF8.GetBytes(String.Format(header,start,start+Encoding.UTF8.GetByteCount(body),fragment,end)+body+"\0");}
 static byte[] Dib(){var data=new byte[56];Array.Copy(BitConverter.GetBytes(40),0,data,0,4);Array.Copy(BitConverter.GetBytes(2),0,data,4,4);Array.Copy(BitConverter.GetBytes(2),0,data,8,4);Array.Copy(BitConverter.GetBytes((ushort)1),0,data,12,2);Array.Copy(BitConverter.GetBytes((ushort)32),0,data,14,2);Array.Copy(BitConverter.GetBytes(16),0,data,20,4);for(int i=40;i<data.Length;i++)data[i]=(byte)(i*3);return data;}
 static byte[] Files(string directory){string a=Path.Combine(directory,"synthetic-file-a.txt"),b=Path.Combine(directory,"synthetic-file-b.txt");File.WriteAllText(a,"Owned synthetic test A");File.WriteAllText(b,"Owned synthetic test B");byte[] list=Encoding.Unicode.GetBytes(a+"\0"+b+"\0\0");var data=new byte[20+list.Length];Array.Copy(BitConverter.GetBytes(20),0,data,0,4);Array.Copy(BitConverter.GetBytes(1),0,data,16,4);Array.Copy(list,0,data,20,list.Length);return data;}
 static object RunCase(IntPtr owner,string name,uint format,byte[] payload){
  Set(owner,format,payload);byte[] before=Read(format);string[] formats=NativeClipboard.ProbeFormats().ToArray();uint sequence=NativeClipboard.GetClipboardSequenceNumber();IntPtr ownerBefore=NativeClipboard.GetClipboardOwner();uint pid;NativeClipboard.GetWindowThreadProcessId(ownerBefore,out pid);Check(pid==(uint)Process.GetCurrentProcess().Id,"Fixture owner differs from test process");var codes=new List<string>();
  foreach(int mode in new[]{0,1}){try{ClipboardReader.ReadSnapshot(mode);throw new Exception("Non-Excel clipboard unexpectedly accepted");}catch(ValidationException e){Check(e.Code=="VCP-CLIPBOARD-COPY-UNVERIFIED","Unexpected refusal: "+e.Code);Check(e.Message.Contains("변경된 셀은 없습니다"),"Missing no-change refusal");codes.Add(e.Code);}}
  byte[] after=Read(format);string[] afterFormats=NativeClipboard.ProbeFormats().ToArray();uint afterSequence=NativeClipboard.GetClipboardSequenceNumber();IntPtr afterOwner=NativeClipboard.GetClipboardOwner();
  Check(sequence==afterSequence&&ownerBefore==afterOwner&&formats.SequenceEqual(afterFormats)&&before.SequenceEqual(after),"Product clipboard read changed the source data or ownership");Check(payload.SequenceEqual(before.Take(payload.Length)),"Windows payload does not match fixture");
  Console.WriteLine("PASS "+name+": refused for caller modes 0/1; sequence, owner, formats, bytes unchanged");
  return new {name,status="PASS",format,payloadBytes=before.Length,beforeSequence=sequence,afterSequence,ownerProcessId=pid,formats,sha256Before=Hash(before),sha256After=Hash(after),refusalCodes=codes.ToArray()};
 }
 [STAThread]static int Main(string[] args){
  if(args.Length!=2||args[0]!="--synthetic-only"){Console.Error.WriteLine("Use --synthetic-only output-directory; this test replaces clipboard with owned synthetic data.");return 2;}
  string output=Path.GetFullPath(args[1]);Directory.CreateDirectory(output);Console.OutputEncoding=new UTF8Encoding(false);
  if(Process.GetProcessesByName("EXCEL").Length!=0){Console.Error.WriteLine("NOT RUN: Excel is active; no clipboard mutation performed.");return 3;}
  var window=new NativeWindow();window.CreateHandle(new CreateParams{Caption="VCP synthetic clipboard test owner",Parent=new IntPtr(-3)});var results=new List<object>();int exit=0;string failure=null;
  try{results.Add(RunCase(window.Handle,"Unicode text",13,Encoding.Unicode.GetBytes("합성 텍스트 85\r\n00123\0")));results.Add(RunCase(window.Handle,"HTML table",RegisterClipboardFormat("HTML Format"),Html()));results.Add(RunCase(window.Handle,"DIB image",8,Dib()));results.Add(RunCase(window.Handle,"File drop list",15,Files(output)));}
  catch(Exception error){failure=error.ToString();exit=1;Console.Error.WriteLine(failure);}
  finally{window.DestroyHandle();}
  var report=new{kind="Actual Windows OS clipboard, owned synthetic fixtures; no Excel UI or workbook",passed=results.Count,failed=exit==0?0:1,productDllSha256=Hash(File.ReadAllBytes(typeof(ClipboardReader).Assembly.Location)),cases=results.ToArray(),failure};File.WriteAllText(Path.Combine(output,"non-excel-clipboard-results.json"),new JavaScriptSerializer().Serialize(report),new UTF8Encoding(false));Console.WriteLine("RESULT: "+results.Count+" passed; "+(exit==0?0:1)+" failed");return exit;
 }
}
