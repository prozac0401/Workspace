using System.Globalization;

namespace ImageCopySave.Helper;

// Version 1: --shell copy|save absolute-path invoke-sequence parent-hwnd
// Successful save output is exactly the UTF-8 absolute path plus a newline.
// No shell interpreter, ambient destination, HWND lookup or clipboard recapture
// may replace a value supplied by the invoking Explorer command.
internal sealed record ShellRequest(string Operation, string Target, uint Sequence, nint ParentWindow)
{
    public static bool TryParse(string[] args, out ShellRequest? result)
    {
        result = null;
        if (args.Length != 5 || args[0] != "--shell" || args[1] is not ("copy" or "save") ||
            string.IsNullOrWhiteSpace(args[2]) || args[2].IndexOfAny(['\0', '\r', '\n']) >= 0 ||
            !Path.IsPathFullyQualified(args[2]) ||
            !uint.TryParse(args[3], NumberStyles.None, CultureInfo.InvariantCulture, out uint sequence) ||
            !ulong.TryParse(args[4], NumberStyles.None, CultureInfo.InvariantCulture, out ulong parent) ||
            parent > (IntPtr.Size == 8 ? (ulong)long.MaxValue : int.MaxValue)) return false;
        result = new ShellRequest(args[1], args[2], sequence, (nint)parent);
        return true;
    }
}

internal sealed record WorkerResult(int ExitCode, string Output, string Error);
