// Manual-assisted API integration. The operator clicks the real progress Cancel
// button; this harness never sends UI input or starts/closes an Excel process.
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

namespace ExcelSelectionExport.IntegrationTests
{
    internal static class CancellationTests
    {
        private delegate bool EnumProc(IntPtr window, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool EnumChildWindows(IntPtr window, EnumProc callback, IntPtr parameter);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder name, int maximum);
        [DllImport("oleacc.dll")] private static extern int AccessibleObjectFromWindow(IntPtr window, uint objectId, ref Guid iid, [MarshalAs(UnmanagedType.IDispatch)] out object result);
        private static dynamic application;
        private static object attachmentWindow, workbooks, startupFixture, addin, automation;
        private static object sourceBook, sourceSheet, sourceRange;
        private static string startupPath, sourceName;
        private static int checks;
        // Set before dispatch; only an observed busy=False permits source cleanup.
        private static bool sourceMayBeInUse;

        [STAThread]
        private static int Main(string[] args)
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            int result = 1;
            try { result = Run(args); }
            finally
            {
                try { ClearReferences(); }
                finally
                {
                    GC.Collect(); GC.WaitForPendingFinalizers();
                    GC.Collect(); GC.WaitForPendingFinalizers();
                }
            }
            return result;
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static int Run(string[] args)
        {
            try
            {
                if (args.Length != 1) throw new ArgumentException("Usage: CancellationTests.exe <owned-fixture.xlsx.pid>");
                string marker = Path.GetFullPath(args[0]);
                if (!marker.EndsWith(".xlsx.pid", StringComparison.OrdinalIgnoreCase))
                    throw new ArgumentException("The exact .xlsx.pid marker created by ExcelProbe is required.");
                startupPath = marker.Substring(0, marker.Length - 4);
                if (!File.Exists(startupPath) || !File.Exists(marker)) throw new Exception("Owned startup fixture or PID marker is missing.");
                int pid;
                if (!Int32.TryParse(File.ReadAllText(marker).Trim(), out pid) || pid <= 0) throw new Exception("Invalid PID marker.");
                application = Attach(pid);
                uint attachedPid;
                GetWindowThreadProcessId(new IntPtr((int)application.Hwnd), out attachedPid);
                if (attachedPid != pid) throw new Exception("Attached process differs from the owned PID.");
                workbooks = application.Workbooks;
                if ((int)((dynamic)workbooks).Count != 1)
                    throw new Exception("Refusing to run: owned process must contain only its startup fixture.");
                startupFixture = ((dynamic)workbooks)[1];
                if (!String.Equals((string)((dynamic)startupFixture).FullName, startupPath, StringComparison.OrdinalIgnoreCase))
                    throw new Exception("Refusing to run: startup workbook does not match the PID marker.");
                object addins = application.COMAddIns;
                try { addin = ((dynamic)addins).Item("Workspace.ExcelSelectionExport"); }
                finally { ReleaseOne(addins); }
                if (!(bool)((dynamic)addin).Connect) throw new Exception("Installed compiled add-in is not connected.");
                automation = ((dynamic)addin).Object;
                if (automation == null) throw new Exception("Installed compiled add-in has no automation object.");
                string initialDiagnostics = (string)((dynamic)automation).GetDiagnostics();
                if (initialDiagnostics.IndexOf("stage=M1;", StringComparison.OrdinalIgnoreCase) >= 0)
                    throw new Exception("M1-only payload detected; install the functional build before cancellation testing.");
                if (initialDiagnostics.IndexOf(";busy=False", StringComparison.Ordinal) < 0)
                    throw new Exception("Add-in is already busy; the harness will not start or cancel another operation.");
                Console.WriteLine("MODE=MANUAL_ASSISTED_API_CANCELLATION; operator clicks the actual progress Cancel button");
                Console.WriteLine("Excel=" + application.Version + ";Build=" + application.Build + ";PID=" + pid);
                Console.WriteLine("DIAGNOSTICS_BEFORE " + initialDiagnostics);
                RunCancellation();
                Console.WriteLine("PASS cancellation; " + checks + " assertions");
                Console.WriteLine("NOT_RUN cancellation at every progress stage, process interruption, context-menu invocation, other Excel instances");
                return 0;
            }
            catch (Exception exception)
            {
                Console.Error.WriteLine("FAIL " + exception);
                try { if (automation != null) Console.Error.WriteLine("DIAGNOSTICS_FAILURE " + ((dynamic)automation).GetDiagnostics()); } catch { }
                return 1;
            }
            finally
            {
                // Only this exact unsaved synthetic workbook is owned. Never close
                // the startup fixture or an unexpected output, even after failure.
                try
                {
                    if (sourceMayBeInUse)
                        Console.Error.WriteLine("PRESERVED_PENDING_SOURCE: engine completion was not confirmed; leave the synthetic source and startup workbook open. UI inspection and manual cleanup are required after the engine stops.");
                    else CloseSyntheticSource();
                }
                catch (Exception exception) { Console.Error.WriteLine("CLEANUP_FAILURE " + exception); throw; }
            }
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void RunCancellation()
        {
            sourceBook = ((dynamic)workbooks).Add(-4167);
            sourceName = (string)((dynamic)sourceBook).Name;
            object sheets = ((dynamic)sourceBook).Worksheets;
            try { sourceSheet = ((dynamic)sheets)[1]; }
            finally { ReleaseOne(sheets); }
            dynamic book = sourceBook, sheet = sourceSheet;
            sheet.Name = "CancelSyntheticSource";
            sourceRange = sheet.Range["A1:CV200"];
            dynamic range = sourceRange;
            var values = new object[200, 100];
            for (int row = 0; row < 200; row++)
                for (int column = 0; column < 100; column++)
                    values[row, column] = row * 100 + column + 1;
            range.Value2 = values;
            range.NumberFormat = "0";
            book.Activate(); sheet.Activate(); range.Select();
            book.Saved = true; // Make accidental source dirtying detectable.
            Check(Convert.ToDouble(range.CountLarge, CultureInfo.InvariantCulture) == 20000, "Exactly 20,000 selected cells, below the >20,000 confirmation boundary");
            Check((int)((dynamic)workbooks).Count == 2, "Only startup and synthetic source exist before callback");
            string beforeXml = SourceXml();
            bool beforeSaved = (bool)book.Saved;
            string beforeGlobals = GlobalSnapshot();
            string beforeStartup = StartupSnapshot();
            int beforeBooks = (int)((dynamic)workbooks).Count;
            Console.WriteLine("SOURCE_SNAPSHOT xml_chars=" + beforeXml.Length + ";saved=" + beforeSaved + ";workbooks=" + beforeBooks);
            Console.WriteLine("WAIT_FOR_PROGRESS_CANCEL");
            Console.Out.Flush();
            var elapsed = Stopwatch.StartNew();
            try
            {
                // A real IDispatch is required by the installed callback signature;
                // null through the DLR becomes VT_EMPTY. No private UI is invoked.
                sourceMayBeInUse = true;
                ((dynamic)automation).Export((object)application);
            }
            finally { Console.WriteLine("CALLBACK_ELAPSED_MS=" + elapsed.ElapsedMilliseconds); }
            string diagnostics = WaitForCompletion(elapsed);
            Console.WriteLine("COMPLETION_ELAPSED_MS=" + elapsed.ElapsedMilliseconds);
            Console.WriteLine("DIAGNOSTICS_AFTER " + diagnostics);
            if (diagnostics.IndexOf(";outcome=success;", StringComparison.Ordinal) >= 0)
                throw new Exception("Cancel was not performed: the export completed successfully before UI cancellation.");
            if (diagnostics.IndexOf(";outcome=error:", StringComparison.Ordinal) >= 0
                || diagnostics.IndexOf(";outcome=display-error:", StringComparison.Ordinal) >= 0)
                throw new Exception("Export failed instead of being canceled: " + diagnostics);
            Check(diagnostics.IndexOf(";outcome=canceled;", StringComparison.Ordinal) >= 0, "Callback reports outcome=canceled");
            Check(diagnostics.IndexOf(";busy=False", StringComparison.Ordinal) >= 0, "Callback reports busy=False");
            Check((int)((dynamic)workbooks).Count == beforeBooks, "Cancellation leaves no output workbook");
            AssertOnlyOwnedWorkbooks();
            Check(String.Equals(beforeXml, SourceXml(), StringComparison.Ordinal), "Source XML values, formulas and formats unchanged");
            Check(beforeSaved == (bool)book.Saved, "Source Saved state unchanged");
            Check(String.Equals(beforeGlobals, GlobalSnapshot(), StringComparison.Ordinal), "Calculation, EnableEvents, Interactive, ScreenUpdating, DisplayAlerts and StatusBar values and types restored");
            Check(String.Equals(beforeStartup, StartupSnapshot(), StringComparison.Ordinal), "Startup fixture metadata unchanged");
            object active = application.ActiveWorkbook;
            try { Check(SameComObject(active, sourceBook), "Synthetic source remains the active workbook; no output is active"); }
            finally { ReleaseOne(active); }
        }

        private static string WaitForCompletion(Stopwatch elapsed)
        {
            string last = "completion not observed";
            while (true)
            {
                try
                {
                    last = (string)((dynamic)automation).GetDiagnostics();
                    if (last.IndexOf(";busy=False", StringComparison.Ordinal) >= 0)
                    {
                        sourceMayBeInUse = false;
                        return last;
                    }
                }
                catch (COMException exception)
                {
                    // Excel can temporarily reject another automation call while
                    // processing its own UI. Retry only those explicit busy codes.
                    uint code = unchecked((uint)exception.ErrorCode);
                    if (code != 0x80010001U && code != 0x8001010AU) throw;
                    last = "Excel COM busy: 0x" + code.ToString("X8", CultureInfo.InvariantCulture);
                }
                if (elapsed.ElapsedMilliseconds >= 120000)
                {
                    Console.Error.WriteLine("TIMEOUT_NEEDS_UI_MANUAL_CLEANUP elapsed_ms=" + elapsed.ElapsedMilliseconds + ";last=" + last);
                    throw new TimeoutException("Engine completion was not observed within 120 seconds. The source is preserved; inspect the progress UI and clean up manually only after the engine stops.");
                }
                System.Threading.Thread.Sleep(50);
            }
        }

        private static string SourceXml()
        {
            object xml = ((dynamic)sourceRange).Value[11]; // xlRangeValueXMLSpreadsheet
            if (!(xml is string) || String.IsNullOrEmpty((string)xml)) throw new Exception("Source XML snapshot is missing.");
            return (string)xml;
        }

        private static string GlobalSnapshot()
        {
            var text = new StringBuilder();
            Append(text, application.Calculation); Append(text, application.EnableEvents);
            Append(text, application.Interactive); Append(text, application.ScreenUpdating);
            Append(text, application.DisplayAlerts); Append(text, application.StatusBar);
            return text.ToString();
        }

        private static string StartupSnapshot()
        {
            dynamic book = startupFixture;
            var text = new StringBuilder();
            Append(text, book.FullName); Append(text, book.Saved); Append(text, book.Date1904);
            return text.ToString();
        }

        private static void Append(StringBuilder text, object value)
        {
            string representation = value == null ? "null" : value.GetType().FullName + ":" + Convert.ToString(value, CultureInfo.InvariantCulture);
            text.Append(representation.Length).Append(':').Append(representation).Append(';');
        }

        private static void AssertOnlyOwnedWorkbooks()
        {
            int startupCount = 0, sourceCount = 0;
            for (int index = 1; index <= (int)((dynamic)workbooks).Count; index++)
            {
                object candidate = ((dynamic)workbooks)[index];
                try
                {
                    if (SameComObject(candidate, startupFixture)) startupCount++;
                    else if (SameComObject(candidate, sourceBook)) sourceCount++;
                    else throw new Exception("Unexpected workbook remains after cancellation; it will not be closed by this harness.");
                }
                finally { ReleaseOne(candidate); }
            }
            Check(startupCount == 1 && sourceCount == 1, "Exactly the original startup and synthetic source workbook objects remain");
        }

        private static bool SameComObject(object left, object right)
        {
            if (left == null || right == null) return false;
            IntPtr a = IntPtr.Zero, b = IntPtr.Zero;
            try { a = Marshal.GetIUnknownForObject(left); b = Marshal.GetIUnknownForObject(right); return a == b; }
            finally { if (a != IntPtr.Zero) Marshal.Release(a); if (b != IntPtr.Zero) Marshal.Release(b); }
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static dynamic Attach(int pid)
        {
            object result = null;
            EnumProc child = delegate(IntPtr window, IntPtr unused)
            {
                var name = new StringBuilder(256); GetClassName(window, name, name.Capacity);
                if (name.ToString() == "EXCEL7")
                {
                    Guid dispatch = new Guid("00020400-0000-0000-C000-000000000046");
                    object native;
                    if (AccessibleObjectFromWindow(window, 0xfffffff0, ref dispatch, out native) == 0) result = native;
                }
                return result == null;
            };
            EnumWindows(delegate(IntPtr window, IntPtr unused)
            {
                uint process; GetWindowThreadProcessId(window, out process);
                if (process == pid) EnumChildWindows(window, child, IntPtr.Zero);
                return result == null;
            }, IntPtr.Zero);
            if (result == null) throw new Exception("No workbook window for owned Excel PID " + pid);
            attachmentWindow = result;
            return ((dynamic)result).Application;
        }

        private static void CloseSyntheticSource()
        {
            if (sourceBook == null) return;
            dynamic book = sourceBook;
            if (!String.IsNullOrEmpty((string)book.Path)
                || String.Equals((string)book.FullName, startupPath, StringComparison.OrdinalIgnoreCase)
                || !String.Equals((string)book.Name, sourceName, StringComparison.Ordinal)
                || SameComObject(sourceBook, startupFixture))
                throw new Exception("Refusing to close source: synthetic workbook ownership check failed.");
            book.Close(false);
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        private static void ClearReferences()
        {
            object range = sourceRange, sheet = sourceSheet, book = sourceBook;
            object api = automation, entry = addin, fixture = startupFixture;
            object books = workbooks, app = application, window = attachmentWindow;
            sourceRange = null; sourceSheet = null; sourceBook = null; automation = null; addin = null;
            startupFixture = null; workbooks = null; application = null; attachmentWindow = null;
            ReleaseOne(range); ReleaseOne(sheet); ReleaseOne(book); ReleaseOne(api); ReleaseOne(entry);
            ReleaseOne(fixture); ReleaseOne(books); ReleaseOne(app); ReleaseOne(window);
        }

        private static void ReleaseOne(object value)
        {
            if (value == null || !Marshal.IsComObject(value)) return;
            try { Marshal.ReleaseComObject(value); } catch (InvalidComObjectException) { }
        }

        private static void Check(bool condition, string label)
        {
            if (!condition) throw new Exception(label);
            checks++; Console.WriteLine("PASS " + label);
        }
    }
}
