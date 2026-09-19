using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using FolderState.Core;

internal static class UiFlowChecks
{
    private static int passed;

    public static FolderState.App.MainWindow CreateVerifiedWindow()
    {
        // Keep generated fixtures below the repository output directory. Do not delete them:
        // a failed test leaves its exact state available for diagnosis.
        string repository = FindRepository();
        string artifacts = Path.GetFullPath(Path.Combine(repository, "artifacts"));
        string suite = Path.GetFullPath(Path.Combine(artifacts, "ui-smoke", Guid.NewGuid().ToString("N")));
        Assert(suite.StartsWith(artifacts + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase), "Fixture path escaped artifacts.");
        Directory.CreateDirectory(suite);
        var engine = new FolderStateEngine(Path.Combine(AppContext.BaseDirectory, "icons"), Path.Combine(suite, "logs"));
        var window = new FolderState.App.MainWindow(engine);
        var previousContext = SynchronizationContext.Current;
        SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext());
        try
        {
            Wait(CheckFlows(window, suite, engine));
            Console.WriteLine($"PASS {passed} WPF interaction checks. Fixtures: {suite}");
            return window;
        }
        finally { SynchronizationContext.SetSynchronizationContext(previousContext); }
    }

    private static async Task CheckFlows(FolderState.App.MainWindow window, string suite, FolderStateEngine engine)
    {
        string a = Folder(suite, "A_진행 중 [이동형]"), b = Folder(suite, "B_상태 없음");
        string broken = Folder(suite, "C_읽기 실패"), recovery = Folder(suite, "D_중단된 작업");
        string emptyRecovery = Folder(suite, "E_첫 상태 저장 중단"), readBackFailure = Folder(suite, "F_저장 후 읽기 실패");
        string business = Path.Combine(b, "업무 원본.txt");
        File.WriteAllText(business, "KEEP BUSINESS CONTENT");
        Ok(engine.Set(a, WorkStatus.Doing, IconMode.Portable));
        File.WriteAllText(Path.Combine(broken, FolderStateEngine.StateFile), "invalid fixture metadata");

        Assert(!Control<FrameworkElement>(window, "StateButtons").IsEnabled, "Initial state actions must be disabled.");
        Assert(!Control<Button>(window, "RepairButton").IsEnabled && !Control<Button>(window, "ResetButton").IsEnabled, "Initial recovery/reset must be disabled.");
        Pass("no confirmed target disables mutations");

        await Select(window, a);
        Assert(Control<RadioButton>(window, "PortableMode").IsChecked == true, "Stored portable mode was not shown.");
        Assert(Control<TextBlock>(window, "SelectedFolderText").Text.Contains(Path.GetFileName(a), StringComparison.Ordinal), "Confirmed target name was not shown.");
        Assert(Control<FrameworkElement>(window, "StateButtons").IsEnabled, "Confirmed valid target should allow status changes.");
        Assert(Control<Button>(window, "RepairButton").IsEnabled && Control<Button>(window, "ResetButton").IsEnabled, "Stored state should allow repair/reset.");
        Pass("confirmed target shows its own status and icon location");

        Control<TextBox>(window, "FolderPath").Text = b;
        Assert(!Control<FrameworkElement>(window, "StateButtons").IsEnabled && !Control<Button>(window, "RepairButton").IsEnabled && !Control<Button>(window, "ResetButton").IsEnabled, "Editing A to B left mutation controls enabled.");
        bool invoked = false;
        await InvokeTask(window, "Apply", (Func<string, OperationResult>)(target =>
        {
            invoked = true;
            return engine.Set(target, WorkStatus.Done);
        }));
        Assert(!invoked && engine.ReadState(b) is null, "Unconfirmed edited target was modified.");
        Assert(engine.ReadState(a)?.Status == WorkStatus.Doing, "Original target changed after path edit.");
        Pass("editing A to B blocks even a direct apply until confirmation");

        await InvokeTask(window, "Refresh");
        Assert(Control<RadioButton>(window, "LocalMode").IsChecked == true && Control<RadioButton>(window, "PortableMode").IsChecked == false, "A's portable mode leaked into empty B.");
        Assert(Control<FrameworkElement>(window, "StateButtons").IsEnabled, "Empty confirmed target should allow its first state.");
        Assert(!Control<RadioButton>(window, "LocalMode").IsEnabled && !Control<RadioButton>(window, "PortableMode").IsEnabled, "Empty target exposes icon location before its first state.");
        Assert(!Control<Button>(window, "RepairButton").IsEnabled && !Control<Button>(window, "ResetButton").IsEnabled && !Control<Button>(window, "ModeApplyButton").IsEnabled, "Empty target exposes actions requiring stored state.");
        Pass("new target resets icon location and state-dependent actions");

        await Select(window, broken);
        string staleFailure = Control<TextBlock>(window, "ResultText").Text;
        Assert(!string.IsNullOrWhiteSpace(staleFailure), "Read failure has no explanation.");
        Assert(!Control<FrameworkElement>(window, "StateButtons").IsEnabled, "Unreadable state should not permit mutations.");
        await Select(window, b);
        Assert(Control<TextBlock>(window, "ResultText").Text != staleFailure, "Previous target error survived successful target selection.");
        Assert(!Control<TextBlock>(window, "CurrentState").Text.Contains("읽지 못", StringComparison.Ordinal), "Previous read error survived in current state.");
        Pass("switching from an unreadable target clears stale errors");

        await Select(window, Path.Combine(suite, "missing folder"));
        Assert(!Control<FrameworkElement>(window, "StateButtons").IsEnabled && !Control<Button>(window, "RepairButton").IsEnabled && !Control<Button>(window, "ResetButton").IsEnabled, "Invalid folder enabled mutations.");
        bool invalidInvoked = false;
        await InvokeTask(window, "Apply", (Func<string, OperationResult>)(target =>
        {
            invalidInvoked = true;
            return engine.Set(target, WorkStatus.Done);
        }));
        Assert(!invalidInvoked, "Invalid target reached a mutation.");
        Pass("invalid target remains disabled after failed confirmation");

        Ok(engine.Set(recovery, WorkStatus.Todo));
        byte[]? journal = null;
        var interrupted = new FolderStateEngine(Path.Combine(AppContext.BaseDirectory, "icons"))
        {
            TransactionCheckpoint = checkpoint =>
            {
                if (checkpoint != "journal") return;
                journal = File.ReadAllBytes(Path.Combine(recovery, FolderStateEngine.JournalFile));
                throw new IOException("Capture a valid journal for a UI recovery fixture.");
            }
        };
        Assert(!interrupted.Set(recovery, WorkStatus.Done).Success && journal is not null, "Could not prepare recovery fixture.");
        File.WriteAllBytes(Path.Combine(recovery, FolderStateEngine.JournalFile), journal!);
        await Select(window, recovery);
        Assert(Control<Button>(window, "RepairButton").IsEnabled, "Pending recovery must leave repair available.");
        Assert(!Control<FrameworkElement>(window, "StateButtons").IsEnabled && !Control<Button>(window, "ResetButton").IsEnabled && !Control<Button>(window, "ModeApplyButton").IsEnabled, "Pending recovery exposed other mutations.");
        await InvokeTask(window, "Apply", (Func<string, OperationResult>)engine.Repair);
        Assert(engine.ReadState(recovery)?.Status == WorkStatus.Todo, "Repair did not recover the interrupted target.");
        Assert(Control<FrameworkElement>(window, "StateButtons").IsEnabled, "Repair did not restore normal target actions.");
        Pass("pending recovery offers repair and returns to normal actions");

        byte[]? firstJournal = null;
        var interruptedFirstState = new FolderStateEngine(Path.Combine(AppContext.BaseDirectory, "icons"))
        {
            TransactionCheckpoint = checkpoint =>
            {
                if (checkpoint != "journal") return;
                firstJournal = File.ReadAllBytes(Path.Combine(emptyRecovery, FolderStateEngine.JournalFile));
                throw new IOException("Capture the first state journal before rollback.");
            }
        };
        Assert(!interruptedFirstState.Set(emptyRecovery, WorkStatus.Doing).Success && firstJournal is not null, "Could not prepare first-state recovery fixture.");
        File.WriteAllBytes(Path.Combine(emptyRecovery, FolderStateEngine.JournalFile), firstJournal!);
        await Select(window, emptyRecovery);
        Assert(Control<Button>(window, "RepairButton").IsEnabled && !Control<FrameworkElement>(window, "StateButtons").IsEnabled, "Interrupted first state must offer recovery before a new state.");
        OperationResult? firstRepair = null;
        await InvokeTask(window, "Apply", (Func<string, OperationResult>)(target => firstRepair = engine.Repair(target)));
        Assert(firstRepair is { Success: false, ErrorCode: "state_missing" }, "First-state recovery should report that no stored state remains.");
        Assert(!File.Exists(Path.Combine(emptyRecovery, FolderStateEngine.JournalFile)) && engine.ReadState(emptyRecovery) is null, "First-state recovery did not restore the unmarked folder.");
        Assert(Control<FrameworkElement>(window, "StateButtons").IsEnabled, "Recovered unmarked folder cannot receive its first state.");
        Assert(!Control<Button>(window, "RepairButton").IsEnabled && !Control<Button>(window, "ResetButton").IsEnabled, "Recovered unmarked folder still offers repair/reset.");
        Assert(Control<TextBlock>(window, "ResultText").Text.Contains(firstRepair!.Message, StringComparison.Ordinal), "Repair outcome was lost while refreshing the recovered folder.");
        Pass("first-state recovery permits a new state after state_missing");

        await Select(window, a);
        Control<RadioButton>(window, "LocalMode").IsChecked = true;
        var doneButton = Control<Panel>(window, "StateButtons").Children.OfType<Button>().Single(button => (string)button.Tag == nameof(WorkStatus.Done));
        doneButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        while (!Control<TextBox>(window, "FolderPath").IsEnabled) await Task.Delay(10);
        Assert(engine.ReadState(a)?.Status == WorkStatus.Done && engine.ReadState(a)?.Mode == IconMode.Portable, "Status action silently applied a pending icon location selection.");
        Pass("status button preserves the saved icon location despite an unapplied selection");

        var before = engine.ReadState(a)!;
        Control<RadioButton>(window, "LocalMode").IsChecked = true;
        Assert(Control<Button>(window, "ModeApplyButton").IsEnabled, "Changing the icon location did not enable its apply action.");
        Control<Button>(window, "ModeApplyButton").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        while (!Control<TextBox>(window, "FolderPath").IsEnabled) await Task.Delay(10);
        var after = engine.ReadState(a)!;
        Assert(after.Mode == IconMode.Local && after.Status == before.Status && after.Updated == before.Updated, "Icon location update changed the work status or its time.");
        Assert(!Control<Button>(window, "ModeApplyButton").IsEnabled, "Saved icon location still appears pending.");
        Assert(Control<TextBlock>(window, "ResultText").Text.Contains(Path.GetFileName(a), StringComparison.Ordinal), "Operation result does not name its target folder.");
        Pass("icon location apply preserves the state time and names its target");

        await InvokeTask(window, "Apply", (Func<string, OperationResult>)(target => new(false, "set", target, "doing", null, "TEST: operation failed", "io_error")));
        string failureTitle = Control<TextBlock>(window, "ResultTitle").Text;
        await InvokeTask(window, "Apply", (Func<string, OperationResult>)(target => engine.Set(target, WorkStatus.Done)));
        string successTitle = Control<TextBlock>(window, "ResultTitle").Text;
        Assert(!string.IsNullOrWhiteSpace(successTitle) && successTitle != failureTitle, "Success and failure are indistinguishable.");
        Assert(!Control<TextBlock>(window, "ResultText").Text.Contains("TEST: operation failed", StringComparison.Ordinal), "Previous operation error survived a success.");
        Assert(Control<TextBlock>(window, "CurrentState").Text.Contains(WorkStatus.Done.Label(), StringComparison.Ordinal), "Successful operation did not refresh the saved state.");
        await InvokeTask(window, "Apply", (Func<string, OperationResult>)(target => new(true, "repair", target, "done", "done", "TEST: saved", Warning: "TEST: display needs checking")));
        Assert(Control<TextBlock>(window, "ResultTitle").Text != successTitle && Control<TextBlock>(window, "ResultTitle").Text != failureTitle, "Saved-with-warning is not distinct from success or failure.");
        Assert(Control<TextBlock>(window, "ResultText").Text.Contains("TEST: display needs checking", StringComparison.Ordinal), "Display warning was omitted.");
        Pass("success, failure and saved-with-warning have separate feedback");

        await Select(window, readBackFailure);
        FileStream? lockedState = null;
        OperationResult? savedResult = null;
        try
        {
            await InvokeTask(window, "Apply", (Func<string, OperationResult>)(target =>
            {
                savedResult = engine.Set(target, WorkStatus.Doing);
                Ok(savedResult);
                // Hold only the fixed state file after a successful commit. The UI's
                // following read fails, while the operation result remains successful.
                lockedState = new FileStream(Path.Combine(target, FolderStateEngine.StateFile), FileMode.Open, FileAccess.Read, FileShare.None);
                return savedResult;
            }));
            Assert(savedResult is { Success: true } && lockedState is not null, "Could not isolate a post-save read failure.");
            Assert(Control<TextBlock>(window, "ResultTitle").Text.Contains("작업 완료 · 추가 확인", StringComparison.Ordinal), "A post-save read failure was reported as a failed save.");
            Assert(Control<TextBlock>(window, "ResultText").Text.Contains(savedResult!.Message, StringComparison.Ordinal), "The successful save message was lost when rereading failed.");
            Assert(!Control<FrameworkElement>(window, "StateButtons").IsEnabled && !Control<Button>(window, "RepairButton").IsEnabled && !Control<Button>(window, "ResetButton").IsEnabled, "Failed reread left stale state available for another mutation.");
        }
        finally { lockedState?.Dispose(); }
        await InvokeTask(window, "Refresh");
        Assert(engine.ReadState(readBackFailure)?.Status == WorkStatus.Doing, "The committed state was not retained after the read lock was released.");
        Assert(Control<FrameworkElement>(window, "StateButtons").IsEnabled && Control<Button>(window, "RepairButton").IsEnabled, "Confirming after the read lock was released did not restore normal actions.");
        Pass("a successful save survives a failed reread and can be confirmed again");

        Console.WriteLine("CHECK final fixture preservation");
        Assert(File.ReadAllText(business) == "KEEP BUSINESS CONTENT" && Directory.Exists(b), "Business fixture changed.");
        Console.WriteLine("CHECK unrelated folder state");
        Assert(engine.ReadState(b) is null, "An unrelated selected folder received a state.");
        Console.WriteLine("CHECK UI flow body complete");
    }

    private static async Task Select(FolderState.App.MainWindow window, string folder)
    {
        Control<TextBox>(window, "FolderPath").Text = folder;
        await InvokeTask(window, "Refresh");
    }

    private static Task InvokeTask(FolderState.App.MainWindow window, string method, params object[] arguments)
    {
        var member = typeof(FolderState.App.MainWindow).GetMethod(method, BindingFlags.NonPublic | BindingFlags.Instance)
            ?? throw new Exception($"Missing UI operation: {method}");
        return member.Invoke(window, arguments) as Task ?? throw new Exception($"UI operation {method} must return Task.");
    }

    private static T Control<T>(FolderState.App.MainWindow window, string name) where T : FrameworkElement =>
        window.FindName(name) as T ?? throw new Exception($"Required control missing: {name}");

    private static void Wait(Task task)
    {
        if (!task.IsCompleted)
        {
            var dispatcher = Dispatcher.CurrentDispatcher;
            var frame = new DispatcherFrame();
            bool timedOut = false;
            var timeout = new DispatcherTimer { Interval = TimeSpan.FromSeconds(45) };
            timeout.Tick += (_, _) => { timedOut = true; frame.Continue = false; };
            timeout.Start();
            _ = task.ContinueWith(completed =>
            {
                Console.WriteLine("CHECK UI flow task completed: " + completed.Status);
                frame.Continue = false;
            }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
            Dispatcher.PushFrame(frame);
            timeout.Stop();
            Console.WriteLine($"CHECK dispatcher frame exited: task={task.Status}, shutdown={dispatcher.HasShutdownStarted}");
            if (timedOut) throw new TimeoutException("WPF interaction checks exceeded 45 seconds.");
            if (!task.IsCompleted) throw new InvalidOperationException("The WPF dispatcher stopped before interaction checks completed.");
        }
        task.GetAwaiter().GetResult();
    }

    private static string FindRepository()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
            if (File.Exists(Path.Combine(directory.FullName, "src", "FolderState.App", "FolderState.App.csproj"))) return directory.FullName;
        throw new DirectoryNotFoundException("Run UI checks from a repository build so fixtures remain under artifacts.");
    }

    private static string Folder(string suite, string name)
    { string path = Path.Combine(suite, name); Directory.CreateDirectory(path); return path; }
    private static void Ok(OperationResult result) => Assert(result.Success, $"{result.ErrorCode}: {result.Message}");
    private static void Assert(bool condition, string message)
    { if (!condition) throw new Exception(message); }
    private static void Pass(string name) { passed++; Console.WriteLine("PASS " + name); }
}
