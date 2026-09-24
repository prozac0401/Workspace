using System;
using System.IO;
using System.Text;
using VisibleCellsPaste;

internal static class ProbeClipboard
{
    [STAThread]
    private static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        if (args.Length != 2 || args[0] != "--synthetic-only") { Console.Error.WriteLine("Usage: ProbeClipboard.exe --synthetic-only OUTPUT_DIRECTORY (only a known synthetic Excel copy)"); return 2; }
        try
        {
            string output = Path.GetFullPath(args[1]); Directory.CreateDirectory(output);
            uint process; IntPtr owner = NativeClipboard.GetClipboardOwner(); NativeClipboard.GetWindowThreadProcessId(owner, out process);
            string formats = String.Join(Environment.NewLine, NativeClipboard.ProbeFormats());
            string metadata = "sequence=" + NativeClipboard.GetClipboardSequenceNumber() + Environment.NewLine + "owner=" + owner + Environment.NewLine + "ownerPid=" + process + Environment.NewLine + formats;
            File.WriteAllText(Path.Combine(output, "clipboard-formats.txt"), metadata, Encoding.UTF8);
            Console.WriteLine(metadata);
            Console.WriteLine("CopyEvidence=" + ClipboardReader.ProbeCopyEvidence(0));
            foreach (string format in new[] { "XML Spreadsheet", "HTML Format", "Biff8", "Biff12", "Preferred DropEffect", "DataObject" })
            {
                if (!NativeClipboard.HasFormat(format)) continue;
                uint sequence; byte[] bytes = NativeClipboard.ReadFormatBytes(format, out sequence);
                File.WriteAllBytes(Path.Combine(output, format.Replace(" ", "-") + ".bin"), bytes);
                Console.WriteLine("Saved synthetic " + format + ": " + bytes.Length + " bytes; sequence=" + sequence);
            }
            ClipboardSnapshot snapshot = ClipboardReader.ReadSnapshot(0);
            string summary = "Parsed=" + snapshot.SourceRows + "x" + snapshot.SourceColumns + "; count=" + snapshot.Items.Count + "; kinds=" + String.Join(",", System.Linq.Enumerable.Select(snapshot.Items, item => item.Kind.ToString()));
            File.WriteAllText(Path.Combine(output, "clipboard-typed-summary.txt"), summary + Environment.NewLine + snapshot.Evidence, Encoding.UTF8);
            Console.WriteLine(summary);
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error.GetType().Name + ": " + (error is ValidationException ? ((ValidationException)error).Code + ": " : "") + error.Message); return 1; }
    }
}
