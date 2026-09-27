using System.Diagnostics;

namespace ImageCopySave.Tests;

internal sealed record TestRunOptions(bool RequireClipboard, bool UseCurrentClipboard,
    bool AcknowledgeClipboardOverwrite, bool ModeContractTests, bool ListClipboardCases,
    string? ClipboardCase, string? Report, string? Helper)
{
    public static TestRunOptions Parse(string[] args)
    {
        bool require = false, current = false, acknowledge = false, contracts = false, list = false;
        string? scenario = null, report = null, helper = null;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        for (int i = 0; i < args.Length; i++)
        {
            string option = args[i];
            if (!seen.Add(option)) throw new ArgumentException("Duplicate option: " + option);
            string Value()
            {
                if (++i >= args.Length || args[i].StartsWith("--", StringComparison.Ordinal))
                    throw new ArgumentException("A value is required for " + option);
                return args[i];
            }
            switch (option)
            {
                case "--require-clipboard": require = true; break;
                case "--use-current-clipboard": current = true; break;
                case "--acknowledge-clipboard-overwrite": acknowledge = true; break;
                case "--mode-contract-tests": contracts = true; break;
                case "--list-clipboard-cases": list = true; break;
                case "--clipboard-case": scenario = Value(); break;
                case "--report": report = Value(); break;
                case "--helper": helper = Value(); break;
                default: throw new ArgumentException("Unknown option: " + option);
            }
        }
        if (current != acknowledge)
            throw new ArgumentException("Current-session testing requires BOTH --use-current-clipboard and --acknowledge-clipboard-overwrite.");
        if ((contracts || list) && (current || require || scenario != null || helper != null) || contracts && list)
            throw new ArgumentException("Safe mode-contract/list commands cannot be combined with clipboard execution options.");
        if (scenario != null && !ClipboardTests.CaseNames.Contains(scenario, StringComparer.Ordinal))
            throw new ArgumentException("Unknown clipboard case; use --list-clipboard-cases.");
        return new(require || current || scenario != null, current, acknowledge, contracts, list, scenario, report, helper);
    }
}

/// <summary>The Local namespace scopes the single coordinator mutex to this Windows session.</summary>
internal sealed class CurrentClipboardLease : IDisposable
{
    internal const string MutexName = @"Local\ImageCopySave.Tests.CurrentClipboard";
    private readonly Mutex mutex;
    private EventWaitHandle? authorization;
    private bool ownsMutex;
    public string Token { get; } = Guid.NewGuid().ToString("N");
    private static string EventName(string token) => @"Local\ImageCopySave.Tests.ClipboardRun-" + token;

    public CurrentClipboardLease()
    {
        mutex = new Mutex(false, MutexName);
        try
        {
            // An abandoned coordinator may still have descendants shutting down. Fail closed
            // for this attempt instead of assuming that its clipboard operation has ended.
            try { ownsMutex = mutex.WaitOne(0); }
            catch (AbandonedMutexException) { ownsMutex = true; throw new TestUnavailableException("A previous clipboard coordinator ended unexpectedly; this attempt did not access the clipboard. Retry after its owned workers have exited."); }
            if (!ownsMutex) throw new TestUnavailableException("Another current-session clipboard coordinator is active; no clipboard access was attempted.");
            authorization = new EventWaitHandle(true, EventResetMode.ManualReset, EventName(Token));
        }
        catch { Dispose(); throw; }
    }

    public static void VerifyWorkerAuthorization(string token)
    {
        if (!Guid.TryParseExact(token, "N", out _))
            throw new TestUnavailableException("Invalid current-session coordinator token.");
        try
        {
            using var signal = EventWaitHandle.OpenExisting(EventName(token));
            if (!signal.WaitOne(0)) throw new TestUnavailableException("The clipboard coordinator has stopped.");
            using var active = Mutex.OpenExisting(MutexName);
            bool acquired = false;
            try
            {
                try { acquired = active.WaitOne(0); }
                catch (AbandonedMutexException) { acquired = true; }
                if (acquired) throw new TestUnavailableException("No active current-session clipboard coordinator owns the session mutex.");
            }
            finally { if (acquired) active.ReleaseMutex(); }
        }
        catch (WaitHandleCannotBeOpenedException)
        { throw new TestUnavailableException("No matching current-session clipboard coordinator is active."); }
    }

