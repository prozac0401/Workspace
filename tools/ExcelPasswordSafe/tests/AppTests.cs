using System;
using System.Diagnostics;
using System.IO;
using System.Security;
using System.Security.AccessControl;
using System.Security.Principal;
using ExcelPasswordSafe;

public static class AppTests
{
    static int count;
    static void Assert(bool condition, string name) { if (!condition) throw new Exception(name); count++; Console.WriteLine("PASS " + name); }
    static SecureString Secret(string value) { var secret = new SecureString(); foreach (char ch in value) secret.AppendChar(ch); return secret; }
    public static int Main(string[] args)
    {
        string directory = args[0];
        using (var empty = Secret(""))
        using (var old = Secret("OldTest42!"))
        using (var next = Secret("New한글42!"))
        using (var longValue = Secret("1234567890123456"))
        using (var caseValue = Secret("oldTest42!"))
        {
            Assert(Workflow.ValidatePasswords("Encrypt", empty, next, next) == null, "Encrypt with matching new password");
            Assert(Workflow.ValidatePasswords("Decrypt", old, empty, empty) == null, "Decrypt requires only current password");
            Assert(Workflow.ValidatePasswords("ChangePassword", old, next, next) == null, "Change current and new");
            Assert(Workflow.ValidatePasswords("ChangePassword", old, old, old) != null, "Change rejects same password");
            Assert(Workflow.ValidatePasswords("ChangePassword", empty, next, next) != null, "Change requires current password");
            Assert(Workflow.ValidatePasswords("Decrypt", empty, empty, empty) != null, "Decrypt requires current password");
            Assert(Workflow.ValidatePasswords("Encrypt", empty, next, old) != null, "Confirmation mismatch blocked");
            Assert(Workflow.ValidatePasswords("Encrypt", empty, longValue, longValue) != null, "Excel length limit enforced");
            Assert(Workflow.ValidatePasswords("Encrypt", empty, empty, empty) != null, "Empty new password blocked");
            Assert(Workflow.ValidatePasswords("Unknown", old, next, next) != null, "Unknown mode rejected");
            Assert(!Workflow.PasswordsEqual(old, caseValue), "Password comparison case sensitive");
            Assert(Workflow.ProtectPassword(empty) == "", "Empty IPC secret");
            string cipher = Workflow.ProtectPassword(next);
            Assert(!cipher.Contains("New") && cipher.Length > 100, "IPC encrypted");
            File.WriteAllText(Path.Combine(directory, "cipher.txt"), cipher);
        }
        Assert(Workflow.QuoteArgument("a b") == "\"a b\"", "Spaces quoted");
        Assert(Workflow.QuoteArgument("x\\") == "\"x\\\\\"", "Trailing slash escaped");
        Assert(Workflow.QuoteArgument("a\"b") == "\"a\\\"b\"", "Quotes escaped");
        Assert(Workflow.QuoteArgument("a&b%#'$()").Contains("a&b%#'$()"), "Shell metacharacters remain data");
        var start = Workflow.EngineStartInfo(@"C:\한글 path\app", @"C:\한글 path\run");
        Assert(!start.UseShellExecute && start.CreateNoWindow, "Engine starts directly without shell or console");
        Assert(!start.Arguments.Contains("New") && start.Arguments.Contains("request.json"), "Command line contains no password");
        Assert(Workflow.ValidateFile(Path.Combine(directory, "book.csv")) != null, "Unsupported extension rejected");
        Assert(Workflow.ValidateFile(Path.Combine(directory, "missing.xlsx")) != null, "Missing file rejected");
        Assert(Workflow.ValidateFile(@"\\nonexistent-server\share\book.xlsx").StartsWith("로컬"), "Network rejected before file access");
        Assert(Workflow.ValidateFile("relative.xlsx").StartsWith("로컬"), "Relative path rejected before file access");
        string file = Path.Combine(directory, "~$book.xlsx"); File.WriteAllText(file, "fixture");
        Assert(Workflow.ValidateFile(file) != null, "Excel lock file rejected");
        file = Path.Combine(directory, "book.xlsx"); File.WriteAllText(file, "fixture");
        Assert(Workflow.ValidateFile(file) == null, "Explicit supported file accepted for engine validation");
        Assert(Workflow.Hash(file).Length == 64, "Source approval hash");
        File.SetAttributes(file, FileAttributes.ReadOnly);
        Assert(Workflow.ValidateFile(file) != null, "Readonly rejected before hash");
        File.SetAttributes(file, FileAttributes.Normal);
        string privatePath = Path.Combine(directory, "private"); Workflow.CreatePrivateDirectory(privatePath);
        var acl = Directory.GetAccessControl(privatePath);
        Assert(acl.AreAccessRulesProtected, "Backup directory disables inherited ACL");
        Assert(acl.GetAccessRules(true, true, typeof(SecurityIdentifier)).Count == 2, "Only current user and SYSTEM access");
        Assert(PasswordWindow.CategoryMessage("CommitUncertain").Contains("재시도하지"), "Uncertain commit needs inspection");
        Console.WriteLine("PASS total=" + count); return 0;
    }
}
