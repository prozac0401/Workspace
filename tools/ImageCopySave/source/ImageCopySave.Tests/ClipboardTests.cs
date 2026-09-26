using System.IO;
using System.ComponentModel;
using System.Diagnostics;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using ImageCopySave.Engine;

namespace ImageCopySave.Tests;

/// <summary>All real clipboard mutations happen in a fresh, private noninteractive window station.</summary>
public static partial class ClipboardTests
{
    private static readonly string[] Cases = ["metadata-only", "alpha-roundtrip", "newer-copy", "preparation-preserves", "snapshot-independent", "native-formats", "helper-exit", "lock-and-cancel", "delayed-rendering",
        "product-copy-save-alpha", "product-jpeg-copy", "product-invalid-preserves", "product-empty-save", "product-parallel-save", "product-save-current", "product-worker-cancel", "product-watchdog",
        "product-snapshot-other-copy", "product-corrupt-clipboard", "product-copy-preparation-race", "product-worker-inflight-cancel",
        "product-shell-roundtrip", "product-shell-invoke-guard"];
    private static ImageData Fixture() => new(2, 2, [0, 0, 255, 255, 10, 20, 30, 0, 12, 22, 32, 128, 0, 255, 0, 255]);
    private static string TestExe => Path.Combine(AppContext.BaseDirectory, "ImageCopySave.Tests.exe");
    private static string ActiveStation = "";
    private static string WorkerDirectory = "";

    public static void Register(Action<string, Action> test)
    {
        foreach (string scenario in Cases)
            test("clipboard isolated " + scenario, () => RunIsolated(scenario));
    }

