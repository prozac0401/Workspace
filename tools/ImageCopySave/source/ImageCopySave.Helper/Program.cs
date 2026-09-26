using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using ImageCopySave.Engine;
namespace ImageCopySave.Helper;
internal static class Program
{
    // Shell and CLI share the same bounded supervisor and disposable image worker.
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            return Run(args);
        }
        catch (Exception ex) when (ex is not StackOverflowException)
        { WriteFailure(ex, "launch"); return 1; }
    }

    private static int Run(string[] args)
    {
        if (args is ["--render-feedback", var renderDirectory])
        { ShellFeedback.RenderSamples(renderDirectory); return 0; }
        if (args is ["--probe-formats"])
        { Console.WriteLine(JsonSerializer.Serialize(new { supportedImageFormat = ClipboardEngine.HasSupportedImage(), note = "Format probe only; no Explorer or G0 proof." })); return 0; }
        if (args.Length == 7 && args[0] is "--worker" or "--worker-shell" && uint.TryParse(args[4], out uint expectedSequence))
            return Work(args[1], args[2], args[3], expectedSequence, new DesktopContext(args[5], args[6]), args[0] == "--worker-shell");
        if (args.Length > 0 && args[0] == "--shell")
        {
            if (!ShellRequest.TryParse(args, out ShellRequest? request)) return 2;
            DesktopContext shellContext = DesktopContext.Current();
            return ShellFeedback.Run(request!, (cancellation, progress) =>
                RunSupervised(request!.Operation, request.Target, request.Sequence, shellContext, true, cancellation, progress));
        }
        if (args.Length != 2 || args[0] is not ("copy" or "save"))
        { Console.Error.WriteLine("ENGINE EVALUATION ONLY. Usage: ImageCopySave.Helper copy <absolute image path> | save <absolute local folder> | --probe-formats"); return 2; }
        DesktopContext context = DesktopContext.Current();
        uint initialSequence = args[0] == "copy" ? ClipboardEngine.CaptureSequence() : 0;
        return RunSupervised(args[0], args[1], initialSequence, context, false, CancellationToken.None, null).ExitCode;
    }

    private static WorkerResult RunSupervised(string operation, string target, uint initialSequence,
        DesktopContext context, bool shell, CancellationToken cancellation, Action? progress)
    {
        string executable = Environment.ProcessPath ?? throw new InvalidOperationException("No executable path.");
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = new UTF8Encoding(false), StandardErrorEncoding = new UTF8Encoding(false) };
        if (Path.GetFileNameWithoutExtension(executable).Equals("dotnet", StringComparison.OrdinalIgnoreCase))
            start.ArgumentList.Add(typeof(Program).Assembly.Location);
        string cancelName = "Local\\ImageCopySave-Cancel-" + Guid.NewGuid().ToString("N");
        using var cancelEvent = new EventWaitHandle(false, EventResetMode.ManualReset, cancelName);
        start.ArgumentList.Add(shell ? "--worker-shell" : "--worker"); start.ArgumentList.Add(operation); start.ArgumentList.Add(target); start.ArgumentList.Add(cancelName); start.ArgumentList.Add(initialSequence.ToString(System.Globalization.CultureInfo.InvariantCulture));
        start.ArgumentList.Add(context.Station); start.ArgumentList.Add(context.Desktop);
        return Supervise(StartWorker(start, context), cancelEvent, operation, shell, cancellation, progress);
    }

    private static WorkerResult Supervise(Process child, EventWaitHandle cancelEvent, string operation,
        bool shell, CancellationToken requestedCancellation, Action? showProgress)
    {
        CancellationTokenSource? canceled = null;
        ConsoleCancelEventHandler? cancelHandler = null;
        bool exitConfirmed = false;
        bool? operationCompleted = null;
        try
        {
            var output = child.StandardOutput.ReadToEndAsync();
            var error = child.StandardError.ReadToEndAsync();
            canceled = CancellationTokenSource.CreateLinkedTokenSource(requestedCancellation);
            CancellationTokenSource cancellation = canceled;
            cancelHandler = (_, e) =>
            {
                e.Cancel = true;
                try { cancellation.Cancel(); }
                catch (ObjectDisposedException) { /* A console callback raced with worker exit. */ }
            };
            if (!shell) Console.CancelKeyPress += cancelHandler;
            var watch = Stopwatch.StartNew(); bool progress = false;
            while (!child.WaitForExit(50))
            {
                if (!progress && watch.ElapsedMilliseconds > 1000)
                {
                    if (shell) showProgress?.Invoke();
                    else Console.Error.WriteLine("그림 처리 중입니다. Ctrl+C로 중단할 수 있습니다. (개발용 엔진 시험)");
                    progress = true;
                }
                if (watch.ElapsedMilliseconds >= 15000 || canceled.IsCancellationRequested)
                {
                    // Only our own worker is terminated. Never kill Explorer or another app.
                    cancelEvent.Set();
                    if (child.WaitForExit(1000)) break;
                    child.Kill(entireProcessTree: true);
                    exitConfirmed = child.WaitForExit(1000);
                    if (!exitConfirmed) throw new TimeoutException("The terminated worker did not exit within its deadline.");
                    const string uncertain = "작업을 강제 중단했습니다. 파일 저장 완료 여부와 클립보드 보존 여부는 불확실합니다. 임시 파일이 남을 수 있습니다.";
                    TryWriteError(uncertain);
                    return new WorkerResult(3, "", uncertain);
                }
            }
            exitConfirmed = true;
            int result = child.ExitCode;
            if (result == 0) operationCompleted = true;
            // Our worker does not create descendants. Once it exits, both short result streams must
            // finish too; do not turn an unexpected inherited pipe into an unlimited supervisor wait.
            if (!Task.WhenAll(output, error).Wait(1000))
                throw new TimeoutException("The worker result streams did not close after exit.");
            string standardOutput = output.GetAwaiter().GetResult();
            string standardError = error.GetAwaiter().GetResult();
            return DeliverResult(new WorkerResult(result, standardOutput, standardError), shell, Console.Out, Console.Error);
        }
        catch (Exception ex) when (ex is not StackOverflowException)
        {
            // Once StartWorker succeeded, a transport/control failure cannot prove that a commit
            // did not happen. Attempt bounded cleanup before reporting that uncertainty.
            if (!exitConfirmed) exitConfirmed = StopOwnWorker(child, cancelEvent);
            WriteFailure(ex, "supervision", clipboardMayHaveChanged: true,
                fileMayHaveBeenCreated: operation == "save", operationCompleted: operationCompleted,
                workerMayStillBeRunning: !exitConfirmed);
            return new WorkerResult(1, "", operationCompleted == true
                ? "그림 작업은 완료했지만 결과를 전달하지 못했습니다. 완료된 작업은 취소되지 않았습니다."
                : "작업 상태를 확인하지 못했습니다. 파일 저장 완료 여부와 클립보드 보존 여부는 불확실합니다.");
        }
        finally
        {
            if (!shell && cancelHandler != null)
            {
                try { Console.CancelKeyPress -= cancelHandler; }
                catch (Exception ex) when (ex is not StackOverflowException) { }
            }
            try { canceled?.Dispose(); }
            catch (Exception ex) when (ex is not StackOverflowException) { }
            try { child.Dispose(); }
            catch (Exception ex) when (ex is not StackOverflowException) { }
        }
    }

    internal static WorkerResult DeliverResult(WorkerResult result, bool shell, TextWriter output, TextWriter error)
    {
        try { output.Write(result.Output); output.Flush(); }
        catch (Exception exception) when (shell && exception is not StackOverflowException)
        {
            // Explorer's selection channel is optional. The GUI still has the known
            // committed result/path and must not reclassify it as an image failure.
        }
        try { error.Write(result.Error); }
        catch (Exception exception) when (shell && exception is not StackOverflowException) { }
        return result;
    }

    private static bool StopOwnWorker(Process child, EventWaitHandle cancelEvent)
    {
        try { if (child.HasExited) return true; }
        catch (Exception ex) when (ex is not StackOverflowException) { }
        try { cancelEvent.Set(); }
        catch (Exception ex) when (ex is not StackOverflowException) { }
        try { if (child.WaitForExit(1000)) return true; }
        catch (Exception ex) when (ex is not StackOverflowException) { }
        try { child.Kill(entireProcessTree: true); }
        catch (Exception ex) when (ex is not StackOverflowException)
        {
            // This worker never spawns children. If tree enumeration failed, still try its own
            // retained process handle; failure remains explicit in workerMayStillBeRunning.
            try { child.Kill(); }
            catch (Exception fallback) when (fallback is not StackOverflowException) { }
        }
        try { return child.WaitForExit(1000); }
        catch (Exception ex) when (ex is not StackOverflowException) { return false; }
    }

    private static Process StartWorker(ProcessStartInfo start, DesktopContext context)
    {
        // Process.Start on Windows uses CreateProcess with inherited handles, but does not populate
        // STARTUPINFO.lpDesktop. System-opened station/desktop handles are not inheritable by default.
        // Open only our existing context as inheritable for this one launch; never change context or
        // enable an interactive fallback. The worker checks both identities before clipboard access.
        using var inherited = new InheritedDesktopContext(context);
        return Process.Start(start) ?? throw new IOException("Cannot start image worker.");
    }

    private static int Work(string operation, string argument, string cancelName, uint expectedSequence,
        DesktopContext expectedContext, bool invokedByShell)
    {
        if (!cancelName.StartsWith("Local\\ImageCopySave-Cancel-", StringComparison.Ordinal)) return 2;
        string stage = "context";
        string? result = null;
        bool committed = false;
        try
        {
            // Internal assertion, not a destination override: a mismatch aborts without switching
            // station/desktop, opening source files, or reading/writing any clipboard content.
            expectedContext.RequireCurrent();
            stage = operation;
            using var cancel = EventWaitHandle.OpenExisting(cancelName);
            using var cts = new CancellationTokenSource();
            RegisteredWaitHandle registration = ThreadPool.RegisterWaitForSingleObject(cancel, (_, _) =>
            {
                try { cts.Cancel(); }
                catch (ObjectDisposedException) { /* A callback already queued as the worker finished. */ }
            }, null, Timeout.Infinite, true);
            if (cancel.WaitOne(0)) cts.Cancel(); // An already signaled request must win before preparation.
            try
            {
                if (operation == "copy")
                {
                    ImageData image = LocalPaths.ReadImage(argument, cts.Token);
                    ClipboardEngine.Copy(image, expectedSequence, cts.Token);
                    committed = true;
                    result = "그림으로 복사했습니다";
                }
                else if (operation == "save")
                {
                    string folder = LocalPaths.Validate(argument, true);
                    ImageData snapshot = ClipboardEngine.Capture(cts.Token, invokedByShell ? expectedSequence : null);
                    result = AtomicPngWriter.Save(snapshot, folder, cts.Token);
                    committed = true;
                }
                else return 2;
            }
            finally { registration.Unregister(null); }
        }
        catch (OperationCanceledException) when (!committed)
        { TryWriteError("커밋 전에 작업을 취소했습니다."); return 3; }
        catch (Exception ex) when (ex is not StackOverflowException)
        {
            WriteFailure(ex, stage, clipboardMayHaveChanged: committed && operation == "copy",
                fileMayHaveBeenCreated: committed && operation == "save", operationCompleted: committed);
            return 1;
        }

        // Publication and delivery of the command result are separate outcomes. A broken stdout
        // must not be reported as an uncommitted copy/save, nor can the completed action be undone.
        try { Console.WriteLine(result); return 0; }
        catch (Exception ex) when (ex is not StackOverflowException)
        {
            WriteFailure(ex, "output", clipboardMayHaveChanged: operation == "copy",
                fileMayHaveBeenCreated: operation == "save", operationCompleted: true);
            return 1;
        }
    }

    private static void WriteFailure(Exception ex, string stage, bool clipboardMayHaveChanged = false,
        bool fileMayHaveBeenCreated = false, bool? operationCompleted = false, bool workerMayStillBeRunning = false)
    {
        // Avoid exposing clipboard text/image bytes, context names, or source paths in diagnostics.
        // This is best effort: a broken error pipe must not reclassify a post-commit failure as launch.
        try
        {
            TryWriteError(JsonSerializer.Serialize(new { error = ex.GetType().Name, code = ex.HResult, nativeCode = NativeErrorCode(ex),
                stage = ex is ClipboardOperationException clipboardError ? clipboardError.Stage : stage,
                clipboardMayHaveChanged = clipboardMayHaveChanged ||
                    (ex is ClipboardOperationException commitError && commitError.ClipboardMayHaveChanged),
                fileMayHaveBeenCreated, operationCompleted, workerMayStillBeRunning,
                message = operationCompleted == true
                    ? "그림 작업은 완료했지만 결과를 전달하지 못했습니다. 완료된 작업은 취소되지 않았습니다."
                    : stage == "supervision"
                        ? "작업 상태를 확인하지 못했습니다. 파일 저장 완료 여부와 클립보드 보존 여부는 불확실합니다."
                        : "그림 작업을 완료하지 못했습니다. 원본 파일은 변경하지 않았습니다." }));
        }
        catch (Exception failure) when (failure is not StackOverflowException) { }
    }

    private static int? NativeErrorCode(Exception error)
    {
        // Native clipboard/path APIs often wrap Win32Exception. Report the numeric code only;
        // never serialize exception messages or paths. Bound traversal of unusual exception chains.
        Exception? current = error;
        for (int depth = 0; current != null && depth < 8; depth++, current = current.InnerException)
            if (current is Win32Exception native) return native.NativeErrorCode;
        return null;
    }

    private static void TryWriteError(string message)
    {
        try { Console.Error.WriteLine(message); }
        catch (Exception ex) when (ex is not StackOverflowException) { }
    }

    private sealed record DesktopContext(string Station, string Desktop)
    {
        public static DesktopContext Current() => new(
            Name(Native.GetProcessWindowStation()), Name(Native.GetThreadDesktop(Native.GetCurrentThreadId())));

        public void RequireCurrent()
        {
            DesktopContext actual = Current();
            if (!string.Equals(Station, actual.Station, StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(Desktop, actual.Desktop, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("The worker desktop context does not match its supervisor.");
        }

        private static string Name(IntPtr handle)
        {
            if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
            Native.GetUserObjectInformation(handle, 2, null, 0, out int bytes);
            if (bytes <= 2 || bytes > 32768 || (bytes & 1) != 0)
                throw new InvalidOperationException("The desktop context could not be identified.");
            var value = new StringBuilder(bytes / 2);
            if (!Native.GetUserObjectInformation(handle, 2, value, bytes, out _))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            string name = value.ToString();
            if (string.IsNullOrEmpty(name)) throw new InvalidOperationException("The desktop context name is empty.");
            return name;
        }
    }

    private sealed class InheritedDesktopContext : IDisposable
    {
        private IntPtr station, desktop;
        public InheritedDesktopContext(DesktopContext context)
        {
            try
            {
                context.RequireCurrent();
                // WINSTA_READATTRIBUTES | ACCESSCLIPBOARD | ACCESSGLOBALATOMS; no desktop creation.
                station = Native.OpenWindowStation(context.Station, true, 0x0026);
                if (station == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                // DESKTOP_READOBJECTS | CREATEWINDOW | WRITEOBJECTS, sufficient for the native owner.
                desktop = Native.OpenDesktop(context.Desktop, 0, true, 0x0083);
                if (desktop == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
                context.RequireCurrent();
            }
            catch { Dispose(); throw; }
        }
        public void Dispose()
        {
            if (desktop != IntPtr.Zero) { Native.CloseDesktop(desktop); desktop = IntPtr.Zero; }
            if (station != IntPtr.Zero) { Native.CloseWindowStation(station); station = IntPtr.Zero; }
        }
    }

    private static class Native
    {
        [DllImport("user32.dll", SetLastError = true)] internal static extern IntPtr GetProcessWindowStation();
        [DllImport("user32.dll", SetLastError = true)] internal static extern IntPtr GetThreadDesktop(uint thread);
        [DllImport("kernel32.dll")] internal static extern uint GetCurrentThreadId();
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder? value, int bytes, out int needed);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern IntPtr OpenWindowStation(string name, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint access);
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        internal static extern IntPtr OpenDesktop(string name, uint flags, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint access);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseWindowStation(IntPtr station);
        [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] internal static extern bool CloseDesktop(IntPtr desktop);
    }
}
