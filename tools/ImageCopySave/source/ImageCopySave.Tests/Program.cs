using System.Diagnostics;
using System.Text.Json;
using ImageCopySave.Engine;
namespace ImageCopySave.Tests;
public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        int? worker = ClipboardTests.TryRunWorker(args);
        if (worker != null) return worker.Value;
        TestRunOptions options;
        try { options = TestRunOptions.Parse(args); }
        catch (ArgumentException error)
        {
            Console.Error.WriteLine(error.Message);
            Console.Error.WriteLine("Usage: ImageCopySave.Tests [--require-clipboard] [--report <path>] [--helper <absolute exe path>] [--clipboard-case <name>] [--use-current-clipboard --acknowledge-clipboard-overwrite] | --mode-contract-tests [--report <path>] | --list-clipboard-cases");
            return 64;
        }
        if (options.ListClipboardCases)
        {
            foreach (string name in ClipboardTests.CaseNames) Console.WriteLine(name);
            return 0;
        }
        string? report = options.Report;
        string? helperPath = options.Helper;
        bool requireClipboard = options.RequireClipboard;
        if (helperPath != null)
        {
            if (!Path.IsPathFullyQualified(helperPath) || !File.Exists(helperPath))
            { Console.Error.WriteLine("The specified helper executable must exist at an absolute path."); return 64; }
            Environment.SetEnvironmentVariable("IMAGE_COPY_SAVE_TEST_HELPER", Path.GetFullPath(helperPath));
        }
        using var clipboardSession = ClipboardTests.Configure(options);
        using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
        bool administrator = new System.Security.Principal.WindowsPrincipal(identity).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        int sessionId = Process.GetCurrentProcess().SessionId;
        var results = new List<object>();
        int failed = 0, skipped = 0;
        void Test(string name, Action body)
        {
            var watch = Stopwatch.StartNew();
            try { body(); Console.WriteLine("PASS " + name); results.Add(new { name, status = "PASS", milliseconds = watch.Elapsed.TotalMilliseconds }); }
            catch (TestUnavailableException ex) { skipped++; Console.WriteLine("NOT RUN " + name + " " + ex.Message); results.Add(new { name, status = "NOT RUN", reason = ex.Message }); }
            catch (Exception ex) { failed++; Console.WriteLine("FAIL " + name + " " + ex.GetType().Name + ": " + ex.Message); results.Add(new { name, status = "FAIL", error = ex.GetType().Name, detail = ex.Message }); }
        }
        if (options.ModeContractTests) ClipboardModeContractTests.Register(Test);
        else if (options.ClipboardCase != null) ClipboardTests.Register(Test);
        else
        {
            CoreTests.Register(Test);
            HelperContractTests.Register(Test);
            SafetyTests.Register(Test);
            CodecTests.Register(Test);
            ClipboardTests.Register(Test);
            FileSystemIntegrationTests.Register(Test);
            BoundaryPerformanceTests.Register(Test);
        }
        if (report != null)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(report))!);
            File.WriteAllText(report, JsonSerializer.Serialize(new { timestamp = DateTimeOffset.UtcNow, os = Environment.OSVersion.ToString(), runtime = Environment.Version.ToString(), architecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(), administrator, sessionId, requireClipboard,
                testScope = options.ModeContractTests ? "mode-contracts-no-clipboard-access" : options.ClipboardCase == null ? "full-suite" : "single-clipboard-case",
                selectedClipboardCase = options.ClipboardCase,
                clipboardContext = options.ModeContractTests ? "not-accessed" : options.UseCurrentClipboard ? "current-user-session" : "private-noninteractive-station",
                clipboardOverwriteAcknowledged = options.AcknowledgeClipboardOverwrite,
                clipboardRestoreAttempted = false,
                clipboardCoordinator = ClipboardTests.CoordinatorEvidence,
                processorCount = Environment.ProcessorCount, processorIdentifier = Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER"),
                gcReportedMemoryLimitBytes = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes,
                isolatedFileSystemRequested = Environment.GetEnvironmentVariable("IMAGE_COPY_SAVE_TEST_ISOLATED_FS") == "1",
                filesystemEvidence = FileSystemIntegrationTests.Evidence, boundaryPerformanceEvidence = BoundaryPerformanceTests.Evidence,
                failed, skipped, results }, new JsonSerializerOptions { WriteIndented = true }));
        }
        Console.WriteLine($"RESULT {results.Count - failed - skipped}/{results.Count} passed, {skipped} not run");
        return failed != 0 ? 1 : (requireClipboard || options.ModeContractTests) && skipped > 0 ? 2 : 0;
    }
}
public static class Check
{
    public static void That(bool condition, string message = "Assertion failed") { if (!condition) throw new Exception(message); }
    public static T Throws<T>(Action action) where T : Exception
    {
        try { action(); } catch (T e) { return e; }
        throw new Exception("Expected " + typeof(T).Name);
    }
}

public sealed class TestUnavailableException(string message) : Exception(message);
