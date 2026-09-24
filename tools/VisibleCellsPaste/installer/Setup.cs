using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System.Xml;
using System.Xml.Linq;
using Microsoft.Win32;

namespace VisibleCellsPaste.Installation
{
    // User-scoped registration only. Never edits Office security policy or closes Excel.
    internal static class Setup
    {
        internal const string Identity = "VisibleCellsPaste.856B2219-6225-42ED-8FF1-2D06E5913AC8";
        internal const string ProgId = "Workspace.VisibleCellsPaste";
        internal const string Clsid = "{856B2219-6225-42ED-8FF1-2D06E5913AC8}";
        internal const string AddinClass = "VisibleCellsPaste.AddIn";
        internal const string AssemblyIdentity = "VisibleCellsPaste.AddIn, Version=0.1.0.0, Culture=neutral, PublicKeyToken=null";
        internal const string AssemblyName = "VisibleCellsPaste.AddIn.dll";
        internal const string ManifestName = "installation.xml";
        private static bool silent;
        private static string report;
        private static readonly List<string> notes = new List<string>();
        [STAThread]
        public static int Main(string[] args)
        {
            silent = args.Contains("--silent");
            report = Argument(args, "--report");
            string target = Argument(args, "--directory") ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VisibleCellsPaste");
            try
            {
                target = ValidateRoot(target);
                RefuseExcel(); // Before even relocating the installed uninstaller to a temporary file.
                if (args.Contains("--uninstall") && SamePath(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location), Path.Combine(target, "launcher")) && !args.Contains("--relocated"))
                    return RelocateUninstaller(target, args);
                string waitPid = Argument(args, "--wait-pid");
                if (waitPid != null) { try { Process.GetProcessById(int.Parse(waitPid, CultureInfo.InvariantCulture)).WaitForExit(15000); } catch (ArgumentException) { } }
                bool created;
                using (Mutex mutex = new Mutex(true, @"Local\VisibleCellsPaste.Setup.856B2219", out created))
                {
                    if (!created) throw new InvalidOperationException("다른 설치 또는 제거가 실행 중입니다. 끝난 후 다시 실행해 주세요.");
                    try
                    {
                        RefuseExcel();
                        if (args.Contains("--uninstall")) Uninstall(target);
                        else if (args.Contains("--diagnose")) Diagnose(target);
                        else Install(target);
                    }
                    finally { mutex.ReleaseMutex(); }
                }
                Finish(0, string.Join(Environment.NewLine, notes.ToArray()));
                return 0;
            }
            catch (Exception e) { Finish(1, "[VCP-INSTALL] " + e.Message + Environment.NewLine + "Excel을 강제 종료하거나 보안 설정을 낮추지 않았습니다."); return 1; }
        }
        private static string Argument(string[] args, string key)
        {
            int i = Array.IndexOf(args, key);
            if (i < 0) return null;
            if (i + 1 >= args.Length || args[i + 1].StartsWith("--", StringComparison.Ordinal)) throw new ArgumentException(key + " 값이 필요합니다.");
            return args[i + 1];
        }
        private static void Finish(int code, string message)
        {
            if (report != null) File.WriteAllText(report, "exit=" + code + Environment.NewLine + message, new UTF8Encoding(false));
            if (!silent) MessageBox.Show(message, "보이는 칸 붙여넣기", MessageBoxButtons.OK, code == 0 ? MessageBoxIcon.Information : MessageBoxIcon.Error);
        }
        internal static string ValidateRoot(string input)
        {
            string full = Path.GetFullPath(input).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            if (full == Path.GetPathRoot(full).TrimEnd(Path.DirectorySeparatorChar) || full.Length < 8) throw new InvalidOperationException("드라이브 루트에는 설치할 수 없습니다.");
            for (DirectoryInfo d = new DirectoryInfo(full); d != null; d = d.Parent)
                if (d.Exists && (d.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidOperationException("재분석 지점 또는 연결된 폴더에는 설치할 수 없습니다.");
            return full;
        }
        // .NET Framework COM registration uses Assembly.CodeBase/RegAsm's unescaped
        // file URL. Uri.AbsoluteUri/EscapedCodeBase percent-encode valid filename
        // characters that Fusion may treat literally (Korean, spaces, %, #).
        internal static string ClrCodeBase(string file)
        {
            string full = Path.GetFullPath(file).Replace('\\', '/');
            return full.StartsWith("//", StringComparison.Ordinal) ? "file:" + full : "file:///" + full;
        }
        internal static bool SamePath(string left, string right) { return string.Equals(Path.GetFullPath(left).TrimEnd('\\'), Path.GetFullPath(right).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
        internal static string SafePath(string basePath, string relative)
        {
            if (Path.IsPathRooted(relative)) throw new InvalidDataException("매니페스트의 절대 경로를 거절했습니다.");
            string full = Path.GetFullPath(Path.Combine(basePath, relative));
            if (!full.StartsWith(basePath.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("설치 경계 밖의 경로를 거절했습니다.");
            for (DirectoryInfo dir = new DirectoryInfo(Path.GetDirectoryName(full)); dir != null && !SamePath(dir.FullName, basePath); dir = dir.Parent)
                if (dir.Exists && (dir.Attributes & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("설치 하위 경로의 연결된 폴더를 거절했습니다.");
            if (File.Exists(full) && (File.GetAttributes(full) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("연결된 파일을 거절했습니다.");
            return full;
        }
        internal static string Hash(string file)
        {
            using (SHA256 hash = SHA256.Create()) using (FileStream stream = File.OpenRead(file))
                return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
        }
        private static void RefuseExcel()
        {
            Process[] excel = Process.GetProcessesByName("EXCEL");
            try { if (excel.Length != 0) throw new InvalidOperationException("Excel이 실행 중입니다. 작업을 저장하고 모든 Excel 창을 닫은 뒤 설치/제거를 다시 실행해 주세요. 변경하지 않았습니다."); }
            finally { foreach (Process p in excel) p.Dispose(); }
        }
        private static string ExcelArchitecture()
        {
            foreach (RegistryView view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
                foreach (RegistryHive hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
                    using (RegistryKey baseKey = RegistryKey.OpenBaseKey(hive, view))
                    using (RegistryKey key = baseKey.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\App Paths\excel.exe"))
                    {
                        string executable = key == null ? null : key.GetValue(null) as string;
                        if (string.IsNullOrEmpty(executable)) continue;
                        executable = Environment.ExpandEnvironmentVariables(executable.Trim('"'));
                        if (!File.Exists(executable)) continue;
                        using (BinaryReader reader = new BinaryReader(File.Open(executable, FileMode.Open, FileAccess.Read, FileShare.ReadWrite)))
                        {
                            if (reader.ReadUInt16() != 0x5a4d) continue;
                            reader.BaseStream.Position = 0x3c; int offset = reader.ReadInt32();
                            if (offset < 0 || offset > reader.BaseStream.Length - 6) continue;
                            reader.BaseStream.Position = offset; if (reader.ReadUInt32() != 0x4550) continue;
                            ushort machine = reader.ReadUInt16();
                            if (machine == 0x8664) return "x64";
                            if (machine == 0x14c) return "x86";
                        }
                    }
            throw new InvalidOperationException("지원하는 Windows 데스크톱 Excel 설치와 비트 수를 확인할 수 없습니다. Excel 설치/조직 승인 상태를 확인해 주세요.");
        }
        private static void VerifyPayload(string file, string arch)
        {
            using (Stream resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("PayloadHashes.txt"))
            {
                if (resource == null) throw new InvalidDataException("패키지 무결성 목록이 없습니다. 완성 배포 패키지를 사용해 주세요.");
                using (StreamReader reader = new StreamReader(resource))
                {
                    string[] lines = reader.ReadToEnd().Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    string prefix = arch + "/" + AssemblyName + " ";
                    string record = lines.SingleOrDefault(x => x.StartsWith(prefix, StringComparison.Ordinal));
                    if (record == null || record.Substring(prefix.Length) != Hash(file)) throw new InvalidDataException("추가 기능 파일 해시가 일치하지 않습니다. 설치하지 않았습니다.");
                }
            }
        }
        private static void RuntimeCheck()
        {
            using (RegistryKey key = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry32).OpenSubKey(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"))
                if (key == null || Convert.ToInt32(key.GetValue("Release", 0), CultureInfo.InvariantCulture) < 528040)
                    throw new InvalidOperationException(".NET Framework 4.8 이상이 필요합니다. 회사에서 승인한 Windows 구성 절차로 준비해 주세요.");
        }
        private static XDocument LoadManifest(string target)
        {
            string file = Path.Combine(target, ManifestName);
            if (!File.Exists(file)) return null;
            XmlReaderSettings settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 1024 * 1024 };
            XDocument doc; using (XmlReader reader = XmlReader.Create(file, settings)) doc = XDocument.Load(reader);
            if (doc.Root == null || (string)doc.Root.Attribute("identity") != Identity || (string)doc.Root.Attribute("schema") != "1" || !SamePath((string)doc.Root.Attribute("root"), target))
                throw new InvalidDataException("설치 매니페스트 소유권/버전을 확인할 수 없습니다. 기존 파일을 변경하지 않았습니다.");
            foreach (XElement f in doc.Root.Element("files").Elements("file")) SafePath(target, (string)f.Attribute("path"));
            string[] allowed = Registration(target, Path.Combine(target, AssemblyName), "0").Select(v => v.Key + "|" + v.Name).ToArray();
            foreach (XElement r in doc.Root.Element("registry").Elements("value"))
            {
                RegValue value = ParseReg(r);
                if (!allowed.Contains(value.Key + "|" + value.Name, StringComparer.Ordinal) || (value.Kind != RegistryValueKind.String && value.Kind != RegistryValueKind.DWord)) throw new InvalidDataException("매니페스트에 자체 등록 범위 밖의 항목이 있습니다.");
            }
            if ((string)doc.Root.Attribute("architecture") != "x86" && (string)doc.Root.Attribute("architecture") != "x64") throw new InvalidDataException("알 수 없는 설치 아키텍처입니다.");
            return doc;
        }
        private static RegistryView View(string arch) { return arch == "x64" ? RegistryView.Registry64 : RegistryView.Registry32; }
        private sealed class RegValue
        {
            internal string Key, Name, Value; internal RegistryValueKind Kind; internal bool PreserveOnly;
            internal XElement Xml() { return new XElement("value", new XAttribute("key", Key), new XAttribute("name", Name), new XAttribute("kind", Kind), new XAttribute("data", Value)); }
        }
        private static RegValue Reg(string key, string name, string value, RegistryValueKind kind = RegistryValueKind.String) { return new RegValue { Key = key, Name = name, Value = value, Kind = kind }; }
        private static List<RegValue> Registration(string target, string dll, string version)
        {
            var list = new List<RegValue>();
            string cls = @"Software\Classes\CLSID\" + Clsid;
            string prog = @"Software\Classes\" + ProgId;
            string addin = @"Software\Microsoft\Office\Excel\Addins\" + ProgId;
            list.Add(Reg(cls, "", AddinClass)); list.Add(Reg(cls + @"\ProgId", "", ProgId));
            list.Add(Reg(prog, "", AddinClass)); list.Add(Reg(prog + @"\CLSID", "", Clsid));
            foreach (string sub in new[] { cls + @"\InprocServer32", cls + @"\InprocServer32\0.1.0.0" })
            {
                list.Add(Reg(sub, "Class", AddinClass)); list.Add(Reg(sub, "Assembly", AssemblyIdentity)); list.Add(Reg(sub, "RuntimeVersion", "v4.0.30319")); list.Add(Reg(sub, "CodeBase", ClrCodeBase(dll)));
            }
            list.Add(Reg(cls + @"\InprocServer32", "", "mscoree.dll")); list.Add(Reg(cls + @"\InprocServer32", "ThreadingModel", "Both"));
            list.Add(Reg(addin, "FriendlyName", "보이는 칸 붙여넣기")); list.Add(Reg(addin, "Description", "선택 범위 안의 보이는 칸에 복사한 값만 순서대로 입력합니다.")); list.Add(Reg(addin, "LoadBehavior", "3", RegistryValueKind.DWord));
            string uninstall = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\" + ProgId;
            list.Add(Reg(uninstall, "DisplayName", "보이는 칸 붙여넣기")); list.Add(Reg(uninstall, "DisplayVersion", version)); list.Add(Reg(uninstall, "Publisher", "Workspace")); list.Add(Reg(uninstall, "InstallLocation", target));
            list.Add(Reg(uninstall, "UninstallString", Quote(Path.Combine(target, @"launcher\VisibleCellsPaste.Setup.exe")) + " --uninstall --directory " + Quote(target)));
            list.Add(Reg(uninstall, "NoModify", "1", RegistryValueKind.DWord)); list.Add(Reg(uninstall, "NoRepair", "1", RegistryValueKind.DWord));
            list.Add(Reg(@"Software\VisibleCellsPaste", "Owner", Identity));
            return list;
        }
        private static RegValue ParseReg(XElement x) { return Reg((string)x.Attribute("key"), (string)x.Attribute("name"), (string)x.Attribute("data"), (RegistryValueKind)Enum.Parse(typeof(RegistryValueKind), (string)x.Attribute("kind"))); }
        private static string Current(RegistryKey hive, RegValue value)
        {
            using (RegistryKey key = hive.OpenSubKey(value.Key))
            {
                if (key == null || !key.GetValueNames().Contains(value.Name, StringComparer.OrdinalIgnoreCase)) return null;
                if (key.GetValueKind(value.Name) != value.Kind) return "<different-kind>";
                return Convert.ToString(key.GetValue(value.Name), CultureInfo.InvariantCulture);
            }
        }
        private static void Set(RegistryKey hive, RegValue value)
        {
            using (RegistryKey key = hive.CreateSubKey(value.Key)) key.SetValue(value.Name, value.Kind == RegistryValueKind.DWord ? (object)int.Parse(value.Value, CultureInfo.InvariantCulture) : value.Value, value.Kind);
        }
        private static void Remove(RegistryKey hive, RegValue value)
        {
            using (RegistryKey key = hive.OpenSubKey(value.Key, true)) if (key != null) key.DeleteValue(value.Name, false);
        }
        private static void Install(string target)
        {
            RuntimeCheck(); string arch = ExcelArchitecture();
            string package = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            string sourceDll = Path.Combine(package, arch, AssemblyName);
            string versionFile = Path.Combine(package, "version.txt");
            if (!File.Exists(sourceDll) || !File.Exists(versionFile)) throw new FileNotFoundException("배포 ZIP 전체를 한 폴더에 압축 해제한 뒤 Install.cmd를 실행해 주세요.");
            string version = File.ReadAllText(versionFile).Trim();
            if (version.Length > 60 || version.Any(c => !(char.IsLetterOrDigit(c) || c == '.' || c == '-'))) throw new InvalidDataException("잘못된 배포 버전입니다.");
            VerifyPayload(sourceDll, arch);
            XDocument previous = LoadManifest(target);
            if (Directory.Exists(target) && previous == null && Directory.EnumerateFileSystemEntries(target).Any()) throw new InvalidOperationException("기존 폴더 소유권을 확인할 수 없어 설치를 중단했습니다.");
            if (previous != null && (string)previous.Root.Attribute("architecture") != arch) throw new InvalidOperationException("기존 설치와 Excel 비트 수가 다릅니다. 기존 제품을 먼저 제거해 주세요.");
            string payloadDir = Path.Combine("versions", version + "-" + Hash(sourceDll).Substring(0, 12), arch);
            var sources = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            sources.Add(Path.Combine(payloadDir, AssemblyName), sourceDll);
            sources.Add(@"launcher\VisibleCellsPaste.Setup.exe", Assembly.GetExecutingAssembly().Location);
            foreach (string name in new[] { "README.md", "CHANGELOG.md" }) if (File.Exists(Path.Combine(package, name))) sources.Add(Path.Combine(payloadDir, name), Path.Combine(package, name));
            List<RegValue> registrations = Registration(target, SafePath(target, Path.Combine(payloadDir, AssemblyName)), version);
            var oldRegs = previous == null ? new List<RegValue>() : previous.Root.Element("registry").Elements("value").Select(ParseReg).ToList();
            using (RegistryKey hive = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, View(arch)))
            {
                foreach (RegValue entry in registrations)
                {
                    string current = Current(hive, entry); RegValue old = oldRegs.FirstOrDefault(v => v.Key == entry.Key && v.Name == entry.Name);
                    if (current == null) continue;
                    if (old == null) throw new InvalidOperationException("소유권을 확인할 수 없는 기존 제품 등록이 있습니다. 등록을 변경하지 않았습니다.");
                    if (entry.Name == "LoadBehavior") { entry.PreserveOnly = current != old.Value; entry.Value = current; continue; }
                    if (current != old.Value) throw new InvalidOperationException("외부에서 변경된 등록이 있습니다. 해당 등록을 보존하기 위해 설치를 중단했습니다: " + entry.Name);
                }
                foreach (KeyValuePair<string,string> item in sources)
                {
                    string dest = SafePath(target, item.Key);
                    XElement old = previous == null ? null : previous.Root.Element("files").Elements("file").FirstOrDefault(x => (string)x.Attribute("path") == item.Key);
                    if (File.Exists(dest) && (old == null || Hash(dest) != (string)old.Attribute("sha256"))) throw new InvalidOperationException("소유권 불명 또는 외부 변경 파일을 보존하기 위해 설치를 중단했습니다: " + item.Key);
                }
                RefuseExcel();
                Directory.CreateDirectory(target);
                string transaction = Path.Combine(target, ".setup-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(transaction);
                var changedFiles = new List<string>(); var backups = new Dictionary<string,string>(); var changedRegs = new List<RegValue>(); var oldValues = new Dictionary<RegValue,string>();
                byte[] oldManifest = File.Exists(Path.Combine(target, ManifestName)) ? File.ReadAllBytes(Path.Combine(target, ManifestName)) : null;
                try
                {
                    foreach (KeyValuePair<string,string> item in sources)
                    {
                        string dest = SafePath(target, item.Key); Directory.CreateDirectory(Path.GetDirectoryName(dest));
                        if (File.Exists(dest)) { string backup = Path.Combine(transaction, backups.Count.ToString(CultureInfo.InvariantCulture)); File.Copy(dest, backup); backups.Add(dest, backup); }
                        if (!SamePath(dest, item.Value)) { changedFiles.Add(dest); File.Copy(item.Value, dest, true); }
                    }
                    RefuseExcel();
                    foreach (RegValue entry in registrations) { if (entry.PreserveOnly) continue; oldValues.Add(entry, Current(hive, entry)); Set(hive, entry); changedRegs.Add(entry); }
                    var files = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
                    if (previous != null) foreach (XElement f in previous.Root.Element("files").Elements("file")) files[(string)f.Attribute("path")] = (string)f.Attribute("sha256");
                    foreach (var item in sources) files[item.Key] = Hash(SafePath(target, item.Key));
                    var manifest = new XDocument(new XElement("installation", new XAttribute("identity", Identity), new XAttribute("schema", "1"), new XAttribute("root", target), new XAttribute("architecture", arch), new XAttribute("version", version), new XAttribute("utc", DateTime.UtcNow.ToString("o")), new XElement("files", files.Select(p => new XElement("file", new XAttribute("path", p.Key), new XAttribute("sha256", p.Value)))), new XElement("registry", registrations.Select(x => x.PreserveOnly ? oldRegs.First(v => v.Key == x.Key && v.Name == x.Name).Xml() : x.Xml()))));
                    string pending = Path.Combine(transaction, "manifest.xml"); manifest.Save(pending);
                    string manifestPath = Path.Combine(target, ManifestName);
                    if (File.Exists(manifestPath)) File.Replace(pending, manifestPath, null); else File.Move(pending, manifestPath);
                    foreach (RegValue entry in registrations) if (Current(hive, entry) != entry.Value) throw new IOException("등록 사후 검증 실패: " + entry.Name);
                    notes.Add("제품 파일과 현재 사용자 자동 로드 등록을 설치했습니다 (" + arch + ").");
                    notes.Add("Excel을 평소처럼 실행해 셀 우클릭 메뉴를 확인해 주세요. 실제 Excel 자동 로드는 이 설치 프로그램에서 아직 확인하지 않았습니다.");
                    notes.Add("설치 파일에는 코드 서명이 없습니다. 조직의 추가 기능 승인 정책은 그대로 적용됩니다.");
                    if (registrations.Any(x => x.Name == "LoadBehavior" && x.Value != "3")) notes.Add("기존 LoadBehavior 설정을 보존했습니다. 자동 로드가 비활성화된 경우 조직 담당자에게 승인 상태를 확인해 주세요.");
                }
                catch
                {
                    foreach (RegValue entry in changedRegs.AsEnumerable().Reverse()) { string value = oldValues[entry]; if (value == null) Remove(hive, entry); else { var restore = Reg(entry.Key, entry.Name, value, entry.Kind); Set(hive, restore); } }
                    foreach (string dest in changedFiles.AsEnumerable().Reverse()) { if (backups.ContainsKey(dest)) File.Copy(backups[dest], dest, true); else if (File.Exists(dest)) File.Delete(dest); }
                    string mp = Path.Combine(target, ManifestName); if (oldManifest != null) File.WriteAllBytes(mp, oldManifest); else if (File.Exists(mp)) File.Delete(mp);
                    throw;
                }
                finally
                {
                    foreach (string file in backups.Values.Concat(new[] { Path.Combine(transaction, "manifest.xml") })) if (File.Exists(file)) File.Delete(file);
                    if (!Directory.EnumerateFileSystemEntries(transaction).Any()) Directory.Delete(transaction);
                }
            }
        }
        private static void Uninstall(string target)
        {
            XDocument manifest = LoadManifest(target);
            if (manifest == null) { notes.Add("확인된 보이는 칸 붙여넣기 설치가 없습니다. 변경하지 않았습니다."); return; }
            string arch = (string)manifest.Root.Attribute("architecture");
            var regs = manifest.Root.Element("registry").Elements("value").Select(ParseReg).ToList();
            var dirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            RefuseExcel();
            using (RegistryKey hive = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, View(arch)))
            {
                foreach (RegValue entry in regs)
                {
                    string current = Current(hive, entry);
                    if (current == entry.Value) Remove(hive, entry);
                    else if (current != null) notes.Add("외부 변경 등록 보존: " + entry.Key + " / " + entry.Name);
                }
                foreach (string keyName in regs.Select(v => v.Key).Distinct().OrderByDescending(v => v.Length))
                    using (RegistryKey key = hive.OpenSubKey(keyName))
                        if (key != null && key.SubKeyCount == 0 && key.ValueCount == 0) hive.DeleteSubKey(keyName, false);
            }
            foreach (XElement f in manifest.Root.Element("files").Elements("file"))
            {
                string file = SafePath(target, (string)f.Attribute("path"));
                if (File.Exists(file)) { if (Hash(file) == (string)f.Attribute("sha256")) File.Delete(file); else notes.Add("외부 변경 파일 보존: " + (string)f.Attribute("path")); }
                string dir = Path.GetDirectoryName(file); while (!SamePath(dir, target)) { dirs.Add(dir); dir = Path.GetDirectoryName(dir); }
            }
            File.Delete(Path.Combine(target, ManifestName));
            foreach (string dir in dirs.OrderByDescending(d => d.Length)) if (Directory.Exists(dir) && !Directory.EnumerateFileSystemEntries(dir).Any()) Directory.Delete(dir);
            if (Directory.Exists(target) && !Directory.EnumerateFileSystemEntries(target).Any()) Directory.Delete(target);
            notes.Add("확인된 자체 파일과 자체 등록을 제거했습니다. 알 수 없는 파일/변경된 항목은 보존했습니다.");
            notes.Add("Excel을 평소처럼 다시 시작해 메뉴가 사라졌는지 확인해 주세요.");
        }
        private static void Diagnose(string target)
        {
            RuntimeCheck(); notes.Add("Excel 비트 수: " + ExcelArchitecture());
            XDocument manifest = LoadManifest(target); notes.Add(manifest == null ? "설치 매니페스트 없음" : "설치 매니페스트 확인됨");
            notes.Add("파일/등록 진단은 실제 Excel 시작과 메뉴 검증을 대신하지 않습니다.");
        }
        private static string Quote(string value) { return "\"" + value.Replace("\"", "\\\"") + "\""; }
        private static int RelocateUninstaller(string target, string[] args)
        {
            string temp = Path.Combine(Path.GetTempPath(), "VisibleCellsPaste-Uninstall-" + Guid.NewGuid().ToString("N") + ".exe");
            File.Copy(Assembly.GetExecutingAssembly().Location, temp);
            var start = new ProcessStartInfo(temp, "--uninstall --relocated --wait-pid " + Process.GetCurrentProcess().Id + " --directory " + Quote(target) + (silent ? " --silent" : "") + (report == null ? "" : " --report " + Quote(report))) { UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden };
            Process.Start(start);
            return 0;
        }
    }
}
