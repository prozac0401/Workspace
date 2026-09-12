using System.Diagnostics;
using System.Text;
using System.Text.Json;
using FolderState.Core;

if (!OperatingSystem.IsWindows()) { Console.Error.WriteLine("Windows integration tests require Windows."); return 1; }
if (args.Length == 3 && args[0] == "--interrupt")
{
    var interrupted = new FolderStateEngine(Path.Combine(AppContext.BaseDirectory, "icons"))
    { TransactionCheckpoint = checkpoint => { if (checkpoint == args[2]) Environment.Exit(77); } };
    return interrupted.Set(args[1], WorkStatus.Done).Success ? 0 : 1;
}
string suite = Path.Combine(Path.GetTempPath(), "FolderState-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(suite);
string icons = Path.Combine(AppContext.BaseDirectory, "icons");
var engine = new FolderStateEngine(icons);
var cases = new List<(string Name, Action Body)>();
int serial = 0;
string Folder(string name = "업무 [한글] 공백") { string p = Path.Combine(suite, (++serial) + "_" + name); Directory.CreateDirectory(p); return p; }
void Assert(bool condition, string message = "assertion failed") { if (!condition) throw new Exception(message); }
void Ok(OperationResult result) { Assert(result.Success, $"{result.ErrorCode}: {result.Message}"); }
void Test(string name, Action action) => cases.Add((name, action));
byte[] Utf16(string text) => [.. Encoding.Unicode.GetPreamble(), .. Encoding.Unicode.GetBytes(text)];
void Overwrite(string file, byte[] bytes) { using var stream = new FileStream(file, FileMode.OpenOrCreate, FileAccess.Write); stream.SetLength(0); stream.Write(bytes); }
void Desktop(string folder, byte[] bytes) => Overwrite(Path.Combine(folder, "desktop.ini"), bytes);
byte[] ReadDesktop(string folder) => File.ReadAllBytes(Path.Combine(folder, "desktop.ini"));

Test("four states / Unicode / spaces / files unchanged", () => {
    string p = Folder(); string business = Path.Combine(p, "실제 업무.txt"); File.WriteAllText(business, "KEEP");
    foreach (var state in Enum.GetValues<WorkStatus>()) { Ok(engine.Set(p, state)); Assert(engine.ReadState(p)?.Status == state); }
    Assert(File.ReadAllText(business) == "KEEP"); Assert(Directory.Exists(p));
    Assert(File.GetAttributes(Path.Combine(p, "desktop.ini")).HasFlag(FileAttributes.Hidden | FileAttributes.System));
    Assert(File.GetAttributes(Path.Combine(p, FolderStateEngine.StateFile)).HasFlag(FileAttributes.Hidden | FileAttributes.System));
    Assert(File.GetAttributes(p).HasFlag(FileAttributes.ReadOnly));
    Ok(engine.Reset(p)); Assert(engine.ReadState(p) is null); Assert(!File.Exists(Path.Combine(p, "desktop.ini")));
    Assert(!File.GetAttributes(p).HasFlag(FileAttributes.ReadOnly));
});
Test("desktop exact bytes and attributes restored", () => {
    foreach (var bytes in new[] { Encoding.UTF8.GetBytes(";keep\r\n[.ShellClassInfo]\r\nIconResource=C:\\old.ico,0\r\nInfoTip=안내\r\n[ViewState]\r\nMode=4\r\n"), Utf16("[.ShellClassInfo]\nIconFile=old.ico\nIconIndex=2\nLocalizedResourceName=한글\n") }) {
        string p = Folder(); Desktop(p, bytes); var attrs = FileAttributes.Hidden | FileAttributes.ReadOnly; File.SetAttributes(Path.Combine(p, "desktop.ini"), attrs);
        Ok(engine.Set(p, WorkStatus.Doing)); Ok(engine.Set(p, WorkStatus.Done)); Ok(engine.Reset(p));
        Assert(ReadDesktop(p).SequenceEqual(bytes), "original bytes differ"); Assert(File.GetAttributes(Path.Combine(p, "desktop.ini")) == attrs);
    }
});
Test("preexisting folder customization retained", () => {
    string p=Folder(); File.SetAttributes(p, File.GetAttributes(p)|FileAttributes.ReadOnly); Ok(engine.Set(p,WorkStatus.Todo)); Ok(engine.Reset(p)); Assert(File.GetAttributes(p).HasFlag(FileAttributes.ReadOnly));
});
Test("external unrelated edits survive reset", () => {
    string p = Folder(); Desktop(p, Utf16("[.ShellClassInfo]\r\nIconResource=old.ico,0\r\nInfoTip=original\r\n"));
    Ok(engine.Set(p, WorkStatus.Doing)); File.AppendAllText(Path.Combine(p, "desktop.ini"), "[External]\r\nCustom=keep\r\n", Encoding.Unicode);
    Ok(engine.Reset(p)); string text = Encoding.Unicode.GetString(ReadDesktop(p)); Assert(text.Contains("Custom=keep")); Assert(text.Contains("IconResource=old.ico,0"));
});
Test("external icon edit is protected", () => {
    string p = Folder(); Ok(engine.Set(p, WorkStatus.Done)); Desktop(p, Utf16("[.ShellClassInfo]\r\nIconResource=external.ico,0\r\n"));
    var result = engine.Set(p, WorkStatus.Issue); Assert(!result.Success && result.ErrorCode == "icon_conflict");
    Ok(engine.Reset(p)); Assert(Encoding.Unicode.GetString(ReadDesktop(p)).Contains("external.ico,0"));
});
Test("repair lost desktop / timestamp stable", () => {
    string p = Folder(); Ok(engine.Set(p, WorkStatus.Doing)); var updated=engine.ReadState(p)!.Updated;
    File.Delete(Path.Combine(p,"desktop.ini")); Ok(engine.Repair(p)); Assert(File.Exists(Path.Combine(p,"desktop.ini"))); Assert(engine.ReadState(p)!.Updated==updated);
});
Test("repair local icon after folder copied", () => {
    string a=Folder(), b=Folder(); Ok(engine.Set(a,WorkStatus.Issue));
    foreach (string name in new[]{"desktop.ini",FolderStateEngine.StateFile}) File.Copy(Path.Combine(a,name),Path.Combine(b,name));
    Ok(engine.Repair(b)); Assert(engine.ReadState(b)!.Status==WorkStatus.Issue);
});
Test("portable / mode retained / local transition / reset", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Doing,IconMode.Portable)); Assert(File.Exists(Path.Combine(p,".folderstate.ico")));
    Ok(engine.Set(p,WorkStatus.Done)); Assert(engine.ReadState(p)!.Mode==IconMode.Portable);
    Ok(engine.Set(p,WorkStatus.Done,IconMode.Local)); Assert(!File.Exists(Path.Combine(p,".folderstate.ico")));
    Ok(engine.Reset(p));
});
Test("unowned portable icon never overwritten", () => {
    string p=Folder(); File.WriteAllText(Path.Combine(p,".folderstate.ico"),"mine"); var result=engine.Set(p,WorkStatus.Done,IconMode.Portable);
    Assert(!result.Success && result.ErrorCode=="portable_conflict"); Assert(File.ReadAllText(Path.Combine(p,".folderstate.ico"))=="mine"); Assert(engine.ReadState(p) is null);
});
Test("changed portable icon blocks reset without partial deletion", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Done,IconMode.Portable)); Overwrite(Path.Combine(p,".folderstate.ico"),Encoding.UTF8.GetBytes("external"));
    Assert(!engine.Reset(p).Success); Assert(engine.ReadState(p)!.Status==WorkStatus.Done); Assert(File.ReadAllText(Path.Combine(p,".folderstate.ico"))=="external");
});
Test("malformed / foreign / future metadata preserved", () => {
    foreach (var text in new[]{"broken","[FolderState]\nVersion=99\nStatus=done","[FolderState]\nVersion=1\nStatus=todo\n"}) {
        string p=Folder(); string file=Path.Combine(p,FolderStateEngine.StateFile); File.WriteAllText(file,text);
        Assert(!engine.Set(p,WorkStatus.Done).Success); Assert(!engine.Reset(p).Success); Assert(File.ReadAllText(file)==text);
    }
});
Test("ambiguous desktop is preserved", () => {
    string p=Folder(); var bytes=Utf16("[.ShellClassInfo]\nIconResource=a\nIconResource=b\n"); Desktop(p,bytes);
    Assert(!engine.Set(p,WorkStatus.Done).Success); Assert(ReadDesktop(p).SequenceEqual(bytes));
});
Test("oversized metadata does not allocate without bound", () => {
    string p=Folder(); Desktop(p,new byte[600*1024]); Assert(engine.Set(p,WorkStatus.Done).ErrorCode=="metadata_too_large");
});
Test("missing icon causes no state change", () => {
    string p=Folder(); var result=new FolderStateEngine(suite).Set(p,WorkStatus.Done); Assert(!result.Success); Assert(engine.ReadState(p) is null);
});
Test("fault after each transaction stage restores exact original", () => {
    foreach(var checkpoint in new[]{"journal",".folderstate.ico","desktop.ini",FolderStateEngine.StateFile,"attributes"}) {
        string p=Folder(); var bytes=Utf16("[.ShellClassInfo]\nInfoTip=KEEP\n"); Desktop(p,bytes);
        var faulty=new FolderStateEngine(icons){TransactionCheckpoint=s=>{if(s==checkpoint)throw new IOException("injected");}};
        Assert(!faulty.Set(p,WorkStatus.Done,IconMode.Portable).Success); Assert(ReadDesktop(p).SequenceEqual(bytes));
        Assert(engine.ReadState(p) is null); Assert(!File.Exists(Path.Combine(p,".folderstate.ico"))); Assert(!File.Exists(Path.Combine(p,FolderStateEngine.JournalFile)));
    }
});
Test("failed reset restores previous state", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Done)); var faulty=new FolderStateEngine(icons){TransactionCheckpoint=s=>{if(s=="desktop.ini")throw new IOException("injected");}};
    Assert(!faulty.Reset(p).Success); Assert(engine.ReadState(p)!.Status==WorkStatus.Done); Ok(engine.Reset(p));
});
Test("file lock does not destroy existing state", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Todo)); using(var locked=new FileStream(Path.Combine(p,"desktop.ini"),FileMode.Open,FileAccess.Read,FileShare.None)) Assert(!engine.Set(p,WorkStatus.Done).Success);
    Assert(engine.ReadState(p)!.Status==WorkStatus.Todo);
});
Test("concurrent operations serialized", () => {
    string p=Folder(); var jobs=Enumerable.Range(0,12).Select(i=>Task.Run(()=>engine.Set(p,(WorkStatus)(i%4)))).ToArray();
    Task.WaitAll(jobs); foreach(var job in jobs) Ok(job.Result); Assert(engine.ReadState(p) is not null); Ok(engine.Reset(p));
});
Test("long path above 260 characters", () => {
    string p=Folder(); for(int i=0;i<7;i++) p=Path.Combine(p,new string('a',40)); Directory.CreateDirectory(p);
    Assert(p.Length>260); Ok(engine.Set(p,WorkStatus.Done)); Ok(engine.Reset(p));
});
Test("files not enumerated or modified with 10000 entries", () => {
    string p=Folder(); for(int i=0;i<10000;i++) File.WriteAllText(Path.Combine(p,$"{i}.txt"),"keep");
    var timer=Stopwatch.StartNew(); Ok(engine.Set(p,WorkStatus.Done)); timer.Stop();
    Assert(Directory.GetFiles(p,"*.txt").Length==10000); Assert(File.ReadAllText(Path.Combine(p,"9999.txt"))=="keep");
    Console.WriteLine($"  10000-entry set: {timer.ElapsedMilliseconds} ms (diagnostic; no timing assertion)");
});
Test("mixed batch reports per-folder success", () => {
    string p=Folder(); var cmd=Commands.Parse(["set","done",p,Path.Combine(suite,"missing"),"--json"]); var results=Commands.Run(engine,cmd);
    Assert(results.Length==2&&results[0].Success&&!results[1].Success); Assert(engine.ReadState(p)!.Status==WorkStatus.Done);
});
Test("argument errors rejected", () => {
    foreach(var args in new[]{new[]{"set","done"},new[]{"set","done",suite,"--mode","other"},new[]{"reset",suite,"--mode","local"},new[]{"status",suite,suite}}) {
        bool rejected=false; try{Commands.Parse(args);}catch(StateException){rejected=true;} Assert(rejected);
    }
});
Test("invalid path and root do not mutate", () => {
    Assert(!engine.Set("relative",WorkStatus.Todo).Success); Assert(!engine.Set(Path.GetPathRoot(suite)!,WorkStatus.Todo).Success);
});
Test("JSON audit log emitted outside business folder", () => {
    string p=Folder(), logs=Folder("logs"); Ok(new FolderStateEngine(icons,logs).Set(p,WorkStatus.Done));
    using var json=JsonDocument.Parse(File.ReadAllText(Path.Combine(logs,"operations.jsonl"))); Assert(json.RootElement.GetProperty("action").GetString()=="set");
    Assert(!File.Exists(Path.Combine(p,"operations.jsonl")));
});
Test("process interruption recovers persisted transaction", () => {
    foreach (string checkpoint in new[]{"desktop.ini",FolderStateEngine.StateFile,"attributes"}) {
        string p=Folder(); Ok(engine.Set(p,WorkStatus.Todo)); var before=engine.ReadState(p)!;
        var launch=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};
        if(string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath),"dotnet",StringComparison.OrdinalIgnoreCase)) launch.ArgumentList.Add(typeof(Program).Assembly.Location);
        launch.ArgumentList.Add("--interrupt"); launch.ArgumentList.Add(p); launch.ArgumentList.Add(checkpoint);
        using var child=Process.Start(launch)!; Assert(child.WaitForExit(15000),"interrupt child timed out"); Assert(child.ExitCode==77);
        Assert(File.Exists(Path.Combine(p,FolderStateEngine.JournalFile))); Ok(engine.Repair(p));
        Assert(engine.ReadState(p)==before); Assert(!File.Exists(Path.Combine(p,FolderStateEngine.JournalFile)));
    }
});
Test("hard-linked metadata does not alter business file", () => {
    string p=Folder(); string business=Path.Combine(p,"business.txt"); File.WriteAllText(business,"ORIGINAL");
    Assert(NativeTest.CreateHardLink(Path.Combine(p,FolderStateEngine.StateFile),business,IntPtr.Zero),"hard link setup failed");
    Assert(engine.Set(p,WorkStatus.Done).ErrorCode=="hard_link"); Assert(File.ReadAllText(business)=="ORIGINAL");
});
Test("damaged journal is retained without changing files", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Todo)); byte[] before=ReadDesktop(p);
    string journal=Path.Combine(p,FolderStateEngine.JournalFile); File.WriteAllText(journal,"{broken");
    Assert(engine.Repair(p).ErrorCode=="invalid_journal"); Assert(ReadDesktop(p).SequenceEqual(before)); Assert(File.ReadAllText(journal)=="{broken");
});

