using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace ExcelPasswordSafe
{
    public sealed class DiscoveryIssue
    {
        public string path { get; set; }
        public string category { get; set; }
    }

    public sealed class BatchDiscovery
    {
        public readonly List<string> Files = new List<string>();
        public readonly List<DiscoveryIssue> Issues = new List<DiscoveryIssue>();
    }

    public static class BatchWorkflow
    {
        public static bool IsMode(string mode)
        {
            return mode == "Encrypt" || mode == "Decrypt" || mode == "ChangePassword";
        }

        public static string ModeLabel(string mode)
        {
            return mode == "Encrypt" ? "암호 설정" : mode == "Decrypt" ? "암호 해제" : "암호 변경";
        }

        public static bool ContainsPath(string root, string candidate)
        {
            string fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            string full = Path.GetFullPath(candidate);
            return full.Equals(fullRoot, StringComparison.OrdinalIgnoreCase) || full.StartsWith(fullRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
        }

        public static bool IsOwnedData(string path)
        {
            return ContainsPath(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ExcelPasswordSafe"), path);
        }

        public static void CheckDirectory(string path)
        {
            if (String.IsNullOrWhiteSpace(path) || path.Length < 3 || !Char.IsLetter(path[0]) || path[1] != ':' || (path[2] != '\\' && path[2] != '/') || path.Substring(2).Contains(":"))
                throw new ArgumentException("로컬 폴더를 선택하세요. 네트워크 경로는 지원하지 않습니다.");
            string full = Path.GetFullPath(path);
            if (!Directory.Exists(full)) throw new DirectoryNotFoundException("폴더를 찾을 수 없습니다.");
            var drive = new DriveInfo(Path.GetPathRoot(full));
            if (drive.DriveType != DriveType.Fixed || !String.Equals(drive.DriveFormat, "NTFS", StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("로컬 고정 NTFS 드라이브의 폴더를 선택하세요.");
            if (IsOwnedData(full)) throw new ArgumentException("프로그램의 백업·기록 폴더는 처리 대상이 아닙니다.");
            for (var entry = new DirectoryInfo(full); entry != null; entry = entry.Parent)
            {
                var attributes = File.GetAttributes(entry.FullName);
                if ((attributes & FileAttributes.ReparsePoint) != 0) throw new ArgumentException("연결·동기화 폴더는 지원하지 않습니다. 별도 로컬 폴더를 선택하세요.");
                if ((attributes & FileAttributes.Offline) != 0) throw new ArgumentException("오프라인 폴더는 처리할 수 없습니다.");
            }
        }

        public static bool IsWorkbookName(string path)
        {
            string name = Path.GetFileName(path);
            if (name.StartsWith("~$", StringComparison.Ordinal) || name.StartsWith(".eps-", StringComparison.OrdinalIgnoreCase)) return false;
            string extension = Path.GetExtension(path).ToLowerInvariant();
            return extension == ".xls" || extension == ".xlsx" || extension == ".xlsm" || extension == ".xlsb";
        }

        public static BatchDiscovery Discover(string root, CancellationToken token)
        {
            CheckDirectory(root);
            root = Path.GetFullPath(root);
            var result = new BatchDiscovery();
            var pending = new Stack<string>(); pending.Push(root);
            while (pending.Count > 0)
            {
                token.ThrowIfCancellationRequested();
                string directory = pending.Pop();
                try
                {
                    CheckDirectory(directory);
                    foreach (string path in Directory.EnumerateFileSystemEntries(directory, "*", SearchOption.TopDirectoryOnly))
                    {
                        token.ThrowIfCancellationRequested();
                        FileAttributes attributes;
                        try { attributes = File.GetAttributes(path); }
                        catch (UnauthorizedAccessException) { result.Issues.Add(new DiscoveryIssue { path = path, category = "FolderAccessDenied" }); continue; }
                        catch (IOException) { result.Issues.Add(new DiscoveryIssue { path = path, category = "EntryReadFailed" }); continue; }
                        bool isDirectory = (attributes & FileAttributes.Directory) != 0;
                        if (!isDirectory && !IsWorkbookName(path)) continue;
                        string blocked = IsOwnedData(path) ? "AppDataExcluded" :
                            (attributes & FileAttributes.ReparsePoint) != 0 ? "ReparsePoint" :
                            (attributes & FileAttributes.Offline) != 0 ? "OfflineFileUnsupported" : null;
                        if (blocked != null) { result.Issues.Add(new DiscoveryIssue { path = path, category = blocked }); continue; }
                        if (isDirectory) pending.Push(path);
                        else result.Files.Add(Path.GetFullPath(path));
                    }
                }
                catch (UnauthorizedAccessException) { result.Issues.Add(new DiscoveryIssue { path = directory, category = "FolderAccessDenied" }); }
                catch (IOException) { result.Issues.Add(new DiscoveryIssue { path = directory, category = "FolderReadFailed" }); }
                catch (ArgumentException) { result.Issues.Add(new DiscoveryIssue { path = directory, category = "FolderChangedOrUnsupported" }); }
                catch (System.Security.SecurityException) { result.Issues.Add(new DiscoveryIssue { path = directory, category = "FolderAccessDenied" }); }
            }
            result.Files.Sort(StringComparer.OrdinalIgnoreCase);
            result.Issues.Sort(delegate(DiscoveryIssue a, DiscoveryIssue b) { return StringComparer.OrdinalIgnoreCase.Compare(a.path, b.path); });
            return result;
        }

        public static ProcessStartInfo StartInfo(string baseDirectory, string runDirectory)
        {
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            return new ProcessStartInfo(powershell,
                "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File " + Workflow.QuoteArgument(Path.Combine(baseDirectory, @"runtime\BatchEngine.ps1")) +
                " -RequestPath " + Workflow.QuoteArgument(Path.Combine(runDirectory, "request.json")))
            { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = baseDirectory };
        }

        public static string Reason(string category)
        {
            switch (category)
            {
                case "FolderAccessDenied": case "FolderReadFailed": case "EntryReadFailed": return "이 위치를 읽지 못했습니다. 권한과 파일 상태를 확인하세요.";
                case "FolderChangedOrUnsupported": return "검색 중 폴더가 바뀌었거나 지원하지 않는 경로입니다.";
                case "AppDataExcluded": return "프로그램의 백업·기록 폴더는 제외했습니다.";
                case "NotProcessed": return "앞선 작업 중단으로 처리하지 않았습니다.";
                case "Cancelled": return "사용자 요청으로 취소했습니다. 완료된 파일은 유지합니다.";
                case "MissingResult": case "InvalidChildResult": case "MissingChildResult": return "처리 결과를 확인하지 못했습니다. 다시 실행하기 전에 백업과 현재 파일을 확인하세요.";
                case "FailureReportFailed": return "실패 기록 Excel을 저장하지 못했습니다. 백업·기록 폴더의 JSON 기록을 확인하세요.";
                case "TemporaryCleanupIncomplete": return "작업용 파일을 정리하지 못했습니다. 백업·기록 보기에서 남은 파일과 접근 권한을 확인하세요.";
                case "Completed": case "ReplacedAndVerified": return "완료";
                default: return ResultMessages.CategoryMessage(category);
            }
        }
    }
}
