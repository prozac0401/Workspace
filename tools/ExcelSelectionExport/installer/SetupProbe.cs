using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

// Compiled, read-only deployment diagnostics. Never attaches to an Excel process,
// changes Office policy/security, enables an add-in, or writes registration.
internal static class SetupProbe
{
    internal const string ProgId = "Workspace.ExcelSelectionExport";
    const string Clsid = "{2A2A4B8C-6D6C-4E28-AB96-E34B9B4319A1}";
    static readonly Dictionary<string, string> Report = new Dictionary<string, string>();
    static readonly RegistryView[] Views = Environment.Is64BitOperatingSystem
        ? new[] { RegistryView.Registry64, RegistryView.Registry32 }
        : new[] { RegistryView.Registry32 };

    [STAThread]
    static int Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        int code = 99;
        string reportPath = null;
        try
        {
            if (args.Length == 0) throw new ArgumentException("진단 명령이 없습니다.");
            string mode = args[0];
            reportPath = mode == "preflight" ? (args.Length > 2 ? args[2] : null) : (args.Length > 1 ? args[1] : null);
            Report["Mode"] = mode;
            Report["Utc"] = DateTime.UtcNow.ToString("o", CultureInfo.InvariantCulture);
            Report["RunningExcelCount"] = RunningExcelCount().ToString(CultureInfo.InvariantCulture);
            if (mode == "uninstall")
                code = RunningExcelCount() > 0 ? Fail(20, "Excel에서 작업을 저장하고 모든 Excel 창을 닫은 뒤 제거해 주세요.") : 0;
            else if (mode == "preflight")
            {
                if (args.Length < 3 || (args[1] != "x86" && args[1] != "x64")) throw new ArgumentException("올바른 설치 비트수가 필요합니다.");
                code = Preflight(args[1], args.Length > 3 && args[3] == "upgrade");
            }
            else if (mode == "diagnose")
            {
                code = Preflight(Environment.Is64BitProcess ? "x64" : "x86", false);
                if (code == 0) code = DiagnoseActivation();
            }
            else throw new ArgumentException("알 수 없는 진단 명령입니다.");
        }
        catch (Exception ex) { code = Fail(99, "설치 상태를 확인하지 못했습니다: " + ex.GetType().Name + " (" + ex.HResult.ToString("X8") + ")"); }
        Report["Code"] = code.ToString(CultureInfo.InvariantCulture);
        if (code == 0 && !Report.ContainsKey("Message")) Report["Message"] = "사전 검사를 마쳤습니다. 실제 메뉴 준비 여부는 Excel을 새로 시작하여 확인하세요.";
        var lines = new List<string> { "[Probe]" };
        foreach (var item in Report) lines.Add(item.Key + "=" + item.Value.Replace("\r", " ").Replace("\n", " "));
        string output = String.Join(Environment.NewLine, lines.ToArray());
        if (reportPath != null)
        {
            try { File.WriteAllText(reportPath, output, Encoding.Unicode); }
            catch { return 98; }
        }
        Console.WriteLine(output);
        return code;
    }

    static int Fail(int code, string message) { Report["Message"] = message; return code; }
    static int RunningExcelCount()
    {
        var processes = Process.GetProcessesByName("EXCEL");
        int count = processes.Length;
        foreach (var process in processes) process.Dispose();
        return count;
    }

    static int Preflight(string expectedArch, bool upgrading)
    {
        Report["ExpectedArchitecture"] = expectedArch;
        if (!HasFramework48()) return Fail(11, ".NET Framework 4.8 이상이 필요합니다. 회사에서 승인한 Windows 구성 절차로 준비해 주세요.");
        var paths = ExcelPaths();
        if (paths.Count == 0) return Fail(10, "설치형 Excel을 찾지 못했습니다. Excel 웹이나 Mac은 지원하지 않습니다.");
        var candidates = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var excelMajors = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        foreach (string path in paths)
        {
            string architecture = ReadPeArchitecture(path);
            if (architecture != "x86" && architecture != "x64") return Fail(12, "Excel 실행 파일의 비트수를 확인하지 못했습니다.");
            candidates[path] = architecture;
            int major = FileVersionInfo.GetVersionInfo(path).FileMajorPart;
            try { OfficeRegistryVersion(major); }
            catch (InvalidOperationException ex) { return Fail(14, ex.Message); }
            excelMajors[path] = major;
        }
        var archs = new HashSet<string>(candidates.Values, StringComparer.OrdinalIgnoreCase);
        if (archs.Count != 1) return Fail(12, "서로 다른 비트수의 Excel 등록이 있습니다. IT 담당자와 설치 상태를 확인해 주세요.");
        if (new HashSet<int>(excelMajors.Values).Count != 1)
            return Fail(14, "서로 다른 주 버전의 Excel 등록이 있습니다. 적용할 Office 정책 버전을 확정하지 못해 설치를 중단했습니다.");
        string excelPath = paths[0];
        int excelMajor = excelMajors[excelPath];
        string actualArch = candidates[excelPath];
        Report["ExcelArchitecture"] = actualArch;
        Report["ExcelVersion"] = FileVersionInfo.GetVersionInfo(excelPath).FileVersion;
        Report["ExcelMajor"] = excelMajor.ToString(CultureInfo.InvariantCulture);
        Report["OfficePolicyVersion"] = OfficeRegistryVersion(excelMajor);
        if (actualArch != expectedArch) return Fail(13, "Excel은 " + actualArch + "입니다. 해당 비트수의 선택범위 내보내기 설치 파일을 실행해 주세요.");
        if (upgrading && RunningExcelCount() > 0) return Fail(20, "Excel에서 작업을 저장하고 모든 Excel 창을 닫은 뒤 업데이트해 주세요.");
        if (RunningExcelCount() > 0) Report["RestartExcel"] = "1";
        else Report["RestartExcel"] = "0";
        int policy = CheckPolicies(excelMajor);
        if (policy != 0) return policy;
        if (ProductInDisabledItems(excelMajor)) return Fail(25, "Office가 이 추가 기능을 사용 안 함 목록에 기록했습니다. 설치가 차단을 해제하지 않습니다. IT 담당자와 로드 실패 원인을 확인해 주세요.");
        RegistryView view = expectedArch == "x64" ? RegistryView.Registry64 : RegistryView.Registry32;
        using (RegistryKey currentUser = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, view))
        using (RegistryKey addin = currentUser.OpenSubKey(@"Software\Microsoft\Office\Excel\Addins\" + ProgId))
        {
            object behavior = addin == null ? null : addin.GetValue("LoadBehavior");
            if (behavior != null)
            {
                Report["ExistingLoadBehavior"] = Convert.ToString(behavior, CultureInfo.InvariantCulture);
                if (Convert.ToInt32(behavior, CultureInfo.InvariantCulture) != 3)
                    return Fail(24, "추가 기능이 사용자 또는 Office에 의해 비활성화되었거나 시작 시 로드되지 않는 상태입니다. 설치가 이를 강제로 바꾸지 않습니다. IT 담당자와 원인을 확인해 주세요.");
            }
        }
        return 0;
    }

    static bool HasFramework48()
    {
        foreach (RegistryView view in Views)
        using (var machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
        using (var framework = machine.OpenSubKey(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"))
        {
            object release = framework == null ? null : framework.GetValue("Release");
            if (release != null && Convert.ToInt32(release, CultureInfo.InvariantCulture) >= 528040) return true;
        }
        return false;
    }

    static List<string> ExcelPaths()
    {
        var paths = new List<string>();
        foreach (RegistryHive hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        foreach (RegistryView view in Views)
        using (RegistryKey root = RegistryKey.OpenBaseKey(hive, view))
        {
            using (RegistryKey app = root.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\excel.exe"))
                AddPath(paths, app == null ? null : app.GetValue("") as string);
            using (RegistryKey excel = root.OpenSubKey(@"SOFTWARE\Microsoft\Office\16.0\Excel\InstallRoot"))
            {
                string path = excel == null ? null : excel.GetValue("Path") as string;
                if (!String.IsNullOrEmpty(path)) AddPath(paths, Path.Combine(path, "EXCEL.EXE"));
            }
        }
        return paths;
    }
    static void AddPath(List<string> paths, string path)
    {
        if (String.IsNullOrWhiteSpace(path)) return;
        path = Environment.ExpandEnvironmentVariables(path.Trim().Trim('"'));
        if (File.Exists(path) && !paths.Exists(delegate(string p) { return String.Equals(p, path, StringComparison.OrdinalIgnoreCase); })) paths.Add(path);
    }
    internal static string ReadPeArchitecture(string path)
    {
        using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
        using (var reader = new BinaryReader(stream))
        {
            if (stream.Length < 64 || reader.ReadUInt16() != 0x5A4D) return "unknown";
            stream.Position = 0x3C;
            int peOffset = reader.ReadInt32();
            if (peOffset < 64 || peOffset > stream.Length - 6) return "unknown";
            stream.Position = peOffset;
            if (reader.ReadUInt32() != 0x00004550) return "unknown";
            ushort machine = reader.ReadUInt16();
            return machine == 0x8664 ? "x64" : machine == 0x14c ? "x86" : "unknown";
        }
    }
    internal static string OfficeRegistryVersion(int excelMajor)
    {
        if (excelMajor == 15) return "15.0";
        if (excelMajor == 16) return "16.0";
        throw new InvalidOperationException("발견한 Excel 주 버전 " + excelMajor.ToString(CultureInfo.InvariantCulture) +
            "의 지원 여부와 Office 정책 경로가 확인되지 않았습니다. 설치를 중단했습니다.");
    }
    internal static string[] OfficePolicyRoots(int excelMajor)
    {
        string version = OfficeRegistryVersion(excelMajor);
        return new[] { @"Software\Policies\Microsoft\Office\" + version + @"\Excel\",
            @"Software\Microsoft\Office\" + version + @"\Excel\" };
    }
    internal static string DisabledItemsPath(int excelMajor)
    {
        return @"Software\Microsoft\Office\" + OfficeRegistryVersion(excelMajor) + @"\Excel\Resiliency\DisabledItems";
    }
    static bool ProductInDisabledItems(int excelMajor)
    {
        foreach (RegistryView view in Views)
        using (RegistryKey root = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, view))
        using (RegistryKey disabled = root.OpenSubKey(DisabledItemsPath(excelMajor)))
        {
            if (disabled == null) continue;
            foreach (string name in disabled.GetValueNames())
            {
                byte[] bytes = disabled.GetValue(name) as byte[];
                if (bytes == null) continue;
                string unicode = Encoding.Unicode.GetString(bytes);
                string ascii = Encoding.ASCII.GetString(bytes);
                if (ContainsProduct(unicode) || ContainsProduct(ascii)) return true;
            }
        }
        return false;
    }
    static bool ContainsProduct(string value)
    {
        return value.IndexOf("ExcelSelectionExport.AddIn", StringComparison.OrdinalIgnoreCase) >= 0 ||
            value.IndexOf(ProgId, StringComparison.OrdinalIgnoreCase) >= 0;
    }
    static int CheckPolicies(int excelMajor)
    {
        foreach (RegistryHive hive in new[] { RegistryHive.CurrentUser, RegistryHive.LocalMachine })
        foreach (RegistryView view in Views)
        using (RegistryKey root = RegistryKey.OpenBaseKey(hive, view))
        foreach (string excel in OfficePolicyRoots(excelMajor))
        {
            using (RegistryKey security = root.OpenSubKey(excel + "Security"))
            {
                if (IsOne(security, "DisableAllAddins")) return Fail(21, "Excel 추가 기능을 차단하는 설정이 적용되어 있습니다. IT 담당자의 승인 조건을 확인해 주세요.");
                if (IsOne(security, "RequireAddinSig")) return Fail(22, "신뢰된 서명이 필요한 환경입니다. 이 서명되지 않은 평가 빌드는 설치할 수 없습니다.");
            }
            using (RegistryKey resiliency = root.OpenSubKey(excel + "Resiliency"))
            using (RegistryKey managed = root.OpenSubKey(excel + @"Resiliency\AddinList"))
            {
                object entry = managed == null ? null : managed.GetValue(ProgId);
                string policyValue = entry == null ? null : Convert.ToString(entry, CultureInfo.InvariantCulture);
                if (policyValue == "0") return Fail(23, "조직 정책에서 이 추가 기능을 차단했습니다. IT 담당자의 승인이 필요합니다.");
                if (IsOne(resiliency, "RestrictToList") && policyValue != "1" && policyValue != "2")
                    return Fail(23, "허용 목록에 있는 추가 기능만 실행할 수 있습니다. IT 담당자에게 Workspace.ExcelSelectionExport 승인 여부를 확인해 주세요.");
            }
        }
        return 0;
    }
    static bool IsOne(RegistryKey key, string name)
    {
        object value = key == null ? null : key.GetValue(name);
        return value != null && Convert.ToString(value, CultureInfo.InvariantCulture) == "1";
    }
    static int DiagnoseActivation()
    {
        object instance = null;
        try
        {
            Type type = Type.GetTypeFromCLSID(new Guid(Clsid), true);
            instance = Activator.CreateInstance(type);
            Report["ComActivation"] = "PASS";
            Report["Message"] = "COM 활성화 검사를 통과했습니다. Excel의 실제 시작 시 메뉴 로드는 별도 확인해야 합니다.";
            return 0;
        }
        catch (Exception ex)
        {
            Report["ComActivation"] = "FAIL";
            return Fail(30, "COM 추가 기능을 로드하지 못했습니다 (" + ex.GetBaseException().HResult.ToString("X8") + "). 설치 파일 또는 Office 로드 진단을 확인해 주세요.");
        }
        finally { if (instance != null && Marshal.IsComObject(instance)) Marshal.ReleaseComObject(instance); }
    }
}
