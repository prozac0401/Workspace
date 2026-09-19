using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Security.Cryptography;
using FolderState.Core;

if (!OperatingSystem.IsWindows()) { Console.Error.WriteLine("Windows integration tests require Windows."); return 1; }
if (args.Length == 3 && args[0] == "--interrupt" || args.Length == 4 && args[0] == "--interrupt-mode")
{
    var interrupted = new FolderStateEngine(Path.Combine(AppContext.BaseDirectory, "icons"))
    { TransactionCheckpoint = checkpoint => { if (checkpoint == args[2]) Environment.Exit(77); } };
    var result = args[0] == "--interrupt-mode"
        ? interrupted.ChangeMode(args[1], Enum.Parse<IconMode>(args[3]))
        : interrupted.Set(args[1], WorkStatus.Done);
    return result.Success ? 0 : 1;
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
string IconName(WorkStatus status) => ".folderstate-" + Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(icons,status.Value()+".ico")))).ToLowerInvariant() + ".ico";
string PortablePath(string folder) => Path.Combine(folder, Encoding.Unicode.GetString(ReadDesktop(folder)).Split('\n').Single(s=>s.StartsWith("IconResource=",StringComparison.Ordinal))[13..].Trim().Split(',')[0]);
void EditBackup(string folder, Action<JsonObject> edit, bool legacy = false)
{
    string file=Path.Combine(folder,FolderStateEngine.StateFile), text=File.ReadAllText(file);
    var match=System.Text.RegularExpressions.Regex.Match(text,@"(?m)^Data=([^\r\n]+)");
    var backup=JsonNode.Parse(Convert.FromBase64String(match.Groups[1].Value))!.AsObject(); edit(backup);
    text=text.Replace(match.Value,"Data="+Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(backup)));
    if(legacy) text=text.Replace("Version=2","Version=1");
    Overwrite(file,Utf16(text));
}
void LegacyPortable(string folder)
{
    Ok(engine.Set(folder,WorkStatus.Doing,IconMode.Portable)); string old=PortablePath(folder);
    File.Move(old,Path.Combine(folder,".folderstate.ico"));
    Desktop(folder,Utf16(File.ReadAllText(Path.Combine(folder,"desktop.ini")).Replace(Path.GetFileName(old),".folderstate.ico")));
    EditBackup(folder,b=>{b.Remove("PortableName");b["ManagedDesktop"]=Convert.ToBase64String(ReadDesktop(folder));},true);
}

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
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Doing,IconMode.Portable)); Assert(File.Exists(PortablePath(p)));
    Ok(engine.Set(p,WorkStatus.Done)); Assert(engine.ReadState(p)!.Mode==IconMode.Portable);
    Ok(engine.Set(p,WorkStatus.Done,IconMode.Local)); Assert(Directory.GetFiles(p,"*.ico").Length==0);
    Ok(engine.Reset(p));
});
Test("unowned portable icon never overwritten", () => {
    string p=Folder(); File.WriteAllText(Path.Combine(p,".folderstate.ico"),"mine"); var result=engine.Set(p,WorkStatus.Done,IconMode.Portable);
    Assert(!result.Success && result.ErrorCode=="portable_conflict"); Assert(File.ReadAllText(Path.Combine(p,".folderstate.ico"))=="mine"); Assert(engine.ReadState(p) is null);
});
Test("changed portable icon blocks reset without partial deletion", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Done,IconMode.Portable)); string icon=PortablePath(p); Overwrite(icon,Encoding.UTF8.GetBytes("external"));
    Assert(!engine.Reset(p).Success); Assert(engine.ReadState(p)!.Status==WorkStatus.Done); Assert(File.ReadAllText(icon)=="external");
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
    foreach(var checkpoint in new[]{"journal",IconName(WorkStatus.Done),"desktop.ini",FolderStateEngine.StateFile,"shell","attributes"}) {
        string p=Folder(); var bytes=Utf16("[.ShellClassInfo]\nInfoTip=KEEP\n"); Desktop(p,bytes);
        var faulty=new FolderStateEngine(icons){TransactionCheckpoint=s=>{if(s==checkpoint)throw new IOException("injected");}};
        Assert(!faulty.Set(p,WorkStatus.Done,IconMode.Portable).Success); Assert(ReadDesktop(p).SequenceEqual(bytes));
        Assert(engine.ReadState(p) is null); Assert(Directory.GetFiles(p,"*.ico").Length==0); Assert(!File.Exists(Path.Combine(p,FolderStateEngine.JournalFile)));
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
    foreach (string checkpoint in new[]{"desktop.ini",FolderStateEngine.StateFile,"shell","attributes"}) {
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

Test("portable immutable resources / repeated states / no orphan icons", () => {
    string p=Folder();
    foreach(var status in Enumerable.Range(0,24).Select(i=>(WorkStatus)(i%4))) {
        Ok(engine.Set(p,status,IconMode.Portable)); string icon=PortablePath(p);
        Assert(Path.GetFileName(icon)==IconName(status)); Assert(Directory.GetFiles(p,"*.ico").Length==1);
        Assert(File.ReadAllBytes(icon).SequenceEqual(File.ReadAllBytes(Path.Combine(icons,status.Value()+".ico"))));
    }
    Ok(engine.Reset(p)); Assert(Directory.GetFiles(p,"*.ico").Length==0);
});
Test("legacy portable upgrade / repair / exact reset", () => {
    foreach(var action in new[]{"set","repair","reset"}) {
        string p=Folder(); var original=Utf16("[.ShellClassInfo]\nIconResource=original.ico,0\nInfoTip=keep\n"); Desktop(p,original);
        LegacyPortable(p); var updated=engine.ReadState(p)!.Updated;
        if(action=="set") Ok(engine.Set(p,WorkStatus.Done)); else if(action=="repair") {Ok(engine.Repair(p));Assert(engine.ReadState(p)!.Updated==updated);}
        else Ok(engine.Reset(p));
        Assert(!File.Exists(Path.Combine(p,".folderstate.ico")));
        if(action!="reset") {Assert(File.Exists(PortablePath(p)));Ok(engine.Reset(p));}
        Assert(ReadDesktop(p).SequenceEqual(original)); Assert(Directory.GetFiles(p,"*.ico").Length==0);
    }
});
Test("portable transition and legacy migration rollback at every stage", () => {
    foreach(bool legacy in new[]{false,true})
    foreach(string stage in new[]{"journal","new-icon","old-icon","desktop.ini",FolderStateEngine.StateFile,"shell","attributes"}) {
        string p=Folder(); if(legacy) LegacyPortable(p); else Ok(engine.Set(p,WorkStatus.Doing,IconMode.Portable));
        string old=Path.GetFileName(PortablePath(p)); var before=Directory.GetFiles(p).ToDictionary(f=>Path.GetFileName(f)!,f=>File.ReadAllBytes(f));
        string checkpoint=stage=="new-icon"?IconName(WorkStatus.Done):stage=="old-icon"?old:stage;
        var faulty=new FolderStateEngine(icons){TransactionCheckpoint=s=>{if(s==checkpoint)throw new IOException("injected");}};
        Assert(!faulty.Set(p,WorkStatus.Done).Success);
        Assert(Directory.GetFiles(p).Length==before.Count);
        foreach(var file in before) Assert(File.ReadAllBytes(Path.Combine(p,file.Key!)).SequenceEqual(file.Value));
        Ok(engine.Reset(p));
    }
});
Test("portable process interruption recovers each persisted stage", () => {
    foreach(bool legacy in new[]{false,true})
    foreach(string stage in new[]{"journal","new-icon","old-icon","desktop.ini",FolderStateEngine.StateFile,"shell","attributes"}) {
        string p=Folder(); if(legacy) LegacyPortable(p); else Ok(engine.Set(p,WorkStatus.Doing,IconMode.Portable));
        string old=Path.GetFileName(PortablePath(p)); var before=engine.ReadState(p)!;
        string checkpoint=stage=="new-icon"?IconName(WorkStatus.Done):stage=="old-icon"?old:stage;
        var launch=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};
        if(string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath),"dotnet",StringComparison.OrdinalIgnoreCase)) launch.ArgumentList.Add(typeof(Program).Assembly.Location);
        launch.ArgumentList.Add("--interrupt");launch.ArgumentList.Add(p);launch.ArgumentList.Add(checkpoint);
        using var child=Process.Start(launch)!;Assert(child.WaitForExit(15000));Assert(child.ExitCode==77);
        Ok(engine.Repair(p));Assert(engine.ReadState(p)==before);Assert(Directory.GetFiles(p,"*.ico").Length==1);
        Ok(engine.Reset(p));
    }
});
Test("portable concurrent transitions leave one owned resource", () => {
    string p=Folder();var jobs=Enumerable.Range(0,24).Select(i=>Task.Run(()=>engine.Set(p,(WorkStatus)(i%4),IconMode.Portable))).ToArray();
    Task.WaitAll(jobs);foreach(var job in jobs)Ok(job.Result);
    Assert(Directory.GetFiles(p,"*.ico").Length==1);Assert(Path.GetFileName(PortablePath(p))==IconName(engine.ReadState(p)!.Status));Ok(engine.Reset(p));
});
Test("unowned hash resource is never adopted / locked old icon rolls back", () => {
    string p=Folder();string file=Path.Combine(p,IconName(WorkStatus.Done));File.Copy(Path.Combine(icons,"done.ico"),file);
    Assert(engine.Set(p,WorkStatus.Done,IconMode.Portable).ErrorCode=="portable_conflict");Assert(File.Exists(file));Assert(engine.ReadState(p) is null);
    p=Folder();Ok(engine.Set(p,WorkStatus.Doing,IconMode.Portable));
    using(var locked=new FileStream(PortablePath(p),FileMode.Open,FileAccess.Read,FileShare.Read)) Assert(!engine.Set(p,WorkStatus.Done).Success);
    Assert(engine.ReadState(p)!.Status==WorkStatus.Doing);Assert(Directory.GetFiles(p,"*.ico").Length==1);Ok(engine.Reset(p));
});
Test("unknown state fields and backup properties survive updates / reset is conservative", () => {
    string p=Folder();Ok(engine.Set(p,WorkStatus.Doing,IconMode.Portable));
    EditBackup(p,b=>b["External"]="preserve");File.AppendAllText(Path.Combine(p,FolderStateEngine.StateFile),"[External]\nNote=keep\n",Encoding.Unicode);
    Ok(engine.Set(p,WorkStatus.Done));Ok(engine.Repair(p));string file=Path.Combine(p,FolderStateEngine.StateFile);byte[] before=File.ReadAllBytes(file);
    Assert(File.ReadAllText(file).Contains("Note=keep"));
    EditBackup(p,b=>Assert(b["External"]!.GetValue<string>()=="preserve"));
    before=File.ReadAllBytes(file);Assert(engine.Reset(p).ErrorCode=="metadata_conflict");Assert(File.ReadAllBytes(file).SequenceEqual(before));
});
Test("portable metadata cannot address a business path", () => {
    foreach(string name in new[]{"business.txt","../business.txt",".folderstate-"+new string('g',64)+".ico"}) {
        string p=Folder();Ok(engine.Set(p,WorkStatus.Doing,IconMode.Portable));File.WriteAllText(Path.Combine(p,"business.txt"),"KEEP");EditBackup(p,b=>b["PortableName"]=name);
        Assert(engine.Set(p,WorkStatus.Done).ErrorCode=="invalid_metadata");Assert(engine.Reset(p).ErrorCode=="invalid_metadata");Assert(File.ReadAllText(Path.Combine(p,"business.txt"))=="KEEP");
    }
});

