using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("보이는 칸 붙여넣기 설치")]
[assembly: AssemblyVersion("0.1.1.1")]
[assembly: AssemblyFileVersion("0.1.1.1")]
namespace VisibleCellsPaste.Installation
{
    // Packaging only. The embedded, verified release's existing installer owns
    // registration, rollback and installation.xml; this launcher never edits them.
    internal static class Bootstrap
    {
        internal const long MaximumExpandedBytes = 16 * 1024 * 1024;
        internal static string[] ValidateArguments(string[] args)
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            for (int i = 0; i < args.Length; i++)
            {
                string flag = args[i];
                if (!seen.Add(flag)) throw new ArgumentException("중복된 설치 옵션입니다.");
                if (flag == "--silent" || flag == "--uninstall" || flag == "--diagnose") continue;
                if (flag != "--directory" && flag != "--report") throw new ArgumentException("알 수 없는 설치 옵션입니다: " + flag);
                if (++i >= args.Length || string.IsNullOrWhiteSpace(args[i]) || args[i].StartsWith("--", StringComparison.Ordinal))
                    throw new ArgumentException(flag + " 값이 필요합니다.");
            }
            if (seen.Contains("--uninstall") && seen.Contains("--diagnose")) throw new ArgumentException("제거와 진단은 따로 실행해 주세요.");
            return args;
        }
        internal static string Quote(string value)
        {
            var text = new StringBuilder("\""); int slashes = 0;
            foreach (char c in value)
            {
                if (c == '\\') { slashes++; continue; }
                text.Append('\\', c == '"' ? slashes * 2 + 1 : slashes);
                text.Append(c); slashes = 0;
            }
            return text.Append('\\', slashes * 2).Append('"').ToString();
        }
        internal static void NoReparse(string path)
        {
            for (var directory = new DirectoryInfo(path); directory != null; directory = directory.Parent)
                if (directory.Exists && (directory.Attributes & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("연결된 임시 폴더를 사용할 수 없습니다.");
        }
        internal static string EntryPath(string root, string name)
        {
            if (string.IsNullOrEmpty(name) || name.Contains(":") || name.Contains("\\") || name.StartsWith("/", StringComparison.Ordinal)
                || name.Split('/').Any(p => p.Length == 0 || p == "." || p == ".." || p.EndsWith(".") || p.EndsWith(" ")))
                throw new InvalidDataException("잘못된 패키지 경로입니다.");
            string path = Path.GetFullPath(Path.Combine(root, name.Replace('/', Path.DirectorySeparatorChar)));
            if (!path.StartsWith(Path.GetFullPath(root).TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("패키지 경로가 임시 폴더를 벗어났습니다.");
            return path;
        }
        internal static List<string> Extract(Stream stream, string root)
        {
            NoReparse(root);
            if (Directory.Exists(root) || File.Exists(root)) throw new IOException("새 임시 폴더가 필요합니다.");
            using (var archive = new ZipArchive(stream, ZipArchiveMode.Read, true))
            {
                if (archive.Entries.Count == 0 || archive.Entries.Count > 64) throw new InvalidDataException("잘못된 패키지 파일 수입니다.");
                var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase); long total = 0;
                foreach (var entry in archive.Entries)
                {
                    if (!paths.Add(EntryPath(root, entry.FullName))) throw new InvalidDataException("중복된 패키지 경로입니다.");
                    if (entry.Length < 0 || entry.Length > MaximumExpandedBytes - total) throw new InvalidDataException("패키지 크기 제한을 초과했습니다.");
                    total += entry.Length;
                }
                Directory.CreateDirectory(root);
                var written = new List<string>();
                try
                {
                    foreach (var entry in archive.Entries)
                    {
                        string path = EntryPath(root, entry.FullName);
                        NoReparse(Path.GetDirectoryName(path)); Directory.CreateDirectory(Path.GetDirectoryName(path));
                        using (var input = entry.Open())
                        using (var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                        {
                            written.Add(path); byte[] buffer = new byte[8192]; long count = 0; int size;
                            while ((size = input.Read(buffer, 0, buffer.Length)) != 0)
                            {
                                count += size; if (count > entry.Length) throw new InvalidDataException("압축 해제 크기가 일치하지 않습니다.");
                                output.Write(buffer, 0, size);
                            }
                            if (count != entry.Length) throw new InvalidDataException("패키지가 잘렸습니다.");
                        }
                    }
                    return written;
                }
                catch { Cleanup(root, written); throw; }
            }
        }
        internal static void Cleanup(string root, IEnumerable<string> files)
        {
            NoReparse(root);
            var directories = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { root };
            foreach (string path in files)
            {
                if (!path.StartsWith(root.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase)) throw new IOException("임시 정리 경계 오류입니다.");
                NoReparse(Path.GetDirectoryName(path));
                if (File.Exists(path))
                {
                    if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0) throw new IOException("변경된 임시 링크를 보존했습니다.");
                    File.Delete(path);
                }
                for (string directory = Path.GetDirectoryName(path); directory.Length > root.Length; directory = Path.GetDirectoryName(directory)) directories.Add(directory);
            }
            foreach (string directory in directories.OrderByDescending(p => p.Length))
                if (Directory.Exists(directory) && !Directory.EnumerateFileSystemEntries(directory).Any()) Directory.Delete(directory);
        }
        [STAThread]
        public static int Main(string[] args)
        {
            bool silent = args.Contains("--silent"); string temp = null; List<string> files = null;
            try
            {
                ValidateArguments(args);
                if (!silent && !args.Contains("--diagnose"))
                {
                    Application.EnableVisualStyles();
                    string action = args.Contains("--uninstall") ? "제거" : "설치 또는 업데이트";
                    if (MessageBox.Show("보이는 칸 붙여넣기를 현재 Windows 계정에 " + action + "합니다.\n\nExcel 문서를 저장하고 모든 Excel을 닫아 주세요. 설치 후 평소처럼 Excel을 열면 메뉴가 준비됩니다.\n\n이 파일은 서명되지 않은 평가 설치 파일입니다. 계속할까요?", "보이는 칸 붙여넣기", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return 1602;
                }
                temp = Path.Combine(Path.GetTempPath(), "VisibleCellsPaste-Setup-" + Guid.NewGuid().ToString("N"));
                using (var zip = Assembly.GetExecutingAssembly().GetManifestResourceStream("Release.zip"))
                using (var expected = new StreamReader(Assembly.GetExecutingAssembly().GetManifestResourceStream("Release.sha256")))
                using (var sha = SHA256.Create())
                {
                    string actual = BitConverter.ToString(sha.ComputeHash(zip)).Replace("-", "").ToLowerInvariant();
                    if (actual != expected.ReadToEnd().Trim()) throw new InvalidDataException("내장 패키지 해시가 일치하지 않습니다.");
                    zip.Position = 0; files = Extract(zip, temp);
                }
                var start = new ProcessStartInfo(Path.Combine(temp, "VisibleCellsPaste.Setup.exe"), string.Join(" ", args.Select(Quote)))
                { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden, WorkingDirectory = temp };
                using (var child = Process.Start(start)) { child.WaitForExit(); return child.ExitCode; }
            }
            catch (Exception error)
            {
                string message = "[VCP-BOOTSTRAP] " + error.Message;
                int report = Array.IndexOf(args, "--report");
                if (report >= 0 && report + 1 < args.Length) try { File.WriteAllText(args[report + 1], "exit=1\n" + message, new UTF8Encoding(false)); } catch { }
                if (!silent) MessageBox.Show(message, "보이는 칸 붙여넣기", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
            finally
            {
                if (files != null) try { Cleanup(temp, files); } catch { /* Preserve unexpected/locked temporary entries; never scan outside the owned inventory. */ }
            }
        }
    }
}
