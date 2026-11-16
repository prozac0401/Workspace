using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using ExcelPasswordSafe;

public static class WizardTests
{
    static readonly List<object> Checks = new List<object>();
    static WorkItem Item(string path, string state, string category)
    {
        return new WorkItem { Path = path, Name = System.IO.Path.GetFileName(path), State = state, Category = category, Attempts = "3" };
    }
    static void Assert(bool value, string name)
    {
        Checks.Add(new { name, passed = value });
        if (!value) throw new InvalidOperationException(name);
        Console.WriteLine("PASS " + name);
    }
    static bool Same(string[] actual, params string[] expected)
    {
        return actual.SequenceEqual(expected, StringComparer.OrdinalIgnoreCase);
    }
    static Dictionary<string, object> Result(string status, string category, string path)
    {
        return new Dictionary<string, object> { { "status", status }, { "category", category }, { "path", path } };
    }
    static Dictionary<string, object> BatchResult(string status, params Dictionary<string, object>[] items)
    {
        return new Dictionary<string, object> { { "status", status }, { "category", "Completed" }, { "items", items } };
    }
    public static int Main(string[] args)
    {
        string output = Path.GetFullPath(args[0]);
        Directory.CreateDirectory(output);
        string status = "FAIL", error = null;
        try
        {
            const string first = @"C:\approved\한글 & 첫째.xlsx";
            const string second = @"C:\approved\nested\second.xlsm";
            const string third = @"C:\approved\third.xlsb";
            const string completed = @"C:\approved\already-complete.xlsx";
            const string skipped = @"C:\approved\already-encrypted.xlsx";
            string[] approved = { first, second, third, completed, skipped };
            var mixed = new[] {
                Item(first, "Failed", "OpenFailedPossiblePasswordOrCorruption"),
                Item(second, "Failed", "ReadOnlyAttribute"),
                Item(third, "NotProcessed", "ExistingExcel"),
                Item(completed, "Success", "SaveAsFailed"),
                Item(skipped, "Skipped", "FileInUse")
            };
            Assert(Same(WizardRules.RetryPaths(mixed, approved), first, second, third), "Mixed completion retries only approved failed or safely unprocessed files");
            Assert(mixed.All(item => item.Attempts == "3") && mixed[3].State == "Success", "Selecting manual retry neither resets history nor mutates completed results");
            Assert(WizardRules.RetryPaths(mixed, new string[0]).Length == 0, "No file is retried without an approved path");
            Assert(WizardRules.RetryPaths(new WorkItem[0], approved).Length == 0, "Empty results produce no retry targets");
            Assert(WizardRules.RetryPaths(new[] {
                Item(first, "Cancelled", "FileInUse"), Item(second, "Pending", "ReadOnlyAttribute"),
                Item(third, "Processing", "SaveAsFailed"), Item(completed, "Unexpected", "AccessDenied")
            }, approved).Length == 0, "Cancellation, pending, active and unknown states cannot become manual retry targets");

            var scope = new[] {
                Item(first, "Failed", "FileInUse"),
                Item(@"C:\approved-other\first.xlsx", "Failed", "FileInUse"),
                Item(@"C:\approved\unapproved.xlsx", "Failed", "FileInUse"),
                Item(@"C:\approved\nested\..\unapproved.xlsx", "Failed", "FileInUse"),
                Item(@"relative.xlsx", "Failed", "FileInUse")
            };
            Assert(Same(WizardRules.RetryPaths(scope, approved), first), "Approval is an exact path whitelist, not a folder or prefix permission");
            var previousCulture = Thread.CurrentThread.CurrentCulture;
            try
            {
                Thread.CurrentThread.CurrentCulture = CultureInfo.GetCultureInfo("tr-TR");
                var duplicates = new[] { Item(@"c:\APPROVED\FILE.xlsx", "Failed", "FileInUse"), Item(@"C:\approved\file.XLSX", "Failed", "ReadOnlyAttribute") };
                var actual = WizardRules.RetryPaths(duplicates, new[] { @"C:\approved\file.xlsx", @"C:\APPROVED\FILE.XLSX" });
                Assert(actual.Length == 1 && actual[0] == duplicates[0].Path, "Windows path matching and deduplication ignore case without depending on current culture");
            }
            finally { Thread.CurrentThread.CurrentCulture = previousCulture; }

            Assert(WizardRules.RetryPaths(new[] { Item(first,"Failed","FileInUse"), Item(@"C:\unapproved-root","NeedsInspection","Unrecognized") }, approved).Length == 0,
                "Any inspection state blocks the entire retry, including a backend-only root record");
            string[] unsafeCategories = { "CommitUncertain", "SourceChanged", "WorkerTimeout", "WorkerInterrupted", "WorkerCrashed", "ExcelStillRunning",
                "ExcelOwnershipOrExistingProcess", "MissingChildResult", "InvalidChildResult", "TemporaryCleanupIncomplete", "BackupChanged", "TempChanged", "SnapshotChanged", "MissingResult" };
            foreach (string category in unsafeCategories)
            {
                var unsafeItems = new[] { Item(first,"Failed","FileInUse"), Item(second,"Failed",category) };
                Assert(WizardRules.RetryPaths(unsafeItems, approved).Length == 0, "Unsafe category blocks all targets even when status is only Failed: " + category);
            }
            var discovery = new[] { "FolderAccessDenied", "FolderReadFailed", "EntryReadFailed", "FolderChangedOrUnsupported", "DirectoryNotFound", "ReparsePoint", "OfflineFileUnsupported", "AppDataExcluded" };
            Assert(discovery.All(category => WizardRules.RetryPaths(new[] { Item(second, "Failed", category) }, approved).Length == 0),
                "Discovery errors and excluded folders never become file retries, even if a supplied path is approved");
            Assert(Same(WizardRules.RetryPaths(new[] { Item(first,"Failed","FileInUse"), Item(@"C:\approved\blocked-folder","Failed","FolderAccessDenied") }, approved), first),
                "A discovery issue stays excluded without hiding an independently safe failed file");
            Assert(new[] { "SignedWorkbookUnsupported", "SharedWorkbookUnsupported", "WriteReservedUnsupported", "Excel4MacroSheetUnsupported", "UnsupportedOrMismatchedFormat", "UnsupportedExtension", "UnrecognizedFutureFailure", "" }
                .All(category => WizardRules.RetryPaths(new[] { Item(first,"Failed",category) }, approved).Length == 0),
                "Unsupported, security-related and unknown failure categories are not retried");
            Assert(Same(WizardRules.RetryPaths(new[] { Item(first,"NotProcessed","AnotherOperationRunning"), Item(second,"Failed","SaveAsFailed") }, approved), first, second),
                "Safe concurrency preflight and precommit save failures can start a newly approved retry");
            Assert(WizardRules.RetryPaths(new[] { Item(first,"Skipped","AlreadyEncrypted"), Item(second,"Skipped","AlreadyUnencrypted") }, approved).Length == 0,
                "Already encrypted or unencrypted outcomes require an explicit operation choice instead of retry");

            var emptyDocument = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>("{}");
            Assert(!ResultDocument.IsValid(emptyDocument, false, new[] { first }) && !ResultDocument.IsValid(emptyDocument, true, approved),
                "An empty final JSON object cannot be displayed as file or batch completion");
            Assert(!ResultDocument.IsValid(Result("Unexpected", "Completed", first), false, new[] { first }) &&
                !ResultDocument.IsValid(Result("Success", "", first), false, new[] { first }), "Unknown final status or missing category is invalid");
            Assert(ResultDocument.IsValid(Result("Success", "ReplacedAndVerified", first.ToUpperInvariant()), false, new[] { first }),
                "A normal single-file result matches its approved Windows path ignoring case");
            Assert(ResultDocument.IsValid(Result("Failed", "ReadOnlyAttribute", ""), false, new[] { first }),
                "Single-file failure before path assignment remains a valid explicit failure");
            Assert(!ResultDocument.IsValid(Result("Success", "ReplacedAndVerified", ""), false, new[] { first }) &&
                !ResultDocument.IsValid(Result("Success", "ReplacedAndVerified", @"C:\outside.xlsx"), false, new[] { first }),
                "Single-file success must identify the approved file");
            var okBatch = BatchResult("Success", Result("Success", "ReplacedAndVerified", first), Result("Skipped", "AlreadyEncrypted", second));
            string serialized = new JavaScriptSerializer().Serialize(okBatch);
            Assert(ResultDocument.IsValid(new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(serialized), true, new[] { first, second }),
                "Actual JSON-deserialized result arrays accept complete batch success and skip records");
            var missingItems = new Dictionary<string, object> { { "status", "Success" }, { "category", "Completed" } };
            Assert(!ResultDocument.IsValid(missingItems, true, new[] { first }), "Final batch items are required even when advisory progress already appeared complete");
            Assert(!ResultDocument.IsValid(BatchResult("Success", Result("Success", "ReplacedAndVerified", first)), true, new[] { first, second }),
                "Every approved file must have a final result");
            Assert(!ResultDocument.IsValid(BatchResult("Success", Result("Success", "ReplacedAndVerified", first), Result("Success", "ReplacedAndVerified", first.ToUpperInvariant())), true, new[] { first }),
                "Conflicting duplicate final records for one approved path are rejected");
            Assert(ResultDocument.IsValid(BatchResult("Failed", Result("NotProcessed", "ExistingExcel", first)), true, new[] { first }) &&
                ResultDocument.IsValid(BatchResult("Cancelled", Result("NotProcessed", "Cancelled", first)), true, new[] { first }),
                "Global preflight failure and cancelled batches may explicitly leave approved files unprocessed");
            Assert(ResultDocument.IsValid(BatchResult("Failed", Result("Success", "ReplacedAndVerified", first), Result("NeedsInspection", "TemporaryCleanupIncomplete", @"C:\approved")), true, new[] { first }),
                "Backend-only root cleanup inspection record is retained beside a completed file");
            Assert(ResultDocument.IsValid(BatchResult("Failed", Result("Failed", "FolderAccessDenied", @"C:\approved\blocked")), true, new string[0]),
                "Discovery-only batch failures need no approved workbook entries");
            Assert(!ResultDocument.IsValid(BatchResult("Success", Result("Failed", "FileInUse", first)), true, new[] { first }),
                "A success envelope cannot conceal a failed file");
            Assert(!ResultDocument.IsValid(BatchResult("Success", Result("Success", "ReplacedAndVerified", first), Result("Success", "ReplacedAndVerified", @"C:\outside.xlsx")), true, new[] { first }),
                "Additional backend records cannot invent successful files outside approval");
            Assert(!ResultDocument.IsValid(BatchResult("Failed", Result("Unknown", "FileInUse", first)), true, new[] { first }) &&
                !ResultDocument.IsValid(BatchResult("Failed", Result("Failed", "FileInUse", "")), true, new[] { first }),
                "Final file records require a recognized terminal state and nonempty absolute path");
            var wrongItems = new Dictionary<string, object> { { "status", "Failed" }, { "category", "BatchFailed" }, { "items", new Dictionary<string, object>() } };
            Assert(!ResultDocument.IsValid(wrongItems, true, new string[0]), "An object in place of the items array is not accepted as an empty result");
            status = "PASS";
        }
        catch (Exception ex) { error = ex.Message; Console.Error.WriteLine(error); }
        File.WriteAllText(Path.Combine(output, "wizard-results.json"), new JavaScriptSerializer().Serialize(new {
            status, assertions = Checks.Count, checks = Checks, error,
            scope = "Pure WizardRules checks against supplied app assembly; no GUI, Excel, file processing or recursive reads",
            timestamp = DateTime.UtcNow.ToString("o")
        }), new UTF8Encoding(false));
        Console.WriteLine(status + " total=" + Checks.Count);
        return status == "PASS" ? 0 : 1;
    }
}
