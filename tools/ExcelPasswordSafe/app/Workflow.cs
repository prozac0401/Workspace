using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace ExcelPasswordSafe
{
    public static class Workflow
    {
        public static string QuoteArgument(string value)
        {
            var result = new StringBuilder("\"");
            int slashes = 0;
            foreach (char ch in value)
            {
                if (ch == '\\') { slashes++; continue; }
                if (ch == '"') result.Append('\\', slashes * 2 + 1);
                else result.Append('\\', slashes);
                result.Append(ch); slashes = 0;
            }
            return result.Append('\\', slashes * 2).Append('"').ToString();
        }

        // Same wire format as Windows PowerShell ConvertFrom-SecureString (no key).
        public static string ProtectPassword(SecureString password)
        {
            if (password.Length == 0) return "";
            IntPtr pointer = Marshal.SecureStringToBSTR(password);
            var bytes = new byte[password.Length * 2];
            try
            {
                Marshal.Copy(pointer, bytes, 0, bytes.Length);
                byte[] encrypted = ProtectedData.Protect(bytes, null, DataProtectionScope.CurrentUser);
                try { return BitConverter.ToString(encrypted).Replace("-", "").ToLowerInvariant(); }
                finally { Array.Clear(encrypted, 0, encrypted.Length); }
            }
            finally { Array.Clear(bytes, 0, bytes.Length); Marshal.ZeroFreeBSTR(pointer); }
        }

        public static bool PasswordsEqual(SecureString left, SecureString right)
        {
            if (left.Length != right.Length) return false;
            IntPtr a = Marshal.SecureStringToBSTR(left), b = Marshal.SecureStringToBSTR(right);
            try
            {
                int difference = 0;
                for (int i = 0; i < left.Length * 2; i++) difference |= Marshal.ReadByte(a, i) ^ Marshal.ReadByte(b, i);
                return difference == 0;
            }
            finally { Marshal.ZeroFreeBSTR(a); Marshal.ZeroFreeBSTR(b); }
        }

        public static string ValidatePasswords(string mode, SecureString oldPassword, SecureString newPassword, SecureString confirmation)
        {
            if (mode != "Encrypt" && mode != "Decrypt" && mode != "ChangePassword") return "작업을 선택하세요.";
            if (mode != "Encrypt" && oldPassword.Length == 0) return "현재 암호를 입력하세요.";
            if (mode != "Decrypt")
            {
                if (newPassword.Length < 1 || newPassword.Length > 15) return "새 암호는 1~15자로 입력하세요.";
                if (!PasswordsEqual(newPassword, confirmation)) return "새 암호와 확인 입력이 서로 다릅니다.";
                if (mode == "ChangePassword" && PasswordsEqual(oldPassword, newPassword)) return "현재 암호와 다른 새 암호를 입력하세요.";
            }
            return null;
        }

        public static string ValidateFile(string path)
        {
            try { return ValidateFileCore(path); }
            catch (UnauthorizedAccessException) { return "파일 접근 권한을 확인하고 다시 선택하세요."; }
            catch (IOException) { return "파일이나 드라이브에 접근할 수 없습니다. 위치를 확인하고 다시 선택하세요."; }
            catch (ArgumentException) { return "파일 경로가 올바르지 않습니다. 파일을 다시 선택하세요."; }
            catch (System.Security.SecurityException) { return "이 파일에 접근할 권한이 없습니다."; }
        }

        static string ValidateFileCore(string path)
        {
            if (String.IsNullOrWhiteSpace(path)) return "Excel 파일 하나를 선택하세요.";
            if (path.Length < 3 || !Char.IsLetter(path[0]) || path[1] != ':' || (path[2] != '\\' && path[2] != '/'))
                return "로컬 드라이브의 Excel 파일을 선택하세요. 네트워크 경로는 지원하지 않습니다.";
            var drive = new DriveInfo(Path.GetPathRoot(path));
            if (drive.DriveType != DriveType.Fixed || !String.Equals(drive.DriveFormat, "NTFS", StringComparison.OrdinalIgnoreCase))
                return "로컬 고정 NTFS 드라이브의 파일을 선택하세요.";
            string extension = Path.GetExtension(path).ToLowerInvariant();
            if (extension != ".xls" && extension != ".xlsx" && extension != ".xlsm" && extension != ".xlsb")
                return "지원 형식은 .xls, .xlsx, .xlsm, .xlsb입니다.";
            if (!File.Exists(path)) return "파일을 찾을 수 없습니다. 위치를 확인하고 다시 선택하세요.";
            FileAttributes attributes = File.GetAttributes(path);
            if ((attributes & FileAttributes.Offline) != 0) return "오프라인 파일입니다. 별도 로컬 폴더에 복사한 뒤 선택하세요.";
            if ((attributes & FileAttributes.ReadOnly) != 0) return "읽기 전용 파일입니다. 파일 속성과 저장 권한을 확인하세요.";
            FileSystemInfo entry = new FileInfo(path);
            while (entry != null)
            {
                if ((entry.Attributes & FileAttributes.ReparsePoint) != 0) return "연결·동기화 경로는 지원하지 않습니다. 별도 로컬 폴더의 파일을 선택하세요.";
                var file = entry as FileInfo;
                entry = file != null ? file.Directory : ((DirectoryInfo)entry).Parent;
            }
            if (Path.GetFileName(path).StartsWith("~$", StringComparison.Ordinal) || Path.GetFileName(path).StartsWith(".eps-", StringComparison.OrdinalIgnoreCase))
                return "작업용 임시 파일은 선택할 수 없습니다. 원본 Excel 파일을 선택하세요.";
            return null;
        }

        public static void CreatePrivateDirectory(string path)
        {
            var acl = new DirectorySecurity();
            var sid = WindowsIdentity.GetCurrent().User;
            acl.SetAccessRuleProtection(true, false);
            acl.SetOwner(sid);
            var inheritance = InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit;
            acl.AddAccessRule(new FileSystemAccessRule(sid, FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
            acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null), FileSystemRights.FullControl, inheritance, PropagationFlags.None, AccessControlType.Allow));
            Directory.CreateDirectory(path, acl);
        }

        public static string Hash(string path)
        {
            using (var stream = File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "");
        }

        public static ProcessStartInfo EngineStartInfo(string baseDirectory, string runDirectory)
        {
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
            return new ProcessStartInfo(powershell,
                "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File " + QuoteArgument(Path.Combine(baseDirectory, @"runtime\Engine.ps1")) +
                " -RequestPath " + QuoteArgument(Path.Combine(runDirectory, "request.json")))
            { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = baseDirectory };
        }
    }

    public static class ResultMessages
    {
        public static string CategoryMessage(string category)
        {
            switch (category)
            {
                case "AlreadyEncrypted": return "이미 암호가 있는 파일입니다. ‘암호 변경’에서 현재 암호와 새 암호를 입력하세요.";
                case "AlreadyUnencrypted": case "NotEncrypted": return "암호가 없는 파일입니다. ‘암호 설정’을 선택하세요.";
                case "OpenFailedPossiblePasswordOrCorruption": return "파일을 열 수 없습니다. 현재 암호를 확인하고, Excel에서 파일이 정상으로 열리는지 확인하세요.";
                case "ExcelOwnershipOrExistingProcess": case "ExistingExcel": case "ExcelStillRunning": return "Excel이 실행 중입니다. 작업을 저장하고 Excel을 모두 정상 종료한 뒤 다시 시도하세요.";
                case "FileInUse": return "다른 프로그램에서 파일을 사용 중입니다. 파일을 닫고 다시 시도하세요.";
                case "Busy": case "AnotherOperationRunning": return "다른 암호 작업이 실행 중입니다. 완료된 뒤 다시 시도하세요.";
                case "SourceChanged": return "파일이 선택 후 변경되었습니다. 최신 파일을 확인하고 다시 실행하세요.";
                case "AccessDenied": case "ReadOnlyAttribute": return "파일이나 폴더에 쓸 수 없습니다. 읽기 전용 속성과 저장 권한을 확인하세요.";
                case "UnsupportedLocation": case "LocalPathRequired": case "LocalNtfsRequired": case "ReparsePoint": case "OfflineFileUnsupported": return "로컬 NTFS 드라이브의 일반 파일을 선택하세요. 네트워크·연결 폴더는 지원하지 않습니다.";
                case "FileNotFound": return "파일을 찾을 수 없습니다. 파일 위치를 확인하고 다시 선택하세요.";
                case "UnsupportedOrMismatchedFormat": return "확장자와 실제 파일 형식이 다르거나 지원하지 않는 구형 형식입니다. 원본을 유지했습니다.";
                case "Excel4MacroSheetUnsupported": return "Excel 4.0 매크로 시트가 있는 파일은 지원하지 않습니다. 원본을 유지했습니다.";
                case "WorkerTimeout": return "Excel 응답 시간이 지났습니다. 원본·백업·임시 파일과 남아 있는 Excel을 확인한 뒤 다시 시도하세요.";
                case "WorkerSessionUnsafe": return "Excel 상태를 확인할 수 없어 중단했습니다. 실행 기록과 열린 Excel을 확인하세요.";
                case "ComRegistrationOrLibrary": return "데스크톱 Excel을 시작할 수 없습니다. Excel 설치 상태를 확인하세요.";
                case "CommitUncertain": return "저장 완료 여부가 불확실합니다. 자동으로 재시도하지 말고 백업·복구본·기록을 확인하세요.";
                case "SignedWorkbookUnsupported": return "서명된 파일은 처리하지 않았습니다. 원본의 서명을 유지합니다.";
                case "SharedWorkbookUnsupported": return "공유 통합 문서는 지원하지 않습니다. 원본을 유지했습니다.";
                case "WriteReservedUnsupported": return "쓰기 암호가 있는 파일은 지원하지 않습니다. 원본을 유지했습니다.";
                case "ValidationFailed": return "저장 후 확인을 통과하지 못했습니다. 원본을 바꾸지 않았습니다. 백업·기록을 확인하세요.";
                default: return "작업을 완료하지 못했습니다. 백업·기록의 확인 코드를 확인하세요.";
            }
        }
    }
}
