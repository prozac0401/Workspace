using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace ImageCopySave.Engine;

public static class LocalPaths
{
    private const FileAttributes HydrationFlags = (FileAttributes)(0x1000 | 0x40000 | 0x400000);
    private const uint ReadAndAttributes = 0x81; // FILE_READ_DATA / FILE_LIST_DIRECTORY + FILE_READ_ATTRIBUTES
    private const uint OpenReparsePoint = 0x00200000;
    private const uint OpenNoRecall = 0x00100000;
    private const uint BackupSemantics = 0x02000000;

    public static string Validate(string input, bool directory)
    {
        using var lease = Acquire(input, directory);
        return lease.FullPath;
    }

    // Pin every component from the volume root before resolving the next component.
    // Actual read/list access is required: attribute-only handles do not enforce
    // sharing restrictions. We never enumerate directories through these handles.
    // Directory handles deny delete sharing to prevent rename/replacement. Write sharing
    // is required by Windows rename-into-directory; files deny both write and delete.
    internal static PathLease Acquire(string input, bool directory)
    {
        if (string.IsNullOrWhiteSpace(input) || input.Length < 3 || !char.IsAsciiLetter(input[0]) || input[1] != ':' || (input[2] != '\\' && input[2] != '/') || input.AsSpan(2).Contains(':'))
            throw new IOException("An explicit local filesystem path is required.");
        string full = Path.GetFullPath(input);
        string volume = Path.GetPathRoot(full)!;
        if (new DriveInfo(volume).DriveType != DriveType.Fixed)
            throw new IOException("Only fixed local volumes are supported by this evaluation.");
        var target = new StringBuilder(1024);
        if (QueryDosDevice(volume[..2], target, target.Capacity) == 0 || !target.ToString().StartsWith(@"\Device\HarddiskVolume", StringComparison.OrdinalIgnoreCase))
            throw new IOException("Mapped or virtual drive aliases are not supported.");
        var lease = new PathLease(full);
        try
        {
            string current = volume;
            lease.Add(OpenChecked(current, true, ReadAndAttributes));
            string[] parts = full[volume.Length..].Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0 && !directory) throw new IOException("Source is not a file.");
            for (int index = 0; index < parts.Length; index++)
            {
                current = Path.Combine(current, parts[index]);
                bool expectDirectory = directory || index < parts.Length - 1;
                lease.Add(OpenChecked(current, expectDirectory, ReadAndAttributes));
            }
            return lease;
        }
        catch { lease.Dispose(); throw; }
    }

    public static ImageData ReadImage(string input, CancellationToken cancellationToken = default)
    {
        using var lease = Acquire(input, false);
        string extension = Path.GetExtension(lease.FullPath).ToLowerInvariant();
        if (extension is not (".png" or ".jpg" or ".jpeg" or ".bmp"))
            throw new InvalidDataException("Unsupported image extension.");
        cancellationToken.ThrowIfCancellationRequested();
        using SafeFileHandle handle = OpenChecked(lease.FullPath, false, 0x80000000);
        using var stream = new FileStream(handle, FileAccess.Read);
        ImageLimits.ValidatePayload(stream.Length);
        byte[] bytes = new byte[checked((int)stream.Length)];
        stream.ReadExactly(bytes);
        cancellationToken.ThrowIfCancellationRequested();
        return ImageCodec.Decode(bytes, extension);
    }

    private static SafeFileHandle OpenChecked(string full, bool directory, uint access)
    {
        SafeFileHandle handle = CreateFile(NativePath(full), access, directory ? 3u : 1u, IntPtr.Zero, 3,
            OpenReparsePoint | OpenNoRecall | BackupSemantics, IntPtr.Zero);
        if (handle.IsInvalid)
        {
            int error = Marshal.GetLastWin32Error(); handle.Dispose();
            throw new IOException("Cannot safely open the local path.", new Win32Exception(error));
        }
        try
        {
            if (!GetFileInformationByHandle(handle, out FileInformation info))
                throw new IOException("Cannot verify the opened local path.", new Win32Exception(Marshal.GetLastWin32Error()));
            FileAttributes attributes = (FileAttributes)info.Attributes;
            if ((attributes & (FileAttributes.ReparsePoint | HydrationFlags)) != 0)
                throw new IOException("Reparse or online-only paths are not read automatically.");
            if (attributes.HasFlag(FileAttributes.Directory) != directory)
                throw new IOException(directory ? "Target is not a directory." : "Source is not a file.");
            return handle;
        }
        catch { handle.Dispose(); throw; }
    }

    internal static string NativePath(string full) => @"\\?\" + full;

    internal sealed class PathLease(string fullPath) : IDisposable
    {
        private readonly List<SafeFileHandle> handles = [];
        internal string FullPath { get; } = fullPath;
        internal void Add(SafeFileHandle handle) => handles.Add(handle);
        public void Dispose()
        {
            for (int index = handles.Count - 1; index >= 0; index--) handles[index].Dispose();
            handles.Clear();
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileInformation
    {
        internal uint Attributes;
        internal System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        internal uint VolumeSerialNumber, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }
    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInformation information);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint QueryDosDevice(string name, StringBuilder target, int size);
}