Test("Shell icon update preserves Unicode comma paths and unrelated settings", () => {
    string customIcons=Folder("아이콘, 공백 [test]");
    foreach(var file in Directory.GetFiles(icons,"*.ico"))File.Copy(file,Path.Combine(customIcons,Path.GetFileName(file)));
    var custom=new FolderStateEngine(customIcons);string p=Folder();var before=Utf16(";keep\n[.ShellClassInfo]\nInfoTip=보존\n[Other]\nKey=value\n");Desktop(p,before);
    foreach(var status in Enum.GetValues<WorkStatus>()) {var result=custom.Set(p,status);Ok(result);Assert(result.Warning is null,result.Warning??"");Assert(File.ReadAllText(Path.Combine(p,"desktop.ini")).Contains("InfoTip=보존"));}
    Ok(custom.Reset(p));Assert(ReadDesktop(p).SequenceEqual(before));Assert(!File.GetAttributes(p).HasFlag(FileAttributes.ReadOnly));
});

Test("unknown snapshot format is rejected without losing fields", () => {
    string p=Folder();Ok(engine.Set(p,WorkStatus.Doing));EditBackup(p,b=>b["Desktop"]!["ExternalSnapshotField"]="preserve");
    string file=Path.Combine(p,FolderStateEngine.StateFile);byte[] before=File.ReadAllBytes(file);
    Assert(engine.Set(p,WorkStatus.Done).ErrorCode=="invalid_metadata");Assert(engine.Reset(p).ErrorCode=="invalid_metadata");Assert(File.ReadAllBytes(file).SequenceEqual(before));
});

