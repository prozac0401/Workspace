using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using VisibleCellsPaste;

// Public so the production assembly's dynamic Excel adapter can access this fault-injection double.
// This is not an Excel COM integration test and never creates an Excel process.
public sealed class GlobalRecoveryApplication
{
    public readonly List<string> SetterAttempts = new List<string>();
    public string FailedSetter;
    public bool FailAfterAssignment;
    public bool FailStatusGet, FailStatusRestore;
    public bool ForbidAnyAccess;
    public int Accesses, CellAccesses;
    public object CalculationState = -4135, StatusState = "during write";
    public bool ScreenState = true, EventsState = true;
    public readonly object Book = new object();
    public readonly GlobalRecoverySheet Sheet;
    public readonly GlobalRecoverySelection Selected;
    public GlobalRecoveryApplication() { Sheet = new GlobalRecoverySheet(this); Selected = new GlobalRecoverySelection(); }
    private void Access() { Accesses++; if (ForbidAnyAccess) throw new Exception("Excel access after fail-closed guard"); }
    private void Attempt(string property, Action assign)
    {
        Access(); SetterAttempts.Add(property);
        bool fail = FailedSetter == property || FailedSetter == "*";
        if (fail && !FailAfterAssignment) throw new COMException("Synthetic " + property + " restoration failure", unchecked((int)0x800A03EC));
        assign();
        if (fail) throw new COMException("Synthetic " + property + " partial setter failure", unchecked((int)0x800A03EC));
    }
    public object Calculation { get { Access(); return CalculationState; } set { Attempt("Calculation", delegate { CalculationState = value; }); } }
    public bool ScreenUpdating { get { Access(); return ScreenState; } set { Attempt("ScreenUpdating", delegate { ScreenState = value; }); } }
    public object StatusBar { get { Access(); if (FailStatusGet) throw new COMException("Synthetic status snapshot failure"); return StatusState; } set { Attempt("StatusBar", delegate { if (FailStatusRestore && Object.Equals(value, false)) throw new InvalidOperationException("Synthetic status restoration verification failure"); StatusState = value; }); } }
    public bool EnableEvents { get { Access(); return EventsState; } set { Attempt("EnableEvents", delegate { EventsState = value; }); } }
    public object ActiveProtectedViewWindow { get { Access(); return null; } }
    public object ActiveWorkbook { get { Access(); return Book; } }
    public object ActiveSheet { get { Access(); return Sheet; } }
    public GlobalRecoverySelection Selection { get { Access(); return Selected; } }
}
public sealed class GlobalRecoverySheet
{
    private readonly GlobalRecoveryApplication app;
    public GlobalRecoverySheet(GlobalRecoveryApplication value) { app = value; }
    public string Name { get { return "Synthetic"; } }
    public object Cells { get { app.CellAccesses++; throw new Exception("Unexpected cell access after failed state restoration"); } }
    public object Range { get { app.CellAccesses++; throw new Exception("Unexpected range access after failed state restoration"); } }
}
public sealed class GlobalRecoverySelection { public string Address { get { return "$E$2"; } } }


// Managed fault injection for the exact production reset algorithm. Actual Excel COM
// default-control behavior is verified separately by the owned-host integration harness.
public sealed class StatusRestoreApplication
{
    public readonly List<object> Writes = new List<object>();
    public object Current = "during operation", ResetResult = false;
    public object FalseResult = false;
    public int Reads, ThrowOnWrite, ThrowOnRead;
    public object StatusBar
    {
        get { Reads++; if (Reads == ThrowOnRead) throw new COMException("Synthetic status read failure"); return Current; }
        set
        {
            Writes.Add(value); if (Writes.Count == ThrowOnWrite) throw new COMException("Synthetic status write failure");
            if (value is bool && !(bool)value) Current = FalseResult;
            else if (value is string && (string)value == "") Current = ResetResult;
            else Current = value;
        }
    }
}

