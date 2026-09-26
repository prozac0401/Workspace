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
        string? report = null;
        string? helperPath = null;
        bool requireClipboard = false;
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--require-clipboard") requireClipboard = true;
            else if (args[i] == "--helper" && i + 1 < args.Length) helperPath = args[++i];
            else if (args[i] == "--report" && i + 1 < args.Length) report = args[++i];
            else { Console.Error.WriteLine("Usage: ImageCopySave.Tests [--require-clipboard] [--report <path>] [--helper <absolute exe path>]"); return 64; }
        }
        if (helperPath != null)
        {
            if (!Path.IsPathFullyQualified(helperPath) || !File.Exists(helperPath))
            { Console.Error.WriteLine("The specified helper executable must exist at an absolute path."); return 64; }
            Environment.SetEnvironmentVariable("IMAGE_COPY_SAVE_TEST_HELPER", Path.GetFullPath(helperPath));
        }
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
        CoreTests.Register(Test);
        HelperContractTests.Register(Test);
        SafetyTests.Register(Test);
        CodecTests.Register(Test);
        ClipboardTests.Register(Test);
        FileSystemIntegrationTests.Register(Test);
        BoundaryPerformanceTests.Register(Test);
        if (report != null)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(report))!);
            File.WriteAllText(report, JsonSerializer.Serialize(new { timestamp = DateTimeOffset.UtcNow, os = Environment.OSVersion.ToString(), runtime = Environment.Version.ToString(), architecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(), administrator, sessionId, requireClipboard,
                processorCount = Environment.ProcessorCount, processorIdentifier = Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER"),
                gcReportedMemoryLimitBytes = GC.GetGCMemoryInfo().TotalAvailableMemoryBytes,
                isolatedFileSystemRequested = Environment.GetEnvironmentVariable("IMAGE_COPY_SAVE_TEST_ISOLATED_FS") == "1",
                filesystemEvidence = FileSystemIntegrationTests.Evidence, boundaryPerformanceEvidence = BoundaryPerformanceTests.Evidence,
                failed, skipped, results }, new JsonSerializerOptions { WriteIndented = true }));
        }
        Console.WriteLine($"RESULT {results.Count - failed - skipped}/{results.Count} passed, {skipped} not run");
        return failed != 0 ? 1 : requireClipboard && skipped > 0 ? 2 : 0;
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