Test("storage change requires a saved state", () => {
    string p=Folder(); var result=engine.ChangeMode(p,IconMode.Portable);
    Assert(!result.Success && result.ErrorCode=="state_missing"); Assert(engine.ReadState(p) is null);
    Assert(Directory.GetFiles(p).Length==0); Assert(!File.GetAttributes(p).HasFlag(FileAttributes.ReadOnly));
});
Test("storage round trips preserve status and timestamp / exact reset", () => {
    foreach(var status in Enum.GetValues<WorkStatus>()) {
        string p=Folder(); var original=Utf16("[.ShellClassInfo]\nIconResource=original.ico,0\nInfoTip=keep\n");
        Desktop(p,original); var attributes=FileAttributes.Hidden|FileAttributes.ReadOnly;
        File.SetAttributes(Path.Combine(p,"desktop.ini"),attributes); Ok(engine.Set(p,status)); var before=engine.ReadState(p)!;
        foreach(var mode in new[]{IconMode.Portable,IconMode.Portable,IconMode.Local,IconMode.Local}) {
            var result=engine.ChangeMode(p,mode); Ok(result); Assert(result.Action=="change-mode");
            Assert(result.PreviousStatus==status.Value() && result.NewStatus==status.Value());
            Assert(engine.ReadState(p)==before with { Mode=mode });
            Assert(Directory.GetFiles(p,"*.ico").Length==(mode==IconMode.Portable?1:0));
        }
        Ok(engine.Reset(p)); Assert(ReadDesktop(p).SequenceEqual(original));
        Assert(File.GetAttributes(Path.Combine(p,"desktop.ini"))==attributes); Assert(engine.ReadState(p) is null);
        Assert(!File.GetAttributes(p).HasFlag(FileAttributes.ReadOnly));
    }
});
Test("storage change preserves unknown fields / reset stays conservative", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Doing)); var before=engine.ReadState(p)!;
    EditBackup(p,b=>b["External"]="preserve");
    File.AppendAllText(Path.Combine(p,FolderStateEngine.StateFile),"[External]\nNote=keep\n",Encoding.Unicode);
    File.AppendAllText(Path.Combine(p,"desktop.ini"),"[External]\nCustom=keep\n",Encoding.Unicode);
    foreach(var mode in new[]{IconMode.Portable,IconMode.Local}) {
        Ok(engine.ChangeMode(p,mode)); Assert(engine.ReadState(p)==before with { Mode=mode });
        Assert(File.ReadAllText(Path.Combine(p,FolderStateEngine.StateFile)).Contains("Note=keep"));
        Assert(File.ReadAllText(Path.Combine(p,"desktop.ini")).Contains("Custom=keep"));
        EditBackup(p,b=>Assert(b["External"]!.GetValue<string>()=="preserve"));
    }
    byte[] state=File.ReadAllBytes(Path.Combine(p,FolderStateEngine.StateFile));
    Assert(engine.Reset(p).ErrorCode=="metadata_conflict");
    Assert(File.ReadAllBytes(Path.Combine(p,FolderStateEngine.StateFile)).SequenceEqual(state));
});
Test("storage change protects external icon settings and resources", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Done)); var before=engine.ReadState(p)!;
    var external=Utf16("[.ShellClassInfo]\nIconResource=external.ico,0\n"); Desktop(p,external);
    Assert(engine.ChangeMode(p,IconMode.Portable).ErrorCode=="icon_conflict");
    Assert(engine.ReadState(p)==before); Assert(ReadDesktop(p).SequenceEqual(external)); Assert(Directory.GetFiles(p,"*.ico").Length==0);
    p=Folder(); Ok(engine.Set(p,WorkStatus.Done)); before=engine.ReadState(p)!;
    string unowned=Path.Combine(p,IconName(WorkStatus.Done)); File.Copy(Path.Combine(icons,"done.ico"),unowned);
    byte[] desktop=ReadDesktop(p); Assert(engine.ChangeMode(p,IconMode.Portable).ErrorCode=="portable_conflict");
    Assert(engine.ReadState(p)==before); Assert(ReadDesktop(p).SequenceEqual(desktop)); Assert(File.Exists(unowned));
    p=Folder(); Ok(engine.Set(p,WorkStatus.Done,IconMode.Portable)); before=engine.ReadState(p)!;
    string owned=PortablePath(p); Overwrite(owned,Encoding.UTF8.GetBytes("external")); desktop=ReadDesktop(p);
    Assert(engine.ChangeMode(p,IconMode.Local).ErrorCode=="portable_conflict");
    Assert(engine.ReadState(p)==before); Assert(ReadDesktop(p).SequenceEqual(desktop)); Assert(File.ReadAllText(owned)=="external");
});
Test("storage change missing installed icon preserves saved state", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Doing)); var before=engine.ReadState(p)!; byte[] desktop=ReadDesktop(p);
    Assert(new FolderStateEngine(suite).ChangeMode(p,IconMode.Portable).ErrorCode=="icon_missing");
    Assert(engine.ReadState(p)==before); Assert(ReadDesktop(p).SequenceEqual(desktop)); Assert(Directory.GetFiles(p,"*.ico").Length==0);
});
Test("storage transition rollback restores bytes and attributes at every stage", () => {
    foreach(var initial in Enum.GetValues<IconMode>())
    foreach(var checkpoint in new[]{"journal",IconName(WorkStatus.Doing),"desktop.ini",FolderStateEngine.StateFile,"shell","attributes"}) {
        string p=Folder(); Ok(engine.Set(p,WorkStatus.Doing,initial)); var before=engine.ReadState(p)!;
        var files=Directory.GetFiles(p).ToDictionary(f=>Path.GetFileName(f)!,f=>(Bytes:File.ReadAllBytes(f),Attributes:File.GetAttributes(f)));
        var folderAttributes=File.GetAttributes(p);
        var faulty=new FolderStateEngine(icons){TransactionCheckpoint=s=>{if(s==checkpoint)throw new IOException("injected");}};
        Assert(!faulty.ChangeMode(p,initial==IconMode.Local?IconMode.Portable:IconMode.Local).Success);
        Assert(engine.ReadState(p)==before); Assert(Directory.GetFiles(p).Length==files.Count);
        foreach(var file in files) {
            string path=Path.Combine(p,file.Key); Assert(File.ReadAllBytes(path).SequenceEqual(file.Value.Bytes));
            Assert(File.GetAttributes(path)==file.Value.Attributes);
        }
        Assert(File.GetAttributes(p)==folderAttributes); Ok(engine.Reset(p));
    }
});
Test("storage process interruption recovers every persisted stage", () => {
    foreach(var initial in Enum.GetValues<IconMode>())
    foreach(var checkpoint in new[]{"journal",IconName(WorkStatus.Doing),"desktop.ini",FolderStateEngine.StateFile,"shell","attributes"}) {
        string p=Folder(); Ok(engine.Set(p,WorkStatus.Doing,initial)); var before=engine.ReadState(p)!;
        var launch=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true};
        if(string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath),"dotnet",StringComparison.OrdinalIgnoreCase)) launch.ArgumentList.Add(typeof(Program).Assembly.Location);
        launch.ArgumentList.Add("--interrupt-mode"); launch.ArgumentList.Add(p); launch.ArgumentList.Add(checkpoint);
        launch.ArgumentList.Add((initial==IconMode.Local?IconMode.Portable:IconMode.Local).ToString());
        using var child=Process.Start(launch)!; Assert(child.WaitForExit(15000),"interrupt child timed out"); Assert(child.ExitCode==77);
        Assert(File.Exists(Path.Combine(p,FolderStateEngine.JournalFile))); Ok(engine.Repair(p)); Assert(engine.ReadState(p)==before);
        Assert(!File.Exists(Path.Combine(p,FolderStateEngine.JournalFile)));
        Assert(Directory.GetFiles(p,"*.ico").Length==(initial==IconMode.Portable?1:0)); Ok(engine.Reset(p));
    }
});
Test("concurrent storage changes preserve saved state and one owned resource", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Issue)); var before=engine.ReadState(p)!;
    var jobs=Enumerable.Range(0,24).Select(i=>Task.Run(()=>engine.ChangeMode(p,(IconMode)(i%2)))).ToArray();
    Task.WaitAll(jobs); foreach(var job in jobs) Ok(job.Result);
    var after=engine.ReadState(p)!; Assert(after.Status==before.Status && after.Updated==before.Updated);
    Assert(Directory.GetFiles(p,"*.ico").Length==(after.Mode==IconMode.Portable?1:0));
    if(after.Mode==IconMode.Portable) Assert(Path.GetFileName(PortablePath(p))==IconName(after.Status));
    Ok(engine.Reset(p)); Assert(Directory.GetFiles(p).Length==0);
});
Test("storage change reads latest status after a concurrent state change", () => {
    string p=Folder(); Ok(engine.Set(p,WorkStatus.Todo));
    using var entered=new ManualResetEventSlim(); using var release=new ManualResetEventSlim();
    var waiting=new FolderStateEngine(icons){TransactionCheckpoint=s=>{if(s=="journal"){entered.Set();Assert(release.Wait(5000),"set release timed out");}}};
    var set=Task.Run(()=>waiting.Set(p,WorkStatus.Done)); Assert(entered.Wait(5000),"set did not reach journal");
    var change=Task.Run(()=>engine.ChangeMode(p,IconMode.Portable)); release.Set();
    Task.WaitAll(set,change); Ok(set.Result); Ok(change.Result);
    Assert(change.Result.PreviousStatus=="done" && change.Result.NewStatus=="done");
    Assert(engine.ReadState(p)!.Status==WorkStatus.Done && engine.ReadState(p)!.Mode==IconMode.Portable); Ok(engine.Reset(p));
});
Test("legacy portable storage change preserves state and exact reset", () => {
    foreach(var mode in Enum.GetValues<IconMode>()) {
        string p=Folder(); var original=Utf16("[.ShellClassInfo]\nIconResource=original.ico,0\nInfoTip=keep\n"); Desktop(p,original);
        LegacyPortable(p); var before=engine.ReadState(p)!; Ok(engine.ChangeMode(p,mode));
        Assert(engine.ReadState(p)==before with { Mode=mode }); Assert(!File.Exists(Path.Combine(p,".folderstate.ico")));
        Assert(Directory.GetFiles(p,"*.ico").Length==(mode==IconMode.Portable?1:0));
        Ok(engine.Reset(p)); Assert(ReadDesktop(p).SequenceEqual(original)); Assert(Directory.GetFiles(p,"*.ico").Length==0);
    }
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