internal static class GlobalStateRecoveryTests
{
    private static int passed, failed;
    private static readonly string[] Order = { "Calculation", "ScreenUpdating", "StatusBar", "EnableEvents" };
    private static readonly MethodInfo Restore = typeof(ExcelEngine).GetMethod("RestoreGlobals", BindingFlags.Instance | BindingFlags.NonPublic);
    private static FieldInfo Field(string name) { return typeof(ExcelEngine).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic); }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static void Test(string name, Action test)
    {
        try { test(); passed++; Console.WriteLine("PASS " + name); }
        catch (Exception error) { failed++; Console.WriteLine("FAIL " + name + ": " + error); }
    }
    private static ClipboardSnapshot Source()
    { return new ClipboardSnapshot("synthetic unit", 1, 1, 1, true, new[] { CellValue.Number(85) }, "No real clipboard or Excel application"); }
    private static void Validation(Action action, string expected)
    {
        try { action(); }
        catch (ValidationException error) { Check(error.Code == expected, "Expected " + expected + ", got " + error.Code); Check(error.Message.Contains("변경된 셀은 없습니다"), "Missing no-change indication"); return; }
        throw new Exception("Expected refusal " + expected);
    }
    private static Exception RestoreState(ExcelEngine engine, bool oldSuppress)
    {
        try { Restore.Invoke(engine, new object[] { -4105, false, "original status", false, oldSuppress }); return null; }
        catch (TargetInvocationException error) { return error.InnerException; }
    }
    private static void SeedTransaction(ExcelEngine engine, bool suppress)
    {
        Field("busy").SetValue(engine, true); Field("undoAllowed").SetValue(engine, true);
        ((UndoEpoch)Field("epoch").GetValue(engine)).Suppress = suppress;
        typeof(ExcelEngine).GetProperty("LastOutcome").GetSetMethod(true).Invoke(engine, new object[] { "success" });
    }
    private static void AssertAllRestoresAttempted(GlobalRecoveryApplication app)
    { Check(app.SetterAttempts.SequenceEqual(Order), "A failed setter prevented another global state restoration attempt"); }
    private static void AssertFutureWorkBlocked(ExcelEngine engine, GlobalRecoveryApplication app)
    {
        app.Accesses = 0; app.ForbidAnyAccess = true;
        Validation(delegate { engine.Prepare(Source()); }, "VCP-RECOVERY-REQUIRED");
        Check(app.Accesses == 0 && app.CellAccesses == 0, "Prepare touched Excel after restoration failure");
        app.ForbidAnyAccess = false;
        var selection = new SelectionSnapshot("synthetic", 2, 2, 5, 1, 1, 1, false, false, new[] { new TargetCell("synthetic", 2, 5, false) });
        var pending = new PreparedPaste { Book = app.Book, Sheet = app.Sheet, Selection = app.Selected, Address = "$E$2", SheetName = "Synthetic", Plan = Planner.Build(Source(), selection) };
        Validation(delegate { engine.Apply(pending, null, null); }, "VCP-RECOVERY-REQUIRED");
        Check(app.CellAccesses == 0, "A previously prepared operation reached cells after restoration failure");
    }
    private static void OneFailure(string property, bool afterAssignment)
    {
        var app = new GlobalRecoveryApplication { FailedSetter = property, FailAfterAssignment = afterAssignment };
        using (var engine = new ExcelEngine(app))
        {
            SeedTransaction(engine, true);
            Exception error = RestoreState(engine, false);
            Check(error is InvalidOperationException, "Restoration failure was not reported"); AssertAllRestoresAttempted(app);
            Check(engine.RecoveryRequired && engine.LastOutcome == "state-restore-failed", "Engine did not fail closed");
            Check(!(bool)Field("busy").GetValue(engine) && !(bool)Field("undoAllowed").GetValue(engine), "Busy or Undo remained enabled");
            Check(!((UndoEpoch)Field("epoch").GetValue(engine)).Suppress, "Event suppression was not restored");
            Check(engine.RecoveryDetail.Contains(property + ":800A03EC") && engine.RecoveryDetail.Contains("success"), "Missing failure property/HRESULT or prior data outcome");
            if (property != "Calculation" || afterAssignment) Check(Object.Equals(app.CalculationState, -4105), "Calculation not restored");
            if (property != "ScreenUpdating" || afterAssignment) Check(!app.ScreenState, "ScreenUpdating not restored");
            if (property != "StatusBar" || afterAssignment) Check(Object.Equals(app.StatusState, "original status"), "StatusBar not restored");
            if (property != "EnableEvents" || afterAssignment) Check(!app.EventsState, "EnableEvents not restored");
            // Keep the injected COM setter fault active: refusal must precede all app access.
            AssertFutureWorkBlocked(engine, app);
        }
    }

    private static void RestoreWithExcelVerification(object application, object prior)
    {
        // Exercises the real algorithm with injected postconditions; this does not model COM marshalling.
        var method = typeof(ExcelEngine).GetMethod("RestoreStatusBarCore", BindingFlags.Static | BindingFlags.NonPublic);
        try { method.Invoke(null, new object[] { application, prior, true }); }
        catch (TargetInvocationException error) { throw error.InnerException; }
    }
    private static void StatusRestoreRegression()
    {
        Test("managed original false uses the direct setter without a COM probe", delegate {
            var app = new StatusRestoreApplication(); ExcelEngine.RestoreStatusBar(app, false);
            Check(app.Writes.Count == 1 && app.Writes[0] is bool && !(bool)app.Writes[0] && app.Reads == 0, "Managed restoration changed the original type or probed COM");
        });
        foreach (string prior in new[] { "FALSE", "기존 상태 메시지" }) {
            string saved = prior; Test("literal status text is preserved: " + saved, delegate {
                var app = new StatusRestoreApplication(); RestoreWithExcelVerification(app, saved);
                Check(app.Writes.Count == 1 && Object.Equals(app.Current, saved) && app.Reads == 0, "Literal status text was treated as Excel default control");
            });
        }
        Test("documented false reset avoids fallback when Excel control is verified", delegate {
            var app = new StatusRestoreApplication(); RestoreWithExcelVerification(app, false);
            Check(app.Writes.Count == 1 && app.Reads == 1 && app.Current is bool && !(bool)app.Current, "Verified default control caused an extra mutation");
        });
        Test("false rendered as text falls back and verifies Boolean default control", delegate {
            var app = new StatusRestoreApplication { FalseResult = "FALSE" }; RestoreWithExcelVerification(app, false);
            Check(app.Writes.SequenceEqual(new object[] { false, "" }) && app.Reads == 2 && app.Current is bool && !(bool)app.Current, "Fallback did not verify exact Boolean false");
        });
        Test("numeric zero is not accepted as verified Boolean default control", delegate {
            var app = new StatusRestoreApplication { FalseResult = 0 }; RestoreWithExcelVerification(app, false);
            Check(app.Writes.Count == 2 && app.Current is bool && !(bool)app.Current, "A coerced numeric result bypassed fallback");
        });
        Test("failed fallback postcondition raises an explicit restoration failure", delegate {
            var app = new StatusRestoreApplication { FalseResult = "FALSE", ResetResult = "" };
            Exception failure = null; try { RestoreWithExcelVerification(app, false); } catch (Exception error) { failure = error; }
            Check(failure is InvalidOperationException && failure.Message.Contains("VCP-STATUSBAR-RESTORE") && app.Writes.Count == 2, "Unverified reset was reported as restored");
        });
        foreach (int write in new[] { 1, 2 }) {
            int position = write; Test("status reset write failure propagates at attempt " + position, delegate {
                var app = new StatusRestoreApplication { FalseResult = "FALSE", ThrowOnWrite = position };
                Exception failure = null; try { RestoreWithExcelVerification(app, false); } catch (Exception error) { failure = error; }
                Check(failure is COMException && app.Writes.Count == position, "A failed reset setter was swallowed or retried");
            });
        }
        Test("status verification getter failure is not mistaken for restored state", delegate {
            var app = new StatusRestoreApplication { ThrowOnRead = 1 };
            Exception failure = null; try { RestoreWithExcelVerification(app, false); } catch (Exception error) { failure = error; }
            Check(failure is COMException && app.Writes.Count == 1 && app.Reads == 1, "Failed verification caused a blind reset");
        });
        Test("Prepare status snapshot getter failure remains retryable without mutations", delegate {
            var app = new GlobalRecoveryApplication { FailStatusGet = true, StatusState = false };
            using (var engine = new ExcelEngine(app)) {
                Exception failure = null; try { engine.Prepare(Source()); } catch (Exception error) { failure = error; }
                Check(failure is COMException && !engine.RecoveryRequired && app.SetterAttempts.Count == 0 && app.CellAccesses == 0, "Read-only failure mutated state or blocked retry");
                app.FailStatusGet = false;
                Validation(delegate { engine.Prepare(Source()); }, "VCP-SELECTION");
                Check(!engine.RecoveryRequired && Object.Equals(app.StatusState, false), "Retry did not restore the original state");
            }
        });
        Test("Prepare restoration failure blocks future work without accessing cells", delegate {
            var app = new GlobalRecoveryApplication { FailStatusRestore = true, StatusState = false };
            using (var engine = new ExcelEngine(app)) {
                Field("undoAllowed").SetValue(engine, true);
                Exception failure = null; try { engine.Prepare(Source()); } catch (Exception error) { failure = error; }
                Check(failure is InvalidOperationException && engine.RecoveryRequired && engine.LastOutcome == "state-restore-failed", "Prepare restoration failure was not recorded");
                Check(engine.RecoveryDetail.Contains("StatusBar:") && !(bool)Field("busy").GetValue(engine) && !(bool)Field("undoAllowed").GetValue(engine) && app.CellAccesses == 0, "Prepare restore failure retained write/undo eligibility");
                AssertFutureWorkBlocked(engine, app);
            }
        });
    }

    private static int Main()
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        StatusRestoreRegression();
        foreach (string property in Order) { string captured = property; Test("failed " + property + " isolates cleanup and blocks future writes", delegate { OneFailure(captured, false); }); }
        Test("setter mutates then throws still blocks further work", delegate { OneFailure("StatusBar", true); });
        Test("all four restore failures are aggregated without skipping cleanup", delegate {
            var app = new GlobalRecoveryApplication { FailedSetter = "*" };
            using (var engine = new ExcelEngine(app)) {
                SeedTransaction(engine, false); Exception error = RestoreState(engine, true);
                Check(error is InvalidOperationException, "Missing aggregate failure"); AssertAllRestoresAttempted(app);
                Check(Order.All(name => engine.RecoveryDetail.Contains(name + ":800A03EC")), "Lost a failed restoration property");
                Check(engine.RecoveryRequired && engine.LastOutcome == "state-restore-failed" && !(bool)Field("busy").GetValue(engine), "Cleanup state incorrect");
                Check(((UndoEpoch)Field("epoch").GetValue(engine)).Suppress, "Original true suppression was not restored");
                AssertFutureWorkBlocked(engine, app);
            }
        });
        Test("successful cleanup restores original false globals and suppression", delegate {
            var app = new GlobalRecoveryApplication();
            using (var engine = new ExcelEngine(app)) {
                SeedTransaction(engine, true); Check(RestoreState(engine, false) == null, "Unexpected cleanup failure"); AssertAllRestoresAttempted(app);
                Check(!engine.RecoveryRequired && engine.LastOutcome == "success", "Successful outcome damaged");
                Check(!(bool)Field("busy").GetValue(engine) && (bool)Field("undoAllowed").GetValue(engine), "Successful busy/Undo cleanup incorrect");
                Check(!((UndoEpoch)Field("epoch").GetValue(engine)).Suppress, "Suppression not restored");
                Check(Object.Equals(app.CalculationState,-4105) && !app.ScreenState && Object.Equals(app.StatusState,"original status") && !app.EventsState && app.CellAccesses == 0, "Original globals not restored exactly");
            }
        });
        Test("busy guard refuses before any Excel access", delegate {
            var app = new GlobalRecoveryApplication { ForbidAnyAccess = true };
            using (var engine = new ExcelEngine(app)) { Field("busy").SetValue(engine,true); Validation(delegate { engine.Prepare(Source()); }, "VCP-BUSY"); Check(app.Accesses == 0 && app.CellAccesses == 0, "Busy guard accessed Excel"); }
        });
        Console.WriteLine("RESULT: " + passed + " passed; " + failed + " failed"); return failed == 0 ? 0 : 1;
    }
}
