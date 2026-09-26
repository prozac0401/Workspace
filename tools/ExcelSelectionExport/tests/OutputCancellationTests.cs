// Direct reflection engine integration: this is not an actual menu click test.
// Reads an already prepared, task-owned four-cell fixture; never seeds source
// values or history through COM, closes user documents, or kills a process.
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace ExcelSelectionExport.IntegrationTests
{
    internal static class OutputCancellationTests
    {
        [DllImport("user32.dll")]
        static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        static int checks;
        static readonly BindingFlags Members = BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

        [STAThread]
        static int Main(string[] args)
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            try { return Run(args); }
            finally
            {
                GC.Collect(); GC.WaitForPendingFinalizers();
                GC.Collect(); GC.WaitForPendingFinalizers();
            }
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        static int Run(string[] args)
        {
            object application = null, book = null, selection = null, sheet = null, job = null;
            Process workerProcess = null;
            try
            {
                if (args.Length != 2)
                    throw new ArgumentException("Usage: OutputCancellationTests.exe <owned-fixture.xlsx.pid> <actual-ExcelSelectionExport.AddIn.dll>");
                string marker = Path.GetFullPath(args[0]);
                if (!marker.EndsWith(".xlsx.pid", StringComparison.OrdinalIgnoreCase))
                    throw new ArgumentException("The exact .xlsx.pid marker created by ExcelProbe is required.");
                string fixture = marker.Substring(0, marker.Length - 4);
                if (!File.Exists(fixture) || !File.Exists(marker)) throw new Exception("Owned fixture or PID marker is missing.");
                int pid;
                if (!Int32.TryParse(File.ReadAllText(marker).Trim(), out pid) || pid <= 0)
                    throw new Exception("Invalid owned PID marker.");
                string dll = Path.GetFullPath(args[1]);
                if (!File.Exists(dll) || !String.Equals(Path.GetFileName(dll), "ExcelSelectionExport.AddIn.dll", StringComparison.OrdinalIgnoreCase))
                    throw new ArgumentException("Supply the exact existing product ExcelSelectionExport.AddIn.dll.");
                Assembly payload = Assembly.LoadFrom(dll);
                Type engine = payload.GetType("ExcelSelectionExport.ExportEngine", true);
                Type jobType = engine.GetNestedType("ExportJob", BindingFlags.NonPublic);
                if (jobType == null) throw new MissingMemberException(engine.FullName, "ExportJob");
                ConstructorInfo constructor = jobType.GetConstructor(Members, null, new[] { typeof(object) }, null);
                if (constructor == null) throw new MissingMethodException(jobType.FullName, ".ctor(object)");

                application = ExcelProbe.Attach(pid);
                dynamic app = application;
                uint attachedPid;
                GetWindowThreadProcessId(new IntPtr(Convert.ToInt64(app.Hwnd)), out attachedPid);
                Check(attachedPid == pid, "attached Application matches the exact owned PID");
                object books = null;
                try
                {
                    books = app.Workbooks;
                    Check(Convert.ToInt32(((dynamic)books).Count) == 1, "only the owned fixture is open before the test");
                    book = ((dynamic)books)[1];
                }
                finally { Release(books); }
                Check(String.Equals(Convert.ToString(((dynamic)book).FullName), fixture, StringComparison.OrdinalIgnoreCase),
                    "startup workbook matches the marker path");
                selection = app.Selection;
                Check(selection != null, "current source selection exists");
                object areas = null, selectedBook = null;
                try
                {
                    areas = ((dynamic)selection).Areas;
                    Check(Convert.ToInt32(((dynamic)areas).Count) == 1 && Convert.ToDouble(((dynamic)selection).CountLarge) == 4,
                        "fixture already has one finite four-cell selection; source setup is not performed");
                    sheet = ((dynamic)selection).Worksheet;
                    selectedBook = ((dynamic)sheet).Parent;
                    Check(String.Equals(Convert.ToString(((dynamic)selectedBook).FullName), fixture, StringComparison.OrdinalIgnoreCase),
                        "selected cells belong to the owned fixture");
                }
                finally { Release(selectedBook); Release(areas); }
                Check(Convert.ToBoolean(app.EnableEvents) && Convert.ToBoolean(app.Interactive), "source starts with events and interaction enabled");
                string before = SourceSnapshot(book, selection);
                string globals = GlobalSnapshot(application);
                string tempFolders = TemporaryFolders();
                bool undoBefore = UndoEnabled(application);
                Console.WriteLine("MODE=DIRECT_ENGINE_REFLECTION_OUTPUT_CANCELLATION; NOT_ACTUAL_UI_MENU_CLICK");
                Console.WriteLine("PAYLOAD=" + dll + ";SHA256=" + FileHash(dll) + ";Assembly=" + payload.FullName);
                Console.WriteLine("Excel=" + app.Version + ";Build=" + app.Build + ";sourcePID=" + pid + ";undoBefore=" + undoBefore);

                job = constructor.Invoke(new object[] { application });
                Call(job, "Start");
                var timer = Stopwatch.StartNew();
                bool reachedWorker = false;
                while (timer.ElapsedMilliseconds < 30000)
                {
                    Call(job, "Advance");
                    object workspace = Field(job, "outputWorkspace");
                    object output = Field(job, "output");
                    if (!(bool)Field(job, "sourcePhase") && workspace != null && output != null
                        && !Object.ReferenceEquals(Field(job, "outputApplication"), application))
                    {
                        PropertyInfo workerApplication = workspace.GetType().GetProperty("Application", Members);
                        if (workerApplication == null) throw new MissingMemberException(workspace.GetType().FullName, "Application");
                        // Borrowed reference owned by OutputWorkspace. Do not call
                        // ReleaseComObject on this reference from the test.
                        object worker = workerApplication.GetValue(workspace, null);
                        uint workerPid;
                        GetWindowThreadProcessId(new IntPtr(Convert.ToInt64(((dynamic)worker).Hwnd)), out workerPid);
                        Check(workerPid != 0 && workerPid != attachedPid, "output has an independent owned Excel PID");
                        workerProcess = Process.GetProcessById(checked((int)workerPid));
                        Check(String.Equals(workerProcess.ProcessName, "EXCEL", StringComparison.OrdinalIgnoreCase), "captured output process is Excel");
                        Console.WriteLine("WORKER_REACHED;PID=" + workerPid + ";elapsed_ms=" + timer.ElapsedMilliseconds);
                        worker = null;
                        reachedWorker = true;
                        break;
                    }
                    if ((bool)jobType.GetProperty("Finished", Members).GetValue(job, null))
                    {
                        // Surface an actual engine failure before classifying a
                        // too-fast successful transfer as missed test coverage.
                        Call(job, "Complete");
                        throw new NotRunException("The four-cell export completed before a worker-stage cancellation boundary was observed.");
                    }
                }
                if (!reachedWorker) throw new NotRunException("No worker-stage cancellation boundary was reached within 30 seconds.");
                Call(job, "Cancel");
                Call(job, "Advance");
                bool canceled = false;
                try { Call(job, "Complete"); }
                catch (OperationCanceledException) { canceled = true; }
                Check(canceled, "Complete reports OperationCanceledException after worker-stage cancellation");
                Call(job, "Rollback");
                ((IDisposable)job).Dispose();
                job = null;

                Check(before == SourceSnapshot(book, selection), "source XML, values, formulas, address and Saved state are unchanged");
                Check(globals == GlobalSnapshot(application), "source screen, input, events, alerts, calculation and status are restored");
                Check(WorkbookCount(application) == 1, "source instance still contains only the owned fixture");
                Check(String.Equals(Convert.ToString(((dynamic)book).FullName), fixture, StringComparison.OrdinalIgnoreCase), "original fixture remains open");
                Check(tempFolders == TemporaryFolders(), "product temporary GUID folders match the baseline");
                bool undoAfter = UndoEnabled(application);
                if (undoBefore) Check(undoAfter, "initially enabled native Undo remains enabled after cancellation");
                else Console.WriteLine("NOT_RUN_UNDO_PRESERVATION: native Undo was disabled before the test; cancellation checks are independent.");
                Check(workerProcess != null && workerProcess.WaitForExit(15000), "captured worker exits normally after rollback; no kill is used");
                Console.WriteLine("PASS output-stage direct engine cancellation;assertions=" + checks + ";undoBefore=" + undoBefore + ";undoAfter=" + undoAfter);
                return 0;
            }
            catch (NotRunException error)
            {
                Console.Error.WriteLine("NOT_RUN output-stage cancellation: " + error.Message);
                return 2;
            }
            catch (Exception error)
            {
                Console.Error.WriteLine("FAIL " + error);
                return 1;
            }
            finally
            {
                if (job != null)
                {
                    try { Call(job, "Rollback"); }
                    catch (Exception error) { Console.Error.WriteLine("ROLLBACK_FAILED " + error); }
                    try { ((IDisposable)job).Dispose(); }
                    catch (Exception error) { Console.Error.WriteLine("DISPOSE_FAILED " + error); }
                    job = null;
                }
                if (workerProcess != null) workerProcess.Dispose();
                Release(sheet); Release(selection); Release(book); Release(application);
            }
        }

        static object Field(object instance, string name)
        {
            FieldInfo field = instance.GetType().GetField(name, Members);
            if (field == null) throw new MissingFieldException(instance.GetType().FullName, name);
            return field.GetValue(instance);
        }
        static object Call(object instance, string name)
        {
            MethodInfo method = instance.GetType().GetMethod(name, Members, null, Type.EmptyTypes, null);
            if (method == null) throw new MissingMethodException(instance.GetType().FullName, name);
            try { return method.Invoke(instance, null); }
            catch (TargetInvocationException error) { throw error.InnerException ?? error; }
        }
        static int WorkbookCount(object application)
        {
            object books = null;
            try { books = ((dynamic)application).Workbooks; return Convert.ToInt32(((dynamic)books).Count); }
            finally { Release(books); }
        }
        static bool UndoEnabled(object application)
        {
            object bars = null;
            try { bars = ((dynamic)application).CommandBars; return Convert.ToBoolean(((dynamic)bars).GetEnabledMso("Undo")); }
            finally { Release(bars); }
        }
        static string SourceSnapshot(object bookObject, object rangeObject)
        {
            dynamic book = bookObject, range = rangeObject;
            var text = new StringBuilder();
            object xml = range.Value[11]; // xlRangeValueXMLSpreadsheet, read only
            if (!(xml is string) || String.IsNullOrEmpty((string)xml)) throw new Exception("Source XML snapshot is missing.");
            Append(text, xml); Append(text, range.Value2); Append(text, range.Formula);
            Append(text, range.Address); Append(text, book.FullName); Append(text, book.Saved); Append(text, book.Date1904);
            return Hash(Encoding.UTF8.GetBytes(text.ToString()));
        }
        static string GlobalSnapshot(object application)
        {
            dynamic app = application;
            var text = new StringBuilder();
            Append(text, app.ScreenUpdating); Append(text, app.Interactive); Append(text, app.EnableEvents);
            Append(text, app.DisplayAlerts); Append(text, app.Calculation); Append(text, app.StatusBar);
            return text.ToString();
        }
        static string TemporaryFolders()
        {
            string root = Path.Combine(Path.GetTempPath(), "Workspace", "ExcelSelectionExport");
            if (!Directory.Exists(root)) return String.Empty;
            string[] directories = Directory.GetDirectories(root);
            Array.Sort(directories, StringComparer.OrdinalIgnoreCase);
            var text = new StringBuilder();
            foreach (string directory in directories)
            {
                Guid id;
                if (Guid.TryParseExact(Path.GetFileName(directory), "N", out id)) text.AppendLine(Path.GetFileName(directory));
            }
            return text.ToString();
        }
        static void Append(StringBuilder text, object value)
        {
            Array array = value as Array;
            if (array != null)
            {
                text.Append("array:").Append(array.Rank).Append(':');
                for (int dimension = 0; dimension < array.Rank; dimension++)
                    text.Append(array.GetLowerBound(dimension)).Append('/').Append(array.GetLength(dimension)).Append(':');
                foreach (object item in array) Append(text, item);
                return;
            }
            string rendered = value == null ? "<null>" : value.GetType().FullName + ":" + Convert.ToString(value, CultureInfo.InvariantCulture);
            text.Append(rendered.Length).Append(':').Append(rendered).Append(';');
        }
        static string FileHash(string path) { return Hash(File.ReadAllBytes(path)); }
        static string Hash(byte[] bytes)
        {
            using (SHA256 hash = SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
        }
        static void Check(bool value, string label)
        {
            if (!value) throw new Exception(label);
            checks++; Console.WriteLine("PASS " + label);
        }
        static void Release(object value)
        {
            if (value != null && Marshal.IsComObject(value))
                try { Marshal.ReleaseComObject(value); }
                catch (InvalidComObjectException) { }
        }
        sealed class NotRunException : Exception
        {
            internal NotRunException(string message) : base(message) { }
        }
    }
}
