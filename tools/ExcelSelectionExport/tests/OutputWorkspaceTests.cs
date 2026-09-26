using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using ExcelSelectionExport;

// Compiles together with OutputWorkspace.cs. This suite uses managed fakes and
// synthetic temporary files only; it never starts or attaches to Excel.
class OutputWorkspaceTests
{
    static int checks;
    static string suiteRoot;
    static void Assert(bool value, string label)
    {
        if (!value) throw new Exception(label);
        checks++;
        Console.WriteLine("PASS " + label);
    }
    static bool Fails(Action action)
    {
        try { action(); return false; }
        catch (Exception) { return true; }
    }
    static OutputWorkspace Workspace(WorkspaceFakeApplication source, WorkspaceFakeApplication worker,
        List<object> released, Action<string> delete)
    {
        return new OutputWorkspace(source, delegate { return worker; },
            delegate(object value) { if (value != null) released.Add(value); }, suiteRoot, delete);
    }
    static int Main()
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        suiteRoot = Path.Combine(Path.GetTempPath(), "Workspace", "ExcelSelectionExportTests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(suiteRoot);
        try
        {
            var source = new WorkspaceFakeApplication();
            var worker = new WorkspaceFakeApplication();
            var released = new List<object>();
            var workspace = Workspace(source, worker, released, File.Delete);
            Assert(Object.ReferenceEquals(workspace.Application, worker), "fresh worker is exposed to the writer");
            Assert(!worker.Visible && !worker.EnableEvents && !worker.DisplayAlerts && !worker.Interactive && !worker.ScreenUpdating,
                "only the worker is hidden and guarded");
            Assert(source.FlagWrites == 0 && source.QuitCalls == 0 && !released.Contains(source), "source application remains untouched");
            worker.Books.Count = 1;
            var book = new WorkspaceFakeWorkbook(worker);
            string template = workspace.SaveTemplate(book);
            string directory = Path.GetDirectoryName(template);
            Assert(File.Exists(template) && Path.GetFileName(template) == "Selection.xlsx" && Path.GetDirectoryName(directory) == suiteRoot,
                "template uses a unique owned directory under the supplied root");
            Assert(book.Format == 51 && !book.ReadOnlyRecommended && !book.CreateBackup && !book.AddToMru,
                "template is xlsx without backup or recent-file entry");
            Assert(Fails(delegate { workspace.SaveTemplate(book); }) && book.SaveCalls == 1, "second save never overwrites a template");
            worker.Books.Count = 0; // the engine closes and releases its workbook first
            workspace.CloseApplication();
            Assert(worker.QuitCalls == 1 && File.Exists(template), "worker closes before the template is imported into the source");
            Assert(Fails(delegate { object ignored = workspace.Application; }), "closed worker cannot be acquired again");
            workspace.Dispose();
            Assert(!File.Exists(template) && !Directory.Exists(directory), "successful disposal removes the exact template and empty directory");
            workspace.Dispose();
            Assert(worker.QuitCalls == 1, "repeated disposal never quits twice");

            var alias = new WorkspaceFakeApplication();
            var aliasReleases = new List<object>();
            Assert(Fails(delegate { Workspace(alias, alias, aliasReleases, File.Delete); })
                && alias.FlagWrites == 0 && alias.QuitCalls == 0 && aliasReleases.Count == 0,
                "a factory returning the source is rejected without touching it");
            Assert(Fails(delegate
            {
                new OutputWorkspace(source, delegate { throw new InvalidOperationException("synthetic activation failure"); },
                    delegate(object value) { throw new Exception("nothing was acquired"); }, suiteRoot, File.Delete);
            }), "activation failure does not require an application cleanup");

            var startupWorker = new WorkspaceFakeApplication { FailFlag = "ScreenUpdating" };
            var startupReleases = new List<object>();
            Assert(Fails(delegate { Workspace(source, startupWorker, startupReleases, File.Delete); })
                && startupWorker.QuitCalls == 1 && startupReleases.Contains(startupWorker),
                "a partial guard failure quits and releases the empty owned worker");
            var occupiedStartup = new WorkspaceFakeApplication();
            occupiedStartup.Books.Count = 1;
            var occupiedReleases = new List<object>();
            Assert(Fails(delegate { Workspace(source, occupiedStartup, occupiedReleases, File.Delete); })
                && occupiedStartup.QuitCalls == 0 && occupiedStartup.FlagWrites == 0 && !occupiedReleases.Contains(occupiedStartup),
                "unexpected startup documents are neither hidden nor closed nor released");

            var foreignWorker = new WorkspaceFakeApplication();
            var foreignWorkspace = Workspace(source, foreignWorker, new List<object>(), File.Delete);
            var sourceBook = new WorkspaceFakeWorkbook(source);
            Assert(Fails(delegate { foreignWorkspace.SaveTemplate(sourceBook); }) && sourceBook.SaveCalls == 0,
                "a source or unrelated workbook cannot be saved as the template");
            foreignWorkspace.Dispose();

            var saveWorker = new WorkspaceFakeApplication();
            var saveWorkspace = Workspace(source, saveWorker, new List<object>(), File.Delete);
            saveWorker.Books.Count = 1;
            var brokenBook = new WorkspaceFakeWorkbook(saveWorker) { FailAfterWrite = true };
            Assert(Fails(delegate { saveWorkspace.SaveTemplate(brokenBook); })
                && brokenBook.LastPath != null && !File.Exists(brokenBook.LastPath) && !Directory.Exists(Path.GetDirectoryName(brokenBook.LastPath)),
                "failed SaveAs removes its partial file and owned directory");
            saveWorker.Books.Count = 0;
            saveWorkspace.Dispose();

            var retryWorker = new WorkspaceFakeApplication { FailQuits = 1 };
            var retryWorkspace = Workspace(source, retryWorker, new List<object>(), File.Delete);
            Assert(Fails(delegate { retryWorkspace.CloseApplication(); }) && Object.ReferenceEquals(retryWorkspace.Application, retryWorker),
                "a failed Quit retains the owned application for retry");
            retryWorkspace.Dispose();
            retryWorkspace.Dispose();
            Assert(retryWorker.QuitCalls == 2, "disposal retries a failed Quit exactly once after recovery");

            int deletions = 0;
            var deleteWorker = new WorkspaceFakeApplication();
            var deleteWorkspace = Workspace(source, deleteWorker, new List<object>(), delegate(string value)
            {
                deletions++;
                if (deletions == 1) throw new IOException("synthetic sharing failure");
                File.Delete(value);
            });
            string retryTemplate = deleteWorkspace.SaveTemplate(new WorkspaceFakeWorkbook(deleteWorker));
            Assert(Fails(delegate { deleteWorkspace.Dispose(); }) && File.Exists(retryTemplate) && deleteWorker.QuitCalls == 1,
                "file cleanup failure is reported after independent worker shutdown");
            deleteWorkspace.Dispose();
            deleteWorkspace.Dispose();
            Assert(!File.Exists(retryTemplate) && !Directory.Exists(Path.GetDirectoryName(retryTemplate))
                && deletions == 2 && deleteWorker.QuitCalls == 1, "later disposal retries only unfinished file cleanup");

            var extraWorker = new WorkspaceFakeApplication();
            var extraWorkspace = Workspace(source, extraWorker, new List<object>(), File.Delete);
            string extraTemplate = extraWorkspace.SaveTemplate(new WorkspaceFakeWorkbook(extraWorker));
            string extraDirectory = Path.GetDirectoryName(extraTemplate);
            string unexpectedFile = Path.Combine(extraDirectory, "unexpected.txt");
            File.WriteAllText(unexpectedFile, "must be preserved");
            Assert(Fails(delegate { extraWorkspace.Dispose(); }) && !File.Exists(extraTemplate) && File.Exists(unexpectedFile),
                "directory cleanup never recursively removes an unexpected file");
            File.Delete(unexpectedFile); // this test created the marker
            extraWorkspace.Dispose();
            Assert(!Directory.Exists(extraDirectory), "empty directory cleanup can be retried after external obstruction ends");

            var occupiedWorker = new WorkspaceFakeApplication();
            var occupiedRuntimeReleases = new List<object>();
            var occupiedWorkspace = Workspace(source, occupiedWorker, occupiedRuntimeReleases, File.Delete);
            occupiedWorker.Books.Count = 1;
            Assert(Fails(delegate { occupiedWorkspace.Dispose(); }) && occupiedWorker.QuitCalls == 0
                && !occupiedRuntimeReleases.Contains(occupiedWorker), "disposal refuses to quit or release a worker containing a document");
            occupiedWorker.Books.Count = 0;
            occupiedWorkspace.Dispose();
            Assert(occupiedWorker.QuitCalls == 1, "worker shutdown can be retried after the engine closes its document");
            Assert(Directory.GetFileSystemEntries(suiteRoot).Length == 0, "all synthetic template directories were removed");
            Console.WriteLine("PASS " + checks + " output workspace lifecycle checks");
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
        finally
        {
            // Never recurse, including on a failed test. Preserve unexpected files
            // as diagnostic evidence instead of deleting outside a known leaf.
            if (Directory.Exists(suiteRoot) && Directory.GetFileSystemEntries(suiteRoot).Length == 0)
                Directory.Delete(suiteRoot, false);
        }
    }
}

public sealed class WorkspaceFakeBooks
{
    public int Count;
}
public sealed class WorkspaceFakeApplication
{
    bool visible = true, events = true, alerts = true, interactive = true, screen = true;
    public readonly WorkspaceFakeBooks Books = new WorkspaceFakeBooks();
    public WorkspaceFakeBooks Workbooks { get { return Books; } }
    public int FlagWrites, QuitCalls, FailQuits;
    public string FailFlag;
    void Write(string flag)
    {
        FlagWrites++;
        if (FailFlag == flag) throw new InvalidOperationException("synthetic " + flag + " failure");
    }
    public bool Visible { get { return visible; } set { Write("Visible"); visible = value; } }
    public bool EnableEvents { get { return events; } set { Write("EnableEvents"); events = value; } }
    public bool DisplayAlerts { get { return alerts; } set { Write("DisplayAlerts"); alerts = value; } }
    public bool Interactive { get { return interactive; } set { Write("Interactive"); interactive = value; } }
    public bool ScreenUpdating { get { return screen; } set { Write("ScreenUpdating"); screen = value; } }
    public void Quit()
    {
        QuitCalls++;
        if (FailQuits > 0) { FailQuits--; throw new InvalidOperationException("synthetic Quit failure"); }
    }
}
public sealed class WorkspaceFakeWorkbook
{
    public WorkspaceFakeApplication Application { get; private set; }
    public int SaveCalls, Format;
    public bool ReadOnlyRecommended, CreateBackup, AddToMru, FailAfterWrite;
    public string LastPath;
    public WorkspaceFakeWorkbook(WorkspaceFakeApplication application) { Application = application; }
    public void SaveAs(string filename, int fileFormat, object password, object writePassword,
        bool readOnlyRecommended, bool createBackup, int accessMode, object conflictResolution, bool addToMru)
    {
        SaveCalls++; LastPath = filename; Format = fileFormat;
        ReadOnlyRecommended = readOnlyRecommended; CreateBackup = createBackup; AddToMru = addToMru;
        File.WriteAllText(filename, "synthetic lifecycle fixture");
        if (FailAfterWrite) throw new IOException("synthetic SaveAs failure after creating a partial file");
    }
}
