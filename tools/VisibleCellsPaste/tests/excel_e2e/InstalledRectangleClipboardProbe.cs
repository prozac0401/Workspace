using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using VisibleCellsPaste;

// Run in the ordinary desktop context after the harness has opened its own startup fixture.
// The harness owns Excel launch/close. This probe neither launches nor closes applications,
// changes add-in registration, saves the workbook, nor clicks through confirmation dialogs.
internal static class InstalledRectangleClipboardProbe
{
    [DllImport("user32.dll", SetLastError = true)] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr GetClipboardOwner();
    [DllImport("kernel32.dll")] static extern void SetLastError(uint error);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr GetProcessWindowStation();
    [DllImport("user32.dll", SetLastError = true)] static extern IntPtr GetThreadDesktop(uint thread);
    [DllImport("user32.dll", EntryPoint = "GetUserObjectInformationW", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder data, uint bytes, out uint needed);
    static string report;
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    static void Log(string message)
    {
        Console.WriteLine(message);
        if (report != null) File.AppendAllText(report, message + Environment.NewLine, new UTF8Encoding(false));
    }
    static dynamic Range(ComScope scope, object sheet, string address)
    { return scope.Own(((dynamic)sheet).Range[address]); }
    static void HideRow(ComScope scope, object sheet, string address)
    { dynamic range = Range(scope, sheet, address); dynamic row = scope.Own(range.EntireRow); row.Hidden = true; }
    static void HideColumn(ComScope scope, object sheet, string address)
    { dynamic range = Range(scope, sheet, address); dynamic column = scope.Own(range.EntireColumn); column.Hidden = true; }
    static bool Hidden(ComScope scope, object sheet, string address, bool row)
    {
        dynamic range = Range(scope, sheet, address);
        dynamic axis = scope.Own(row ? range.EntireRow : range.EntireColumn);
        return Convert.ToBoolean(axis.Hidden, CultureInfo.InvariantCulture);
    }
    static void RequireOwnedWorkbook(dynamic books, dynamic book, string fixture)
    {
        Check((int)books.Count == 1, "Unexpected workbook count; probe refused.");
        Check(String.Equals((string)book.FullName, fixture, StringComparison.OrdinalIgnoreCase), "Workbook identity changed; probe refused.");
        Check(!(bool)book.ReadOnly, "Synthetic workbook is read-only.");
    }
    static string UserObjectName(IntPtr handle)
    {
        var name = new StringBuilder(256); uint needed;
        return GetUserObjectInformation(handle, 2, name, (uint)(name.Capacity * 2), out needed)
            ? name.ToString() : "unavailable(error=" + Marshal.GetLastWin32Error() + ")";
    }
    static void RequireOwnedCopy(dynamic app, int expectedPid)
    {
        for (int attempt = 0; attempt < 21; attempt++)
        {
            int mode = Convert.ToInt32(app.CutCopyMode, CultureInfo.InvariantCulture);
            SetLastError(0);
            IntPtr owner = GetClipboardOwner();
            int ownerError = Marshal.GetLastWin32Error();
            uint ownerPid = 0; int pidError = 0;
            if (owner != IntPtr.Zero)
            {
                SetLastError(0); GetWindowThreadProcessId(owner, out ownerPid);
                pidError = Marshal.GetLastWin32Error();
            }
            Log("COPY_STATE attempt=" + attempt + "; owner=0x" + owner.ToInt64().ToString("X", CultureInfo.InvariantCulture)
                + "; ownerPid=" + ownerPid + "; expectedPid=" + expectedPid + "; CutCopyMode=" + mode
                + "; sequence=" + NativeClipboard.GetClipboardSequenceNumber() + "; ownerLastError=" + ownerError + "; pidLastError=" + pidError);
            if (ownerPid == (uint)expectedPid && mode == 1) return;
            // Only an already active copy with no owner yet is a plausible short transition.
            // Never wait through access denial, a foreign owner, or inactive/cut state; never read their data.
            if (attempt == 20 || mode != 1 || owner != IntPtr.Zero || ownerError != 0) break;
            Thread.Sleep(100);
        }
        throw new Exception("Real Excel clipboard ownership/copy state mismatch; no clipboard content was read.");
    }
    internal static int RunOwned(int pid, string fixture, string output)
    { return Main(new[] { pid.ToString(CultureInfo.InvariantCulture), fixture, output }); }
    [STAThread] static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        try
        {
            Check(args.Length == 3, "Usage: InstalledRectangleClipboardProbe.exe OWNED_EXCEL_PID EXACT_STARTUP_FIXTURE.xlsx REPORT.txt");
            int pid = Int32.Parse(args[0], CultureInfo.InvariantCulture);
            string fixture = Path.GetFullPath(args[1]);
            Check(Path.GetFileName(fixture).StartsWith("VCP-installed-startup-", StringComparison.OrdinalIgnoreCase) && File.Exists(fixture), "Existing synthetic startup fixture required.");
            report = Path.GetFullPath(args[2]);
            Check(!String.Equals(fixture, report, StringComparison.OrdinalIgnoreCase), "Report must not overwrite the workbook.");
            Directory.CreateDirectory(Path.GetDirectoryName(report));
            File.WriteAllText(report, "scope=owned synthetic workbook; real Excel Range.Copy; installed Paste callback; no UI click claim" + Environment.NewLine, new UTF8Encoding(false));
            using (var scope = new ComScope())
            {
                dynamic app = scope.Own((object)ExcelProbe.Attach(pid));
                uint actualPid;
                GetWindowThreadProcessId(new IntPtr(Convert.ToInt64(app.Hwnd, CultureInfo.InvariantCulture)), out actualPid);
                Check(actualPid == (uint)pid, "Excel PID identity mismatch.");
                dynamic books = scope.Own(app.Workbooks);
                Check((int)books.Count == 1, "Expected exactly the owned workbook.");
                dynamic book = scope.Own(books.Item(1));
                RequireOwnedWorkbook(books, book, fixture);
                dynamic sheets = scope.Own(book.Worksheets);
                Check((int)sheets.Count == 1, "Expected exactly the synthetic startup worksheet.");
                dynamic sheet = scope.Own(sheets.Item(1));
                Check((string)sheet.Name == "VcpOwnedStartup" && (string)Range(scope, sheet, "A1").Value2 == "Owned startup fixture", "Synthetic fixture marker mismatch.");
                dynamic addins = scope.Own(app.COMAddIns);
                dynamic addin = scope.Own(addins.Item("Workspace.VisibleCellsPaste"));
                Check((bool)addin.Connect, "Installed add-in is not already connected.");
                dynamic callback = scope.Own(addin.Object);
                string initial = callback.GetDiagnostics();
                Check(initial.Contains("connected=True") && initial.Contains("clicks=0") && initial.Contains("outcome=idle"), "Fresh installed add-in required: " + initial);
                Log("PASS owned identity; Excel=" + app.Version + "; Build=" + app.Build + "; " + initial);
                using (var probeProcess = Process.GetCurrentProcess())
                    Log("CONTEXT probePid=" + probeProcess.Id + "; session=" + probeProcess.SessionId
                        + "; station=" + UserObjectName(GetProcessWindowStation()) + "; desktop=" + UserObjectName(GetThreadDesktop(GetCurrentThreadId()))
                        + "; ExcelHwnd=" + app.Hwnd + "; ExcelVisible=" + app.Visible);

                dynamic grid = Range(scope, sheet, "A1:J10");
                var fixtureValues = new object[10, 10];
                for (int r = 0; r < 10; r++) for (int c = 0; c < 10; c++) fixtureValues[r, c] = 1000.0 + r * 10 + c;
                fixtureValues[0, 0] = "Owned startup fixture";
                grid.Value2 = fixtureValues;
                dynamic source = Range(scope, sheet, "A2:D4");
                source.Value2 = new object[,] { { 11.0, 12.0, 13.0, 14.0 }, { 21.0, 22.0, 23.0, 24.0 }, { 31.0, 32.0, 33.0, 34.0 } };
                dynamic target = Range(scope, sheet, "E6:H8");
                target.NumberFormat = "0.00";
                Range(scope, sheet, "F6:F8").Formula2 = "=600+ROW()";
                Range(scope, sheet, "E7:H7").Formula2 = "=700+COLUMN()";
                HideRow(scope, sheet, "A3"); HideColumn(scope, sheet, "B1");
                HideRow(scope, sheet, "A7"); HideColumn(scope, sheet, "F1");
                object[,] before = (object[,])grid.Formula2;
                sheet.Activate();
                source.Copy();
                RequireOwnedCopy(app, pid);
                Log("PASS real Range.Copy; source=A2:D4; hidden row=3; hidden column=B; clipboard owner PID=" + pid);
                // Only synthetic clipboard bytes are recorded, including on parser rejection.
                File.WriteAllBytes(report + ".synthetic.xml.bin", NativeClipboard.ReadFormatBytes("XML Spreadsheet"));
                ClipboardSnapshot copied = ClipboardReader.ReadSnapshot(1);
                double[] expected = { 11, 13, 14, 31, 33, 34 };
                Check(copied.ShapeIsVerified && copied.SourceRows == 2 && copied.SourceColumns == 3 && copied.Items.Count == 6,
                    "Clipboard shape mismatch: " + copied.SourceRows + "x" + copied.SourceColumns + "; items=" + copied.Items.Count);
                for (int i = 0; i < expected.Length; i++) Check(copied.Items[i].Equals(CellValue.Number(expected[i])), "Clipboard row-major value mismatch at index " + i);
                Log("PASS actual clipboard snapshot=2x3; values=11,13,14,31,33,34; " + copied.Evidence);
                RequireOwnedWorkbook(books, book, fixture);
                target.Select();
                Check(copied.ClipboardSequence == NativeClipboard.GetClipboardSequenceNumber(), "Clipboard changed before installed Paste.");
                Log("BEGIN installed Paste callback; target=E6:H8; hidden row=7; hidden column=F");
                callback.Paste(null);
                string diagnostics = "";
                for (int i = 0; i < 100; i++)
                {
                    diagnostics = callback.GetDiagnostics();
                    if (!diagnostics.Contains("outcome=pending")) break;
                    Thread.Sleep(100);
                }
                Check(diagnostics.Contains("clicks=1") && diagnostics.Contains("outcome=success") && diagnostics.Contains("engine=success"), "Installed Paste did not complete: " + diagnostics);
                Log("PASS installed Paste; " + diagnostics);
                RequireOwnedWorkbook(books, book, fixture);
                object[,] after = (object[,])grid.Formula2;
                int[] rows = { 6, 8 }, columns = { 5, 7, 8 };
                for (int r = 0; r < rows.Length; r++) for (int c = 0; c < columns.Length; c++)
                    before[rows[r], columns[c]] = expected[r * columns.Length + c];
                for (int r = 1; r <= 10; r++) for (int c = 1; c <= 10; c++)
                    Check(Object.Equals(before[r, c], after[r, c]), "Value/formula preservation mismatch at row " + r + ", column " + c);
                Check((string)target.NumberFormat == "0.00", "Target number formats changed.");
                Check(Hidden(scope, sheet, "A3", true) && Hidden(scope, sheet, "B1", false) && Hidden(scope, sheet, "A7", true) && Hidden(scope, sheet, "F1", false), "Hidden states changed.");
                Log("PASS six row-major target values; hidden/outside values and formulas unchanged across A1:J10; target number format and hidden states preserved");
                Log("PASS completed; workbook remains unsaved/open for harness-owned normal cleanup");
            }
            return 0;
        }
        catch (Exception error) { Log("FAIL " + error); return 1; }
        finally { GC.Collect(); GC.WaitForPendingFinalizers(); }
    }
}
