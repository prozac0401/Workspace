using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;
namespace ImageCopySave.Engine;

internal enum SaveStage { Created, Written, Flushed, BeforeCommit }
public static class AtomicPngWriter
{
    public static string Save(ImageData image, string directory, CancellationToken cancellationToken = default)
        => SaveCore(image, directory, DateTime.Now, cancellationToken, null);
    internal static string SaveCore(ImageData image, string directory, DateTime localTime,
        CancellationToken cancellationToken, Action<SaveStage>? observer)
    {
        cancellationToken.ThrowIfCancellationRequested();
        using var directoryLease = LocalPaths.Acquire(directory, true);
        string folder = directoryLease.FullPath;
        image.Validate();
        byte[] png = ImageCodec.EncodePng(image);
        cancellationToken.ThrowIfCancellationRequested();
        string temporary = Path.Combine(folder, ".ImageCopySave-" + Guid.NewGuid().ToString("N") + ".tmp");
        // DELETE access permits rename/disposition of this exact handle, without pathname cleanup.
        using SafeFileHandle handle = CreateFile(LocalPaths.NativePath(temporary), 0x40000000 | 0x00010000,
            1, IntPtr.Zero, 1, 0x80000000 | 0x00000080, IntPtr.Zero);
        if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot create owned temporary file.");
        bool committed = false;
        Exception? operationFailure = null;
        try
        {
            using var output = new FileStream(new SafeFileHandle(handle.DangerousGetHandle(), ownsHandle: false), FileAccess.Write);
            observer?.Invoke(SaveStage.Created);
            cancellationToken.ThrowIfCancellationRequested();
            output.Write(png);
            observer?.Invoke(SaveStage.Written);
            output.Flush(true);
            observer?.Invoke(SaveStage.Flushed);
            string stem = "그림_" + localTime.ToString("yyyyMMdd_HHmmss", System.Globalization.CultureInfo.InvariantCulture);
            observer?.Invoke(SaveStage.BeforeCommit);
            for (int number = 1; number <= 10_000; number++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                string destination = Path.Combine(folder, stem + (number == 1 ? "" : "_" + number.ToString(System.Globalization.CultureInfo.InvariantCulture)) + ".png");
                int error = RenameWithoutReplace(handle, destination);
                if (error == 0)
                {
                    committed = true;
                    // A completed commit is success, even if cancellation arrives now.
                    return destination;
                }
                if (error != 80 && error != 183)
                    throw new Win32Exception(error, $"Final PNG could not be committed (native error {error}, candidate {number}).");
            }
            throw new IOException("File name collision limit reached.");
        }
        catch (Exception ex)
        {
            operationFailure = ex;
            throw;
        }
        finally
        {
            // The FileStream wrapper does not own the underlying handle. Cleanup targets
            // that exact object even if its directory entry was changed by another actor.
            if (!committed && !handle.IsClosed)
            {
                int cleanupError = DeleteOwnedHandle(handle);
                if (cleanupError != 0) throw new OwnedTemporaryCleanupException(cleanupError, operationFailure);
            }
        }
    }
    private static int RenameWithoutReplace(SafeFileHandle handle, string destination)
    {
        byte[] name = Encoding.Unicode.GetBytes(destination);
        int offset = IntPtr.Size == 8 ? 20 : 12;
        int lengthOffset = IntPtr.Size == 8 ? 16 : 8;
        int rootOffset = IntPtr.Size == 8 ? 8 : 4;
        int bufferLength = checked(offset + name.Length + sizeof(char));
        IntPtr data = Marshal.AllocHGlobal(bufferLength);
        try
        {
            // The Win32 path conversion also needs a terminating NUL, though
            // FileNameLength counts only the name bytes. Zero padding as well.
            Marshal.Copy(new byte[bufferLength], 0, data, bufferLength);
            Marshal.WriteInt32(data, 0, 0); // ReplaceIfExists = FALSE
            Marshal.WriteIntPtr(data, rootOffset, IntPtr.Zero);
            Marshal.WriteInt32(data, lengthOffset, name.Length);
            Marshal.Copy(name, 0, data + offset, name.Length);
            return SetFileInformationByHandle(handle, 3, data, (uint)bufferLength) ? 0 : Marshal.GetLastWin32Error();
        }
        finally { Marshal.FreeHGlobal(data); }
    }
    private static int DeleteOwnedHandle(SafeFileHandle handle)
    {
        IntPtr data = Marshal.AllocHGlobal(4);
        try { Marshal.WriteInt32(data, 1); return SetFileInformationByHandle(handle, 4, data, 4) ? 0 : Marshal.GetLastWin32Error(); }
        finally { Marshal.FreeHGlobal(data); }
    }
    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetFileInformationByHandle(SafeFileHandle handle, int informationClass, IntPtr data, uint length);
}

internal sealed class OwnedTemporaryCleanupException : IOException
{
    internal int NativeErrorCode { get; }
    internal OwnedTemporaryCleanupException(int error, Exception? operationFailure)
        : base("The operation failed and its owned temporary file could not be removed.", operationFailure)
    {
        NativeErrorCode = error;
        HResult = unchecked((int)0x80070000) | (error & 0xffff);
    }
}
