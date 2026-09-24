using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using VisibleCellsPaste;

// Read-only system contention proof plus synthetic parser cases. No EmptyClipboard,
// SetClipboardData, Clipboard.SetData, Excel COM, workbook writes or UI input exists here.
class ClipboardAdversarialTests
{
    [DllImport("user32.dll", SetLastError=true)] static extern bool OpenClipboard(IntPtr window);
    [DllImport("user32.dll", SetLastError=true)] static extern bool CloseClipboard();
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateWindowEx(uint extended, string className, string title, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);
    [DllImport("user32.dll", SetLastError=true)] static extern bool DestroyWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr GetOpenClipboardWindow();
    static readonly List<string> results = new List<string>();
    static int passed, failed, skipped;
    static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    static void Test(string name, Action action)
    {
        try { action(); passed++; results.Add(name + " PASS"); }
        catch (Exception error) { failed++; results.Add(name + " FAIL " + error); }
    }
    static void RejectParser(string name, byte[] bytes)
    {
        Test(name, delegate
        {
            string code = null;
            try { SpreadsheetXmlParser.Parse(bytes, 0, "synthetic unsupported format; not an OS clipboard copy"); }
            catch (ValidationException error) { code = error.Code; }
            Check(code != null && code.StartsWith("VCP-XML-", StringComparison.Ordinal), "Unsupported synthetic payload was accepted");
            results.Add("  parser_only_code=" + code);
        });
    }
    static void RejectBusy(string name, Action action)
    {
        Test(name, delegate
        {
            string code = null; var watch = Stopwatch.StartNew();
            try { action(); } catch (ValidationException error) { code = error.Code; }
            watch.Stop();
            Check(code == "VCP-CLIPBOARD-BUSY", "Expected busy refusal, got " + (code ?? "success"));
            Check(watch.ElapsedMilliseconds < 2000, "Reader exceeded bounded2s contention budget");
            results.Add("  code=" + code + ";elapsed_ms=" + watch.ElapsedMilliseconds);
        });
    }
    static int Holder(string readyName, string releaseName)
    {
        using (var ready = EventWaitHandle.OpenExisting(readyName))
        using (var release = EventWaitHandle.OpenExisting(releaseName))
        {
            bool open = false;
            IntPtr window = CreateWindowEx(0, "STATIC", "VCP ReadOnly Clipboard Holder", 0, 0, 0, 0, 0, new IntPtr(-3), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (window == IntPtr.Zero) return 4;
            try
            {
                for (int i = 0; i < 50 && !open; i++) { open = OpenClipboard(window); if (!open) Thread.Sleep(20); }
                if (!open) return 2;
                ready.Set();
                return release.WaitOne(10000) ? 0 : 3;
            }
            finally { if (open) CloseClipboard(); DestroyWindow(window); }
        }
    }
    [STAThread] static int Main(string[] args)
    {
        if (args.Length == 3 && args[0] == "--hold-read-lock") return Holder(args[1], args[2]);
        if (args.Length != 1) throw new ArgumentException("result-file (run from repository root)");
        string file = Path.GetFullPath(args[0]);
        string allowed = Path.GetFullPath(Path.Combine(Environment.CurrentDirectory, "artifacts", "visible-cells-paste")) + Path.DirectorySeparatorChar;
        Check(file.StartsWith(allowed, StringComparison.OrdinalIgnoreCase), "Result must remain in owned repository artifacts");
        Directory.CreateDirectory(Path.GetDirectoryName(file));
        results.Add("No clipboard payload bytes read, saved or replaced. Metadata preservation + native lock contention; synthetic parser cases are not real external-app copies.");
        results.Add("harness_revision=message-only-window-v2");
        results.Add("UTC=" + DateTime.UtcNow.ToString("o") + ";helper_pid=" + Process.GetCurrentProcess().Id);
        RejectParser("R17-parser-plain-text", Encoding.UTF8.GetBytes("alpha\tbeta\r\ngamma"));
        RejectParser("R17-parser-html-table", Encoding.UTF8.GetBytes("<html><body><table><tr><td>85</td></tr></table></body></html>"));
        RejectParser("R17-parser-png", new byte[] {137,80,78,71,13,10,26,10,0,0,0,0});
        var drop = new byte[20 + Encoding.Unicode.GetByteCount("C:\\Synthetic\\fixture.txt\0\0")];
        Buffer.BlockCopy(BitConverter.GetBytes(20), 0, drop, 0, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(1), 0, drop, 16, 4);
        Buffer.BlockCopy(Encoding.Unicode.GetBytes("C:\\Synthetic\\fixture.txt\0\0"), 0, drop, 20, drop.Length - 20);
        RejectParser("R17-parser-file-list", drop);

        bool provenanceOpen = false;
        try
        {
            provenanceOpen = OpenClipboard(IntPtr.Zero);
            if (!provenanceOpen) { skipped++; results.Add("R17-current-provenance NOT_RUN current clipboard already busy"); }
            else
            {
                uint before = NativeClipboard.GetClipboardSequenceNumber(); IntPtr owner = NativeClipboard.GetClipboardOwner();
                uint ownerPid; NativeClipboard.GetWindowThreadProcessId(owner, out ownerPid);
                bool excel = false;
                try { if (ownerPid != 0) using (var process = Process.GetProcessById((int)ownerPid)) excel = String.Equals(process.ProcessName, "EXCEL", StringComparison.OrdinalIgnoreCase); }
                catch (ArgumentException) {} catch (InvalidOperationException) {}
                if (excel) { skipped++; results.Add("R17-current-provenance NOT_RUN owner is Excel; no Excel COM probe performed"); }
                else Test("R17-current-nonExcel-or-no-owner-provenance", delegate
                {
                    string resultCode = null;
                    try { ClipboardReader.ReadSnapshot(1); } catch (ValidationException error) { resultCode = error.Code; }
                    Check(resultCode == "VCP-CLIPBOARD-COPY-UNVERIFIED", "Source provenance did not reject before format access");
                    Check(before == NativeClipboard.GetClipboardSequenceNumber() && owner == NativeClipboard.GetClipboardOwner(), "Read-only provenance probe changed clipboard metadata");
                    results.Add("  owner_class=" + (ownerPid == 0 ? "none" : "non-Excel") + ";code=" + resultCode);
                });
            }
        }
        catch (Exception error) { failed++; results.Add("R17-current-provenance FAIL " + error); }
        finally { if (provenanceOpen) CloseClipboard(); }

        string[] formatsBefore = null; uint sequenceBefore = 0; IntPtr ownerBefore = IntPtr.Zero;
        try { formatsBefore = NativeClipboard.ProbeFormats().ToArray(); sequenceBefore = NativeClipboard.GetClipboardSequenceNumber(); ownerBefore = NativeClipboard.GetClipboardOwner(); }
        catch (ValidationException error) { skipped++; results.Add("R18-lock-cases NOT_RUN preflight " + error.Code); }
        if (formatsBefore != null)
        {
            string id = Guid.NewGuid().ToString("N"), readyName = "Local\\VCP.ReadOnlyClipboard.Ready." + id, releaseName = "Local\\VCP.ReadOnlyClipboard.Release." + id;
            using (var ready = new EventWaitHandle(false, EventResetMode.ManualReset, readyName))
            using (var release = new EventWaitHandle(false, EventResetMode.ManualReset, releaseName))
            {
                Process holder = null;
                try
                {
                    var info = new ProcessStartInfo(Assembly.GetExecutingAssembly().Location, "--hold-read-lock " + readyName + " " + releaseName);
                    info.UseShellExecute = false; info.CreateNoWindow = true; info.WindowStyle = ProcessWindowStyle.Hidden;
                    info.RedirectStandardOutput = true; info.RedirectStandardError = true;
                    holder = Process.Start(info);
                    if (!ready.WaitOne(5000)) throw new Exception("Owned read-lock holder did not become ready");
                    Check(!holder.HasExited, "Read-lock holder already exited");
                    uint lockPid; IntPtr lockWindow = GetOpenClipboardWindow(); NativeClipboard.GetWindowThreadProcessId(lockWindow, out lockPid);
                    Check(lockWindow != IntPtr.Zero && lockPid == (uint)holder.Id, "Read lock is not held by the owned child window");
                    results.Add("  owned_holder_pid=" + holder.Id + ";open_window_pid_verified=true");
                    RejectBusy("R18-native-format-read-contended", delegate { uint sequence; NativeClipboard.ReadFormatBytes("XML Spreadsheet", out sequence); });
                    RejectBusy("R18-native-format-probe-contended", delegate { NativeClipboard.ProbeFormats(); });
                }
                catch (Exception error) { failed++; results.Add("R18-owned-lock-harness FAIL " + error); }
                finally
                {
                    release.Set();
                    if (holder != null)
                    {
                        if (!holder.WaitForExit(12000)) { holder.Kill(); holder.WaitForExit(); failed++; results.Add("R18-holder-cleanup FAIL own child exceeded bounded lifetime"); }
                        else if (holder.ExitCode != 0) { failed++; results.Add("R18-holder-cleanup FAIL exit=" + holder.ExitCode); }
                        holder.Dispose();
                    }
                }
            }
            Test("R18-clipboard-metadata-preserved", delegate
            {
                string[] after = NativeClipboard.ProbeFormats().ToArray();
                Check(sequenceBefore == NativeClipboard.GetClipboardSequenceNumber(), "Clipboard sequence changed; no restoration was attempted");
                Check(ownerBefore == NativeClipboard.GetClipboardOwner(), "Clipboard owner changed; no restoration was attempted");
                Check(formatsBefore.SequenceEqual(after), "Clipboard format inventory changed; no restoration was attempted");
                results.Add("  sequence_unchanged=true;owner_unchanged=true;format_inventory_unchanged=true;format_count=" + after.Length);
            });
        }
        results.Add("SUMMARY passed=" + passed + " failed=" + failed + " not_run=" + skipped);
        File.WriteAllLines(file, results, Encoding.UTF8);
        Console.WriteLine(results[results.Count - 1]);
        return failed != 0 ? 1 : skipped != 0 ? 2 : 0;
    }
}