    public void Dispose()
    {
        authorization?.Reset(); authorization?.Dispose(); authorization = null;
        if (ownsMutex) { mutex.ReleaseMutex(); ownsMutex = false; }
        mutex.Dispose();
    }
}

internal static class ClipboardModeContractTests
{
    // These checks do not call any clipboard API or start a product/helper process.
    public static void Register(Action<string, Action> test)
    {
        test("clipboard mode defaults to private isolation", () =>
        {
            var options = TestRunOptions.Parse([]);
            Check.That(!options.UseCurrentClipboard && !options.AcknowledgeClipboardOverwrite);
        });
        test("clipboard mode requires explicit paired acknowledgement", () =>
        {
            Check.Throws<ArgumentException>(() => TestRunOptions.Parse(["--use-current-clipboard"]));
            Check.Throws<ArgumentException>(() => TestRunOptions.Parse(["--acknowledge-clipboard-overwrite"]));
            var options = TestRunOptions.Parse(["--use-current-clipboard", "--acknowledge-clipboard-overwrite"]);
            Check.That(options.UseCurrentClipboard && options.RequireClipboard && options.AcknowledgeClipboardOverwrite);
        });
        test("clipboard mode rejects unsafe or ambiguous option combinations", () =>
        {
            foreach (string[] args in new string[][] {
                ["--use-current-clipboard", "--use-current-clipboard", "--acknowledge-clipboard-overwrite"],
                ["--mode-contract-tests", "--use-current-clipboard", "--acknowledge-clipboard-overwrite"],
                ["--list-clipboard-cases", "--clipboard-case", "alpha-roundtrip"],
                ["--clipboard-case", "unknown"], ["--clipboard-case"], ["--report", "--require-clipboard"],
                ["--coordinator-token", Guid.NewGuid().ToString("N")] })
                Check.Throws<ArgumentException>(() => TestRunOptions.Parse(args));
        });
        test("clipboard mode single case remains explicit and strict", () =>
        {
            var options = TestRunOptions.Parse(["--clipboard-case", "alpha-roundtrip"]);
            Check.That(options.ClipboardCase == "alpha-roundtrip" && options.RequireClipboard && !options.UseCurrentClipboard);
        });
        test("clipboard mode context rejects wrong station or desktop", () =>
        {
            Check.That(ClipboardTests.IsCurrentContext("WinSta0", "Default", true));
            Check.That(!ClipboardTests.IsCurrentContext("WinSta0", "Test", true));
            Check.That(!ClipboardTests.IsCurrentContext("private", "Default", false));
            Check.That(!ClipboardTests.IsCurrentContext("WinSta0", "Default", false));
        });
        test("clipboard mode worker cannot self-authorize", () =>
        {
            Check.Throws<TestUnavailableException>(() => CurrentClipboardLease.VerifyWorkerAuthorization("bad-token"));
            Check.Throws<TestUnavailableException>(() => CurrentClipboardLease.VerifyWorkerAuthorization(Guid.NewGuid().ToString("N")));
        });
        test("clipboard mode session lease rejects concurrent coordinators", () =>
        {
            using var lease = new CurrentClipboardLease();
            Exception? failure = null;
            var contender = new Thread(() =>
            {
                try
                {
                    CurrentClipboardLease.VerifyWorkerAuthorization(lease.Token);
                    Check.Throws<TestUnavailableException>(() => { using var duplicate = new CurrentClipboardLease(); });
                }
                catch (Exception error) { failure = error; }
            });
            contender.Start();
            Check.That(contender.Join(5000), "Session lease contender did not finish.");
            if (failure != null) throw failure;
        });
    }
}