int failed=0; var evidence=new List<object>();
foreach(var test in cases) {
    var timer=Stopwatch.StartNew();
    try { test.Body(); Console.WriteLine("PASS "+test.Name); evidence.Add(new{name=test.Name,passed=true,milliseconds=timer.ElapsedMilliseconds}); }
    catch(Exception ex) { failed++; Console.WriteLine("FAIL "+test.Name+"\n"+ex); evidence.Add(new{name=test.Name,passed=false,error=ex.Message}); }
}
string output=Path.GetFullPath(Path.Combine(AppContext.BaseDirectory,"test-results.json"));
File.WriteAllText(output,JsonSerializer.Serialize(new{timestamp=DateTimeOffset.Now,os=Environment.OSVersion.ToString(),total=cases.Count,failed,tests=evidence},new JsonSerializerOptions{WriteIndented=true}));
Console.WriteLine($"{cases.Count-failed}/{cases.Count} passed. Evidence: {output}");
// Only delete this explicitly created test tree; preserve on failure for investigation.
if(failed==0) { foreach(string file in Directory.EnumerateFiles(suite,"*",SearchOption.AllDirectories))File.SetAttributes(file,FileAttributes.Normal); foreach(string dir in Directory.EnumerateDirectories(suite,"*",SearchOption.AllDirectories))File.SetAttributes(dir,FileAttributes.Directory); Directory.Delete(suite,true); }
else Console.WriteLine("Preserved test data: "+suite);
return failed==0?0:1;

internal static class NativeTest
{
    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet=System.Runtime.InteropServices.CharSet.Unicode, SetLastError=true)]
    [return:System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    internal static extern bool CreateHardLink(string newName,string existingName,IntPtr security);
}
