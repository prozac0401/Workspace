using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Text;
using VisibleCellsPaste.Installation;

internal static class BootstrapTests
{
    static int checks;
    static void Check(bool ok, string name) { if (!ok) throw new Exception(name); checks++; Console.WriteLine("PASS " + name); }
    static void Reject(Action action, string name)
    { bool rejected = false; try { action(); } catch (ArgumentException) { rejected = true; } catch (InvalidDataException) { rejected = true; } catch (IOException) { rejected = true; } Check(rejected, name); }
    static MemoryStream Zip(params string[] names)
    {
        var memory = new MemoryStream();
        using (var zip = new ZipArchive(memory, ZipArchiveMode.Create, true))
            foreach (string name in names) using (var stream = zip.CreateEntry(name).Open()) { stream.WriteByte(42); }
        memory.Position = 0; return memory;
    }
    static int Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--echo") { File.WriteAllLines(args[1], args.Skip(2).Select(a => Convert.ToBase64String(Encoding.UTF8.GetBytes(a)))); return 0; }
        string root = Path.GetFullPath(args[0]);
        try
        {
            Directory.CreateDirectory(root);
            Bootstrap.ValidateArguments(new[] { "--silent", "--directory", "C:\\한글 path's\\", "--report", "report.txt" }); Check(true, "supported arguments accepted");
            Reject(() => Bootstrap.ValidateArguments(new[] { "--wait-pid", "1" }), "internal relocation option rejected");
            Reject(() => Bootstrap.ValidateArguments(new[] { "--silent", "--silent" }), "duplicate option rejected");
            Reject(() => Bootstrap.ValidateArguments(new[] { "--uninstall", "--diagnose" }), "conflicting actions rejected");
            Reject(() => Bootstrap.ValidateArguments(new[] { "--directory", "--silent" }), "missing path rejected");
            foreach (string invalid in new[] { "../escape", "/absolute", "C:/drive", "dir\\file", "dir/../file", "dir//file", "dir/file:stream", "dir./file" })
                Reject(() => Bootstrap.EntryPath(root, invalid), "unsafe archive path rejected: " + invalid);
            using (var zip = Zip("readme.txt", "README.txt")) Reject(() => Bootstrap.Extract(zip, Path.Combine(root, "duplicate")), "Windows case duplicate rejected before extraction");
            Check(!Directory.Exists(Path.Combine(root, "duplicate")), "invalid archive creates no extraction directory");
            using (var zip = Zip("../escape")) Reject(() => Bootstrap.Extract(zip, Path.Combine(root, "traversal")), "traversal archive rejected");
            using (var zip = Zip(Enumerable.Range(0, 65).Select(i => i + ".txt").ToArray())) Reject(() => Bootstrap.Extract(zip, Path.Combine(root, "count")), "entry count bounded");
            using (var oversized = new MemoryStream())
            {
                using (var zip = new ZipArchive(oversized, ZipArchiveMode.Create, true))
                using (var stream = zip.CreateEntry("large.bin").Open())
                { byte[] block = new byte[1024 * 1024]; for (int i = 0; i < 17; i++) stream.Write(block, 0, block.Length); }
                oversized.Position = 0;
                Reject(() => Bootstrap.Extract(oversized, Path.Combine(root, "oversize")), "expanded bytes bounded");
            }
            string good = Path.Combine(root, "valid");
            using (var zip = Zip("nested/data.txt", "readme.txt"))
            {
                var files = Bootstrap.Extract(zip, good);
                Check(files.Count == 2 && File.ReadAllBytes(Path.Combine(good, "nested/data.txt")).SequenceEqual(new byte[] { 42 }), "valid archive bytes extracted");
                string unknown = Path.Combine(good, "unknown.txt"); File.WriteAllText(unknown, "preserve");
                Bootstrap.Cleanup(good, files);
                Check(File.ReadAllText(unknown) == "preserve" && !Directory.Exists(Path.Combine(good, "nested")), "cleanup preserves unknown files and removes owned entries");
            }
            string echo = Path.Combine(root, "args.txt");
            string[] values = { "", "plain", "한글 space's", "C:\\space path\\", "embedded\"quote", "slash\\\"quote" };
            string command = string.Join(" ", new[] { "--echo", echo }.Concat(values).Select(Bootstrap.Quote));
            using (var child = Process.Start(new ProcessStartInfo(Assembly.GetExecutingAssembly().Location, command) { UseShellExecute = false, CreateNoWindow = true }))
            { child.WaitForExit(); Check(child.ExitCode == 0, "argument roundtrip child exits"); }
            Check(File.ReadAllLines(echo).Select(v => Encoding.UTF8.GetString(Convert.FromBase64String(v))).SequenceEqual(values), "Windows argument roundtrip preserves Unicode quotes empty and trailing slashes");
            using (var zip = Assembly.GetExecutingAssembly().GetManifestResourceStream("Release.zip"))
            {
                string release = Path.Combine(root, "release"); var files = Bootstrap.Extract(zip, release);
                Check(files.Count == 17 && File.Exists(Path.Combine(release, "VisibleCellsPaste.Setup.exe")), "complete release inventory extracted");
                Bootstrap.Cleanup(release, files); Check(!Directory.Exists(release), "complete owned extraction cleaned");
            }
            Console.WriteLine(checks + " checks passed"); return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error); return 1; }
    }
}