    private static void RunIsolated(string scenario)
    {
        // A missing product executable is a skipped prerequisite, never a simulated pass.
        if (scenario.StartsWith("product-", StringComparison.Ordinal)) HelperProcessTests.EnsureAvailable();
        // The coordinator never reads, writes, saves, or restores the interactive clipboard.
        string directory = Path.Combine(Path.GetTempPath(), "ImageCopySaveTests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        string result = Path.Combine(directory, "result.txt");
        try
        {
            var start = new ProcessStartInfo(TestExe) { UseShellExecute = false, CreateNoWindow = true };
            start.ArgumentList.Add("--clipboard-worker"); start.ArgumentList.Add(scenario); start.ArgumentList.Add(directory);
            using Process child = Process.Start(start) ?? throw new IOException("Unable to start isolated clipboard worker.");
            if (!child.WaitForExit(scenario.StartsWith("product-", StringComparison.Ordinal) ? 40000 : 20000))
            {
                child.Kill(entireProcessTree: true); child.WaitForExit();
                throw new TimeoutException("Isolated clipboard test exceeded its process deadline.");
            }
            string text = File.Exists(result) ? File.ReadAllText(result) : "No worker result; native tests were not completed.";
            if (child.ExitCode == 77) throw new TestUnavailableException(text);
            Check.That(child.ExitCode == 0 && text.StartsWith("PASS ", StringComparison.Ordinal), text);
        }
        finally
        {
            // Only these exact files are created by this test. Never remove arbitrary descendants.
            foreach (string name in new[] { "result.txt", "case.txt", "child.txt", "ready.txt", "stop.txt", "rendered.txt", "source.png" })
                File.Delete(Path.Combine(directory, name));
            HelperProcessTests.Cleanup(directory);
            Directory.Delete(directory);
        }
    }

    public static int? TryRunWorker(string[] args)
    {
        if (args.Length != 3 || !args[0].StartsWith("--clipboard-", StringComparison.Ordinal)) return null;
        WorkerDirectory = args[2];
        const string casePrefix = "--clipboard-case-";
        bool coordinator = args[0] == "--clipboard-worker";
        bool testCase = args[0].StartsWith(casePrefix, StringComparison.Ordinal);
        string output = Path.Combine(WorkerDirectory, coordinator ? "result.txt" : testCase ? "case.txt" : "child.txt");
        bool preflight = coordinator || testCase;
        try
        {
            if (coordinator)
            {
                // This setup process never accesses a clipboard or moves its initialized STA
                // thread to another desktop. The case process starts on the private desktop
                // through STARTUPINFO.lpDesktop, before the CLR/COM can create any windows.
                using var isolation = new PrivateStation();
                ActiveStation = isolation.Name;
                using var worker = Child(casePrefix + args[1]);
                preflight = false;
                uint exitCode = worker.WaitForExit(args[1].StartsWith("product-", StringComparison.Ordinal) ? 30000u : 15000u);
                string caseResult = Path.Combine(WorkerDirectory, "case.txt");
                string text = File.Exists(caseResult) ? File.ReadAllText(caseResult) : "Case worker did not produce a result.";
                if (exitCode == 77)
                {
                    preflight = true;
                    throw new TestUnavailableException(text);
                }
                Check.That(exitCode == 0 && text.StartsWith("PASS ", StringComparison.Ordinal), text);
                File.WriteAllText(output, "PASS " + args[1] + "; private noninteractive station and desktop verified");
            }
            else
            {
                ActiveStation = args[1];
                VerifyPrivateStation(ActiveStation); // Mandatory BEFORE every case/helper's clipboard access.
                Check.That(ObjectName(N.GetThreadDesktop(N.GetCurrentThreadId())).Equals("Test", StringComparison.OrdinalIgnoreCase),
                    "ABORT: private test desktop could not be verified; no clipboard access was authorized.");
                preflight = false;
                if (testCase)
                {
                    RunCase(args[0][casePrefix.Length..]);
                    File.WriteAllText(output, "PASS case; private noninteractive station and desktop verified");
                    return 0;
                }
                switch (args[0])
                {
                    case "--clipboard-publish":
                        string source = Path.Combine(WorkerDirectory, "source.png");
                        File.WriteAllBytes(source, ImageCodec.EncodePng(Fixture()));
                        ImageData decoded = ImageCodec.Decode(File.ReadAllBytes(source), ".png");
                        ClipboardEngine.Copy(decoded, ClipboardEngine.CaptureSequence());
                        File.Delete(source);
                        File.WriteAllText(output, "PASS published eagerly; source deleted");
                        break;
                    case "--clipboard-lock":
                        using (var owner = new TestWindow())
                        {
                            Require(N.OpenClipboard(owner.Handle), "lock clipboard");
                            try { File.WriteAllText(Path.Combine(WorkerDirectory, "ready.txt"), "ready"); WaitForFile("stop.txt", 10000); }
                            finally { N.CloseClipboard(); }
                        }
                        break;
                    case "--clipboard-delay": DelayedOwner(); break;
                    case "--clipboard-hang": DelayedOwner(hang: true); break;
                    default: throw new InvalidOperationException("Unknown clipboard worker mode.");
                }
            }
            return 0;
        }
        catch (Exception error)
        {
            bool unavailable = preflight || error is TestUnavailableException;
            File.WriteAllText(output, (unavailable ? "NOT RUN " : "FAIL ") + error.GetType().Name + (error is Win32Exception win32 ? " native=" + win32.NativeErrorCode : "") + ": " + error.Message);
            return unavailable ? 77 : 1;
        }
    }

    private static void RunCase(string scenario)
    {
        switch (scenario)
        {
            case "metadata-only":
                SetRaw(); Check.That(!ClipboardEngine.HasSupportedImage(), "Empty clipboard must hide.");
                SetText("plain text / https://example.invalid/image.png");
                Check.That(!ClipboardEngine.HasSupportedImage(), "Text and URL must hide.");
                SetRaw((N.RegisterClipboardFormat("HTML Format"), Encoding.UTF8.GetBytes("<img src='image.png'>")));
                Check.That(!ClipboardEngine.HasSupportedImage(), "HTML only must hide.");
                var drop = new byte[64]; BitConverter.GetBytes(20).CopyTo(drop, 0); BitConverter.GetBytes(1).CopyTo(drop, 16);
                Encoding.Unicode.GetBytes("C:\\image.png\0\0").CopyTo(drop, 20);
                SetRaw((15, drop)); Check.That(!ClipboardEngine.HasSupportedImage(), "CF_HDROP must not follow image paths.");
                SetRaw((N.RegisterClipboardFormat("ImageCopySave.PrivateTest"), new byte[] { 1 }));
                Check.That(!ClipboardEngine.HasSupportedImage(), "Unsupported private data must hide.");
                uint png = N.RegisterClipboardFormat("PNG");
                SetRaw((png, new byte[] { 1, 2, 3 }));
                Check.That(ClipboardEngine.HasSupportedImage(), "Metadata check must not decode a corrupt advertised image.");
                Check.Throws<InvalidDataException>(() => ClipboardEngine.Capture());
                SetRaw((png, ImageCodec.EncodePng(Fixture())), (13, Encoding.Unicode.GetBytes("text\0")));
                Check.That(ClipboardEngine.HasSupportedImage(), "Image plus text must show.");
                CheckImage(Fixture(), ClipboardEngine.Capture());
                break;
            case "alpha-roundtrip":
                ClipboardEngine.Copy(Fixture(), ClipboardEngine.CaptureSequence());
                Check.That(N.IsClipboardFormatAvailable(N.RegisterClipboardFormat("PNG")), "PNG missing.");
                Check.That(N.IsClipboardFormatAvailable(17), "DIBV5 missing.");
                Check.That(!N.IsClipboardFormatAvailable(15), "File references must not be published.");
                uint sequence = ClipboardEngine.CaptureSequence();
                CheckImage(Fixture(), ClipboardEngine.Capture());
                Check.That(ClipboardEngine.CaptureSequence() == sequence, "Capturing eager PNG changed clipboard contents.");
                CheckImage(Fixture(), ClipboardEngine.Capture());
                break;
            case "newer-copy":
                SetText("old"); uint old = ClipboardEngine.CaptureSequence();
                SetText("new"); uint current = ClipboardEngine.CaptureSequence();
                Check.Throws<ClipboardChangedException>(() => ClipboardEngine.Copy(Fixture(), old));
                Check.Throws<ClipboardChangedException>(() => ClipboardEngine.Capture(expectedSequence: old));
                Check.That(ClipboardEngine.CaptureSequence() == current && ReadText() == "new", "Newer clipboard copy was overwritten.");
                SetRaw(); Check.Throws<InvalidDataException>(() => ClipboardEngine.Capture());
                break;
            case "preparation-preserves":
                SetText("preserve"); uint before = ClipboardEngine.CaptureSequence();
                Check.Throws<InvalidDataException>(() => ClipboardEngine.Copy(new ImageData(2, 2, new byte[1]), before));
                using (var cancelled = new CancellationTokenSource())
                {
                    cancelled.Cancel();
                    Check.Throws<OperationCanceledException>(() => ClipboardEngine.Copy(Fixture(), before, cancelled.Token));
                    Check.Throws<OperationCanceledException>(() => ClipboardEngine.Capture(cancelled.Token));
                }
                Check.That(ClipboardEngine.CaptureSequence() == before && ReadText() == "preserve", "Preparation/cancellation changed clipboard.");
                break;
            case "snapshot-independent":
                ClipboardEngine.Copy(Fixture(), ClipboardEngine.CaptureSequence());
                ImageData snapshot = ClipboardEngine.Capture(); SetText("later");
                CheckImage(Fixture(), snapshot);
                Check.That(ReadText() == "later", "Snapshot processing touched the new clipboard.");
                break;
            case "native-formats":
                SetRaw((17, DibCodec.EncodeV5(Fixture())));
                CheckImage(Fixture(), ClipboardEngine.Capture(), "native DIBV5");
                var dib = new byte[44]; BitConverter.GetBytes(40).CopyTo(dib, 0); BitConverter.GetBytes(1).CopyTo(dib, 4);
                BitConverter.GetBytes(1).CopyTo(dib, 8); dib[12] = 1; dib[14] = 24; dib[40] = 5; dib[41] = 10; dib[42] = 15;
                SetRaw((8, dib)); CheckImage(new ImageData(1, 1, [5, 10, 15, 255]), ClipboardEngine.Capture(), "native DIB24");
                SetBitmap(); CheckImage(new ImageData(1, 1, [5, 10, 15, 255]), ClipboardEngine.Capture(), "native BITMAP");
                break;
            case "helper-exit":
                using (var publisher = Child("--clipboard-publish")) publisher.Wait(5000);
                Check.That(File.ReadAllText(Path.Combine(WorkerDirectory, "child.txt")).StartsWith("PASS", StringComparison.Ordinal), "Publisher did not finish.");
                Check.That(!File.Exists(Path.Combine(WorkerDirectory, "source.png")), "Test source was not removed.");
                CheckImage(Fixture(), ClipboardEngine.Capture()); // Publisher window and process are both gone.
                break;
            case "lock-and-cancel":
                SetText("preserve-under-lock"); uint original = ClipboardEngine.CaptureSequence();
                using (var locker = Child("--clipboard-lock"))
                {
                    WaitForFile("ready.txt", 5000);
                    try
                    {
                        Check.That(!ClipboardEngine.HasSupportedImage(), "Contended metadata check must fail closed.");
                        var timer = Stopwatch.StartNew();
                        var locked = Check.Throws<ClipboardOperationException>(() => ClipboardEngine.Capture());
                        Check.That(locked.Stage == "open" && !locked.ClipboardMayHaveChanged && timer.ElapsedMilliseconds < 1500, "Read retry was unbounded or misreported.");
                        var copyFailure = Check.Throws<ClipboardOperationException>(() => ClipboardEngine.Copy(Fixture(), original));
                        Check.That(!copyFailure.ClipboardMayHaveChanged, "Lock failure reported clipboard modification.");
                        using var cancellation = new CancellationTokenSource(50);
                        Check.Throws<OperationCanceledException>(() => ClipboardEngine.Capture(cancellation.Token));
                    }
                    finally { File.WriteAllText(Path.Combine(WorkerDirectory, "stop.txt"), "stop"); }
                    locker.Wait(5000);
                }
                Check.That(ClipboardEngine.CaptureSequence() == original && ReadText() == "preserve-under-lock", "Lock failure changed clipboard.");
                break;
            case "delayed-rendering":
                using (var delayed = Child("--clipboard-delay"))
                {
                    WaitForFile("ready.txt", 5000);
                    Check.That(ClipboardEngine.HasSupportedImage(), "Delayed PNG format not advertised.");
                    Check.That(!File.Exists(Path.Combine(WorkerDirectory, "rendered.txt")), "Metadata query rendered data.");
                    ImageData delayedSnapshot = ClipboardEngine.Capture(expectedSequence: ClipboardEngine.CaptureSequence());
                    CheckImage(Fixture(), delayedSnapshot, "delayed PNG snapshot");
                    Check.That(File.Exists(Path.Combine(WorkerDirectory, "rendered.txt")), "Delayed renderer not invoked.");
                    // The sequence documents clipboard changes, not one guaranteed extra increment
                    // for each WM_RENDERFORMAT callback. Use an explicit newer copy to exercise
                    // stale-copy rejection, independently of materialization timing.
                    uint materializedSequence = ClipboardEngine.CaptureSequence();
                    CheckImage(Fixture(), ClipboardEngine.Capture(), "materialized PNG snapshot");
                    Check.That(ClipboardEngine.CaptureSequence() == materializedSequence, "Reading materialized PNG altered the clipboard.");
                    SetText("newer-copy-after-delayed-rendering");
                    uint newerSequence = ClipboardEngine.CaptureSequence();
                    Check.That(newerSequence != materializedSequence, "Explicit newer copy did not change the clipboard sequence.");
                    Check.Throws<ClipboardChangedException>(() => ClipboardEngine.Copy(Fixture(), materializedSequence));
                    Check.That(ClipboardEngine.CaptureSequence() == newerSequence && ReadText() == "newer-copy-after-delayed-rendering",
                        "Stale-copy cancellation overwrote the newer clipboard contents.");
                    CheckImage(Fixture(), delayedSnapshot, "delayed snapshot after newer copy");
                    File.WriteAllText(Path.Combine(WorkerDirectory, "stop.txt"), "stop");
                    delayed.Wait(5000);
                }
                break;
            default:
                if (scenario.StartsWith("product-", StringComparison.Ordinal)) HelperProcessTests.Run(scenario);
                else throw new InvalidOperationException("Unknown scenario.");
                break;
        }
    }

    private static void CheckImage(ImageData expected, ImageData actual, string context = "clipboard image")
    {
        // Only generated fixtures reach this assertion, inside the verified private station.
        // Limit diagnostics even if a decoder unexpectedly returns a much larger buffer.
        string expectedPixels = Convert.ToHexString(expected.Bgra.AsSpan(0, Math.Min(expected.Bgra.Length, 64)));
        string actualPixels = Convert.ToHexString(actual.Bgra.AsSpan(0, Math.Min(actual.Bgra.Length, 64)));
        Check.That(actual.Width == expected.Width && actual.Height == expected.Height && actual.Bgra.SequenceEqual(expected.Bgra),
            $"{context}: expected {expected.Width}x{expected.Height} BGRA={expectedPixels}; actual {actual.Width}x{actual.Height} BGRA={actualPixels} (first 64 bytes).");
    }

    private static void SetText(string text) => SetRaw((13, Encoding.Unicode.GetBytes(text + "\0")));
    private static string ReadText()
    {
        Require(N.OpenClipboard(IntPtr.Zero), "read text");
        try
        {
            IntPtr h = N.GetClipboardData(13), p = N.GlobalLock(h);
            Require(p != IntPtr.Zero, "text memory");
            try { return Marshal.PtrToStringUni(p) ?? ""; }
            finally { N.GlobalUnlock(h); }
        }
        finally { N.CloseClipboard(); }
    }

    private static IntPtr Memory(byte[] data)
    {
        IntPtr h = N.GlobalAlloc(2, checked((nuint)data.Length)); Require(h != IntPtr.Zero, "allocate");
        IntPtr p = N.GlobalLock(h);
        if (p == IntPtr.Zero) { N.GlobalFree(h); throw new Win32Exception(); }
        try { Marshal.Copy(data, 0, p, data.Length); }
        finally { N.GlobalUnlock(h); }
        return h;
    }
    private static void SetRaw(params (uint Format, byte[] Data)[] formats)
    {
        VerifyPrivateStation(ActiveStation);
        using var owner = new TestWindow(); Require(N.OpenClipboard(owner.Handle), "open test clipboard");
        try
        {
            Require(N.EmptyClipboard(), "empty test clipboard");
            foreach (var format in formats)
            {
                IntPtr h = Memory(format.Data);
                if (N.SetClipboardData(format.Format, h) == IntPtr.Zero) { N.GlobalFree(h); throw new Win32Exception(); }
            }
        }
        finally { N.CloseClipboard(); }
    }
    private static void SetBitmap()
    {
        using var owner = new TestWindow();
        var info = new N.BitmapInfo { Size = 40, Width = 1, Height = -1, Planes = 1, BitCount = 32, SizeImage = 4 };
        IntPtr bitmap = N.CreateDIBSection(IntPtr.Zero, ref info, 0, out IntPtr pixels, IntPtr.Zero, 0);
        Require(bitmap != IntPtr.Zero, "create bitmap");
        try
        {
            Marshal.Copy(new byte[] { 5, 10, 15, 0 }, 0, pixels, 4);
            Require(N.OpenClipboard(owner.Handle), "open bitmap clipboard");
            try
            {
                Require(N.EmptyClipboard(), "empty bitmap clipboard");
                Require(N.SetClipboardData(2, bitmap) != IntPtr.Zero, "publish bitmap"); bitmap = IntPtr.Zero;
            }
            finally { N.CloseClipboard(); }
        }
        finally { if (bitmap != IntPtr.Zero) N.DeleteObject(bitmap); }
    }

    private static void DelayedOwner(bool hang = false)
    {
        uint png = N.RegisterClipboardFormat("PNG");
        N.WindowProc callback = (window, message, wParam, lParam) =>
        {
            if (message == 0x0305 && (uint)wParam == png)
            {
                if (hang)
                {
                    // Deliberately stuck foreign renderer: the public helper watchdog must
                    // terminate only its own blocked worker; our job cleans this fixture.
                    File.WriteAllText(Path.Combine(WorkerDirectory, "rendered.txt"), "WM_RENDERFORMAT entered");
                    Thread.Sleep(Timeout.Infinite);
                }
                IntPtr memory = Memory(ImageCodec.EncodePng(Fixture()));
                if (N.SetClipboardData(png, memory) == IntPtr.Zero) N.GlobalFree(memory);
                else File.WriteAllText(Path.Combine(WorkerDirectory, "rendered.txt"), "rendered");
                return IntPtr.Zero;
            }
            return N.DefWindowProc(window, message, wParam, lParam);
        };
        string name = "ImageCopySaveDelay" + Guid.NewGuid().ToString("N");
        var cls = new N.WindowClass { Procedure = callback, ClassName = name, Instance = N.GetModuleHandle(null) };
        Require(N.RegisterClass(ref cls) != 0, "register delayed test window");
        IntPtr window = N.CreateWindowEx(0, name, "", 0, 0, 0, 0, 0, new IntPtr(-3), IntPtr.Zero, cls.Instance, IntPtr.Zero);
        Require(window != IntPtr.Zero, "create delayed test window");
        try
        {
            Require(N.OpenClipboard(window), "open delayed clipboard");
            try { Require(N.EmptyClipboard(), "empty delayed clipboard"); N.SetClipboardData(png, IntPtr.Zero); }
            finally { N.CloseClipboard(); }
            File.WriteAllText(Path.Combine(WorkerDirectory, "ready.txt"), "ready");
            var deadline = Stopwatch.StartNew();
            while (!File.Exists(Path.Combine(WorkerDirectory, "stop.txt")) && deadline.ElapsedMilliseconds < (hang ? 30000 : 10000))
            {
                while (N.PeekMessage(out N.Message message, IntPtr.Zero, 0, 0, 1)) { N.TranslateMessage(ref message); N.DispatchMessage(ref message); }
                Thread.Sleep(10);
            }
        }
        finally { N.DestroyWindow(window); N.UnregisterClass(name, cls.Instance); GC.KeepAlive(callback); }
    }

    private static void WaitForFile(string name, int milliseconds)
    {
        var time = Stopwatch.StartNew();
        while (!File.Exists(Path.Combine(WorkerDirectory, name)))
        {
            if (time.ElapsedMilliseconds >= milliseconds) throw new TimeoutException("Test helper readiness/deadline exceeded.");
            Thread.Sleep(10);
        }
    }
    private static NativeChild Child(string mode) => new(mode, ActiveStation, WorkerDirectory);
    private static void Require(bool success, string operation) { if (!success) throw new Win32Exception(Marshal.GetLastWin32Error(), operation); }
    private static string ObjectName(IntPtr handle)
    {
        var name = new StringBuilder(256);
        Require(N.GetUserObjectInformation(handle, 2, name, name.Capacity * 2, out _), "identify window station");
        return name.ToString();
    }
    private static void VerifyPrivateStation(string expected)
    {
        string actual = ObjectName(N.GetProcessWindowStation());
        Require(N.GetUserObjectFlags(N.GetProcessWindowStation(), 1, out N.UserObjectFlags flags, Marshal.SizeOf<N.UserObjectFlags>(), out _), "identify station visibility");
        Check.That(!string.IsNullOrWhiteSpace(expected) && actual.Equals(expected, StringComparison.OrdinalIgnoreCase) && !actual.Equals("WinSta0", StringComparison.OrdinalIgnoreCase) && (flags.Flags & 1) == 0,
            "ABORT: private clipboard isolation could not be verified; no clipboard mutation was authorized.");
    }

    private sealed class PrivateStation : IDisposable
    {
        private readonly IntPtr previousStation = N.GetProcessWindowStation();
        private IntPtr station, desktop;
        public string Name { get; private set; } = "";
        public PrivateStation()
        {
            try
            {
                // Only administrators may supply a name. Never elevate here. Normal callers
                // use the OS logon-session name; both paths require a freshly created
                // object and must never reuse somebody else's clipboard.
                using var security = new StationSecurity();
                using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
                bool administrator = new System.Security.Principal.WindowsPrincipal(identity).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
                string? requestedName = administrator ? "ImageCopySaveTest_" + Guid.NewGuid().ToString("N") : null;
                station = N.CreateWindowStation(requestedName, 1 /* CWF_CREATE_ONLY */, 0x2E, ref security.Attributes);
                Require(station != IntPtr.Zero, administrator ? "create fresh named isolated station" : "create fresh OS-named isolated station (existing objects are never reused)");
                Name = ObjectName(station);
                Check.That(!Name.Equals(ObjectName(previousStation), StringComparison.OrdinalIgnoreCase), "Isolation must differ from the original station.");
                Require(N.SetProcessWindowStation(station), "attach isolated station");
                desktop = N.CreateDesktop("Test", IntPtr.Zero, IntPtr.Zero, 0, 0x0083, IntPtr.Zero); Require(desktop != IntPtr.Zero, "create isolated desktop");
                // The current STA thread may already own a COM window on its original
                // desktop. Only native children attach to Test, at process creation.
                VerifyPrivateStation(Name);
            }
            catch { Dispose(); throw; }
        }
        public void Dispose()
        {
            N.SetProcessWindowStation(previousStation);
            if (desktop != IntPtr.Zero) { N.CloseDesktop(desktop); desktop = IntPtr.Zero; }
            if (station != IntPtr.Zero) { N.CloseWindowStation(station); station = IntPtr.Zero; }
        }
    }
    private sealed class StationSecurity : IDisposable
    {
        private IntPtr descriptor;
        internal N.SecurityAttributes Attributes;
        public StationSecurity()
        {
            using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
            string sid = identity.User?.Value ?? throw new InvalidOperationException("Current user SID unavailable.");
            Require(N.ConvertStringSecurityDescriptorToSecurityDescriptor("D:P(A;;GA;;;" + sid + ")", 1, out descriptor, out _), "prepare private station security");
            Attributes = new N.SecurityAttributes { Length = Marshal.SizeOf<N.SecurityAttributes>(), Descriptor = descriptor };
        }
        public void Dispose() { if (descriptor != IntPtr.Zero) { N.LocalFree(descriptor); descriptor = IntPtr.Zero; } }
    }
    private sealed class TestWindow : IDisposable
    {
        public IntPtr Handle { get; } = N.CreateWindowEx(0, "STATIC", "", 0, 0, 0, 0, 0, new IntPtr(-3), IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        public TestWindow() => Require(Handle != IntPtr.Zero, "create test owner");
        public void Dispose() => N.DestroyWindow(Handle);
    }
    private sealed class NativeChild : IDisposable
    {
        private N.ProcessInformation process;
        private IntPtr job;
        private string? standardOutputPath, standardErrorPath;
        public NativeChild(string mode, string station, string directory)
            : this(TestExe, new[] { mode, station, directory }, station) { }

        public NativeChild(string executable, IReadOnlyList<string> arguments, string station, string? logDirectory = null)
        {
            VerifyPrivateStation(station);
            Check.That(Path.IsPathFullyQualified(executable), "An absolute test executable path is required.");
            IntPtr input = IntPtr.Zero, output = IntPtr.Zero, error = IntPtr.Zero;
            try
            {
                // Nested jobs preserve the host/CI job boundary. Never request breakaway.
                // Suspend before assignment so even a fast supervisor cannot leave an
                // unowned worker behind on a test failure or deadline.
                job = N.CreateJobObject(IntPtr.Zero, null);
                Require(job != IntPtr.Zero, "create owned child job");
                var limits = new N.JobExtendedLimitInformation
                { Basic = new N.JobBasicLimitInformation { LimitFlags = 0x00002000 /* KILL_ON_JOB_CLOSE */ } };
                Require(N.SetInformationJobObject(job, 9, ref limits, Marshal.SizeOf<N.JobExtendedLimitInformation>()), "configure owned child job");
                var startup = new N.StartupInfo { Size = Marshal.SizeOf<N.StartupInfo>(), Desktop = station + "\\Test", Flags = 1, ShowWindow = 0 };
                if (logDirectory != null)
                {
                    // Only the three temporary std handles are made inheritable. The
                    // existing owned job is noninheritable and must stay that way.
                    string identifier = Guid.NewGuid().ToString("N");
                    standardOutputPath = Path.Combine(logDirectory, identifier + ".stdout.txt");
                    standardErrorPath = Path.Combine(logDirectory, identifier + ".stderr.txt");
                    input = OpenInheritedFile("NUL", 0x80000000, 3 /* OPEN_EXISTING */);
                    output = OpenInheritedFile(standardOutputPath, 0x40000000, 1 /* CREATE_NEW */);
                    error = OpenInheritedFile(standardErrorPath, 0x40000000, 1 /* CREATE_NEW */);
                    startup.Flags |= 0x00000100 /* STARTF_USESTDHANDLES */;
                    startup.Input = input; startup.Output = output; startup.Error = error;
                }
                var command = new StringBuilder(string.Join(" ", new[] { executable }.Concat(arguments).Select(Quote)));
                Require(N.CreateProcess(executable, command, IntPtr.Zero, IntPtr.Zero, logDirectory != null, 0x08000004 /* NO_WINDOW | SUSPENDED */,
                    IntPtr.Zero, null, ref startup, out process), "launch isolated child");
                Require(N.AssignProcessToJobObject(job, process.Process), "contain isolated child process tree");
                Require(N.ResumeThread(process.Thread) != uint.MaxValue, "resume isolated child");
            }
            catch { Dispose(); throw; }
            finally
            {
                // Parent copies are never retained across launches (including parallel saves).
                if (input != IntPtr.Zero) N.CloseHandle(input);
                if (output != IntPtr.Zero) N.CloseHandle(output);
                if (error != IntPtr.Zero) N.CloseHandle(error);
            }
        }
        private static IntPtr OpenInheritedFile(string path, uint access, uint creation)
        {
            var attributes = new N.SecurityAttributes { Length = Marshal.SizeOf<N.SecurityAttributes>(), InheritHandle = 1 };
            IntPtr handle = N.CreateFile(path, access, 7 /* allow read/write/delete diagnostics */, ref attributes,
                creation, 0x80 /* NORMAL */, IntPtr.Zero);
            Require(handle != new IntPtr(-1), "open isolated diagnostic handle");
            return handle;
        }
        private static string Quote(string value)
        {
            var output = new StringBuilder("\""); int slashes = 0;
            foreach (char c in value)
            {
                if (c == '\\') { slashes++; continue; }
                if (c == '"') { output.Append('\\', slashes * 2 + 1).Append(c); slashes = 0; continue; }
                output.Append('\\', slashes).Append(c); slashes = 0;
            }
            return output.Append('\\', slashes * 2).Append('"').ToString();
        }
        public uint WaitForExit(uint milliseconds)
        {
            var timer = Stopwatch.StartNew();
            while (true)
            {
                CheckCaptureBudget();
                uint remaining = checked((uint)Math.Max(0, (long)milliseconds - timer.ElapsedMilliseconds));
                uint wait = N.WaitForSingleObject(process.Process, Math.Min(remaining, 50u));
                if (wait == 0) break;
                Require(wait == 258, "wait for isolated child");
                if (timer.ElapsedMilliseconds >= milliseconds)
                    throw new TimeoutException("Native helper exceeded deadline. " + DiagnosticSummary());
            }
            CheckCaptureBudget();
            Require(N.GetExitCodeProcess(process.Process, out uint code), "get child status");
            return code;
        }
        public void Wait(uint milliseconds)
        {
            uint code = WaitForExit(milliseconds);
            Check.That(code == 0, "Isolated native helper failed with code " + code);
        }
        public bool IsRunning
        {
            get
            {
                uint wait = N.WaitForSingleObject(process.Process, 0);
                Require(wait is 0 or 258, "inspect isolated child status");
                return wait == 258;
            }
        }

        private void CheckCaptureBudget()
        {
            foreach (string? path in new[] { standardOutputPath, standardErrorPath })
                if (path != null && new FileInfo(path).Length > 65536)
                    throw new IOException("Product helper diagnostics exceeded the 64 KiB per-stream test budget.");
        }

        public void AssertDiagnosticsExclude(string[] forbiddenText, params byte[][] forbiddenBytes)
        {
            CheckCaptureBudget();
            foreach (string? path in new[] { standardOutputPath, standardErrorPath })
            {
                Check.That(path != null, "Raw product diagnostic capture is required.");
                using var stream = new FileStream(path!, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                byte[] buffer = new byte[65537]; int count = 0;
                while (count < buffer.Length)
                {
                    int read = stream.Read(buffer, count, buffer.Length - count);
                    if (read == 0) break;
                    count += read;
                }
                Check.That(count <= 65536, "Raw product diagnostic capture exceeded the test budget.");
                byte[] bytes = buffer[..count];
                string text = Encoding.UTF8.GetString(bytes);
                for (int i = 0; i < forbiddenText.Length; i++)
                    Check.That(string.IsNullOrEmpty(forbiddenText[i]) || !text.Contains(forbiddenText[i], StringComparison.OrdinalIgnoreCase),
                        $"Product raw diagnostics disclosed forbidden text fixture {i + 1}; content withheld.");
                for (int i = 0; i < forbiddenBytes.Length; i++)
                    Check.That(forbiddenBytes[i].Length == 0 || bytes.AsSpan().IndexOf(forbiddenBytes[i]) < 0,
                        $"Product raw diagnostics disclosed forbidden byte fixture {i + 1}; content withheld.");
            }
        }

        public string DiagnosticSummary()
        {
            if (standardErrorPath == null) return "No product stderr capture.";
            using var stream = new FileStream(standardErrorPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            byte[] bytes = new byte[Math.Min(stream.Length, 8192)];
            int length = stream.Read(bytes, 0, bytes.Length);
            string text = Encoding.UTF8.GetString(bytes, 0, length);
            var summaries = new List<string>();
            foreach (string line in text.Split('\n').Take(16))
            {
                try
                {
                    using JsonDocument json = JsonDocument.Parse(line.Trim());
                    if (json.RootElement.ValueKind != JsonValueKind.Object) continue;
                    var fields = new Dictionary<string, object?>();
                    foreach (string name in new[] { "error", "code", "nativeCode", "stage", "clipboardMayHaveChanged" })
                    {
                        if (!json.RootElement.TryGetProperty(name, out JsonElement value)) continue;
                        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out long number)) fields[name] = number;
                        else if (value.ValueKind is JsonValueKind.True or JsonValueKind.False) fields[name] = value.GetBoolean();
                        else if (value.ValueKind == JsonValueKind.Null) fields[name] = null;
                        else if (value.ValueKind == JsonValueKind.String)
                        {
                            string item = value.GetString() ?? "";
                            fields[name] = item.Length <= 128 && item.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-')
                                ? item : "(redacted)";
                        }
                    }
                    if (fields.Count > 0) summaries.Add(JsonSerializer.Serialize(fields));
                }
                catch (JsonException) { /* Product progress text and free-form messages are deliberately omitted. */ }
            }
            string note = stream.Length > bytes.Length ? "; stderr truncated to first 8 KiB" : "";
            return summaries.Count == 0 ? "No structured product stderr diagnostics" + note
                : string.Join(" | ", summaries.Take(8)) + note;
        }

        public void AssertNoSurvivingChildren()
        {
            var time = Stopwatch.StartNew();
            do
            {
                Require(N.QueryInformationJobObject(job, 1, out N.JobBasicAccountingInformation info,
                    Marshal.SizeOf<N.JobBasicAccountingInformation>(), IntPtr.Zero), "inspect owned child job");
                if (info.ActiveProcesses == 0) return;
                Thread.Sleep(10);
            } while (time.ElapsedMilliseconds < 1500);
            throw new InvalidOperationException("Product helper exited while a worker remained alive.");
        }
        public void Dispose()
        {
            // Terminate the whole owned subtree, including an unresponsive renderer or
            // supervisor's worker. The noninheritable job handle is the final backstop.
            if (job != IntPtr.Zero) N.TerminateJobObject(job, 125);
            if (process.Process != IntPtr.Zero)
            {
                if (N.WaitForSingleObject(process.Process, 0) != 0)
                {
                    N.TerminateProcess(process.Process, 125); // Also covers failed job assignment.
                    N.WaitForSingleObject(process.Process, 2000);
                }
                N.CloseHandle(process.Process); process.Process = IntPtr.Zero;
            }
            if (process.Thread != IntPtr.Zero) { N.CloseHandle(process.Thread); process.Thread = IntPtr.Zero; }
            if (job != IntPtr.Zero) { N.CloseHandle(job); job = IntPtr.Zero; }
        }
    }

    private static class N
    {
        [StructLayout(LayoutKind.Sequential)] internal struct JobBasicLimitInformation
        { public long ProcessTime, JobTime; public uint LimitFlags; public nuint MinimumWorkingSet, MaximumWorkingSet; public uint ActiveProcessLimit; public nuint Affinity; public uint PriorityClass, SchedulingClass; }
        [StructLayout(LayoutKind.Sequential)] internal struct IoCounters
        { public ulong ReadOperations, WriteOperations, OtherOperations, ReadBytes, WriteBytes, OtherBytes; }
        [StructLayout(LayoutKind.Sequential)] internal struct JobExtendedLimitInformation
        { public JobBasicLimitInformation Basic; public IoCounters Io; public nuint ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory; }
        [StructLayout(LayoutKind.Sequential)] internal struct JobBasicAccountingInformation
        { public long UserTime, KernelTime, PeriodUserTime, PeriodKernelTime; public uint PageFaults, TotalProcesses, ActiveProcesses, TerminatedProcesses; }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern IntPtr CreateJobObject(IntPtr security, string? name);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool SetInformationJobObject(IntPtr job, int informationClass, ref JobExtendedLimitInformation information, int length);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool QueryInformationJobObject(IntPtr job, int informationClass, out JobBasicAccountingInformation information, int length, IntPtr returned);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool TerminateJobObject(IntPtr job, uint code);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern uint ResumeThread(IntPtr thread);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern IntPtr CreateFile(string path, uint access, uint share, ref SecurityAttributes security, uint creation, uint flags, IntPtr template);

        [StructLayout(LayoutKind.Sequential)] internal struct UserObjectFlags { public int Inherit, Reserved; public uint Flags; }
        [StructLayout(LayoutKind.Sequential)] internal struct SecurityAttributes { public int Length; public IntPtr Descriptor; public int InheritHandle; }
        [StructLayout(LayoutKind.Sequential)] internal struct BitmapInfo { public uint Size; public int Width, Height; public ushort Planes, BitCount; public uint Compression, SizeImage; public int X, Y; public uint Used, Important; }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] internal struct StartupInfo { public int Size; public string? Reserved, Desktop, Title; public int X, Y, Width, Height, XChars, YChars, Fill; public uint Flags; public short ShowWindow, Reserved2; public IntPtr ReservedPointer, Input, Output, Error; }
        [StructLayout(LayoutKind.Sequential)] internal struct ProcessInformation { public IntPtr Process, Thread; public uint ProcessId, ThreadId; }
        [UnmanagedFunctionPointer(CallingConvention.Winapi)] internal delegate IntPtr WindowProc(IntPtr window, uint message, nuint wParam, nint lParam);
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] internal struct WindowClass { public uint Style; public WindowProc Procedure; public int ClassExtra, WindowExtra; public IntPtr Instance, Icon, Cursor, Background; public string? MenuName; public string ClassName; }
        [StructLayout(LayoutKind.Sequential)] internal struct Message { public IntPtr Window; public uint Msg; public nuint WParam; public nint LParam; public uint Time; public int X, Y; public uint Private; }
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool OpenClipboard(IntPtr window);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseClipboard();
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool EmptyClipboard();
        [DllImport("user32.dll")] internal static extern IntPtr GetClipboardData(uint format);
        [DllImport("user32.dll", SetLastError = true)] internal static extern IntPtr SetClipboardData(uint format, IntPtr data);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool IsClipboardFormatAvailable(uint format);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern uint RegisterClipboardFormat(string name);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern IntPtr GlobalAlloc(uint flags, nuint size);
        [DllImport("kernel32.dll", SetLastError = true)] internal static extern IntPtr GlobalLock(IntPtr handle);
        [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GlobalUnlock(IntPtr handle);
        [DllImport("kernel32.dll")] internal static extern IntPtr GlobalFree(IntPtr handle);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern IntPtr CreateWindowEx(uint ex, string cls, string name, uint style, int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool DestroyWindow(IntPtr window);
        [DllImport("gdi32.dll", SetLastError = true)] internal static extern IntPtr CreateDIBSection(IntPtr dc, ref BitmapInfo info, uint usage, out IntPtr bits, IntPtr section, uint offset);
        [DllImport("gdi32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool DeleteObject(IntPtr value);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern IntPtr CreateWindowStation(string? name, uint flags, uint access, ref SecurityAttributes security);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool ConvertStringSecurityDescriptorToSecurityDescriptor(string sddl, uint revision, out IntPtr descriptor, out uint length);
        [DllImport("kernel32.dll")] internal static extern IntPtr LocalFree(IntPtr value);
        [DllImport("user32.dll", EntryPoint = "GetUserObjectInformationW", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetUserObjectFlags(IntPtr handle, int index, out UserObjectFlags flags, int length, out int needed);
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool SetProcessWindowStation(IntPtr station);
        [DllImport("user32.dll")] internal static extern IntPtr GetProcessWindowStation();
        [DllImport("user32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseWindowStation(IntPtr station);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr mode, uint flags, uint access, IntPtr security);
        [DllImport("user32.dll")] internal static extern IntPtr GetThreadDesktop(uint thread);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseDesktop(IntPtr desktop);
        [DllImport("kernel32.dll")] internal static extern uint GetCurrentThreadId();
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder buffer, int length, out int needed);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CreateProcess(string application, StringBuilder command, IntPtr processSecurity, IntPtr threadSecurity, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint flags, IntPtr environment, string? directory, ref StartupInfo startup, out ProcessInformation process);
        [DllImport("kernel32.dll")] internal static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetExitCodeProcess(IntPtr process, out uint code);
        [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool TerminateProcess(IntPtr process, uint code);
        [DllImport("kernel32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseHandle(IntPtr handle);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern ushort RegisterClass(ref WindowClass cls);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool UnregisterClass(string cls, IntPtr instance);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] internal static extern IntPtr GetModuleHandle(string? name);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern IntPtr DefWindowProc(IntPtr window, uint message, nuint wParam, nint lParam);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool PeekMessage(out Message message, IntPtr window, uint min, uint max, uint remove);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool TranslateMessage(ref Message message);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern IntPtr DispatchMessage(ref Message message);
    }
}
