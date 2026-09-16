using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace FolderState.Core;

internal static class SafeFiles
{
    public const int MaxBytes = 512 * 1024;
    public static string Folder(string input)
    {
        if (string.IsNullOrWhiteSpace(input) || !Path.IsPathFullyQualified(input) || input.StartsWith(@"\\?\", StringComparison.Ordinal) || input.StartsWith(@"\\.\", StringComparison.Ordinal))
            throw new StateException("invalid_path", "폴더의 전체 경로를 입력해 주세요. 드라이브 이름이나 공유 폴더의 서버 이름부터 포함해야 합니다.");
        string full = Path.TrimEndingDirectorySeparator(Path.GetFullPath(input));
        if (full.Equals(Path.TrimEndingDirectorySeparator(Path.GetPathRoot(full)!), StringComparison.OrdinalIgnoreCase))
            throw new StateException("root_not_supported", "드라이브나 공유 위치 전체에는 상태를 표시할 수 없습니다. 그 안의 업무 폴더 하나를 선택해 주세요.");
        if (!Directory.Exists(full)) throw new StateException("folder_missing", "폴더를 찾을 수 없습니다. 경로와 연결 상태를 확인해 주세요.");
        for (DirectoryInfo? d = new(full); d is not null; d = d.Parent)
            if ((d.Attributes & FileAttributes.ReparsePoint) != 0)
                throw new StateException("reparse_point", "다른 위치로 연결된 폴더나 파일이 아직 내려받아지지 않은 폴더는 사용할 수 없습니다. 이 PC에 실제로 저장된 일반 폴더를 선택해 주세요.");
        return full;
    }
    public static Snapshot Read(string file, int limit = MaxBytes)
    {
        FileAttributes attributes;
        try { attributes = File.GetAttributes(file); }
        catch (FileNotFoundException) { return Snapshot.Missing; }
        if ((attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
            throw new StateException("unsafe_metadata", "설정 파일이 있어야 할 자리에 폴더나 다른 위치로 연결된 항목이 있습니다. 해당 항목을 지우지 말고 지원을 요청해 주세요.");
        using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (OperatingSystem.IsWindows())
        {
            if (!GetFileInformationByHandle(stream.SafeFileHandle, out var info)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            if (info.NumberOfLinks != 1) throw new StateException("hard_link", "설정 파일이 다른 위치에서도 같은 파일로 쓰이고 있어 바꿀 수 없습니다. 파일을 지우지 말고 지원을 요청해 주세요.");
        }
        if (stream.Length > limit) throw new StateException("metadata_too_large", "파일의 크기가 너무 커서 읽을 수 없습니다. 파일을 그대로 두고 지원을 요청해 주세요.");
        byte[] bytes = new byte[checked((int)stream.Length)]; stream.ReadExactly(bytes);
        return new Snapshot(bytes, attributes);
    }
    public static bool SameData(Snapshot left, Snapshot right) =>
        left.Data is null ? right.Data is null : right.Data is not null && left.Data.AsSpan().SequenceEqual(right.Data);

    public static void Write(string file, Snapshot expected, Snapshot desired)
    {
        var current = Read(file);
        if (!SameData(current, expected)) throw new StateException("concurrent_edit", "작업 중에 폴더 설정이 바뀌어 작업을 멈췄습니다. 설정 파일을 지우지 말고 바뀐 내용을 확인해 주세요.");
        // Recovery need not replace an unchanged file. In particular, an old icon
        // can still be open by Explorer after a failed delete; leave its bytes intact.
        if (SameData(current, desired) && (current.Data is null || current.Attributes == desired.Attributes)) return;
        var parent = Path.GetDirectoryName(file)!;
        _ = Folder(parent);
        string temporary = Path.Combine(parent, ".folderstate-" + Guid.NewGuid().ToString("N") + ".tmp");
        bool attributesCleared = false;
        try
        {
            if (desired.Data is not null)
            {
                using var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough);
                stream.Write(desired.Data); stream.Flush(true);
            }
            if (current.Data is not null && (current.Attributes & FileAttributes.ReadOnly) != 0)
            { File.SetAttributes(file, current.Attributes & ~FileAttributes.ReadOnly); attributesCleared = true; }
            if (desired.Data is null) { if (current.Data is not null) File.Delete(file); }
            else
            {
                if (current.Data is null) File.Move(temporary, file); else File.Replace(temporary, file, null);
                File.SetAttributes(file, desired.Attributes);
            }
        }
        catch
        {
            if (attributesCleared && File.Exists(file)) File.SetAttributes(file, current.Attributes);
            throw;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct FileInformation
    {
        public uint Attributes; public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        public uint VolumeSerial, SizeHigh, SizeLow, NumberOfLinks, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInformation info);
}
