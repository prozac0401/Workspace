using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;

namespace ExcelPasswordSafe
{
    /// <summary>Windows Common Item Dialog in single filesystem-folder mode.</summary>
    public static class FolderPicker
    {
        const int Cancelled = unchecked((int)0x800704C7);
        const uint PickFolders = 0x20;
        const uint ForceFileSystem = 0x40;
        const uint PathMustExist = 0x800;
        const uint NoChangeDirectory = 0x8;
        const uint FileSystemPath = 0x80058000;

        public static string Pick(Window owner)
        {
            if (owner == null) throw new ArgumentNullException("owner");
            owner.Dispatcher.VerifyAccess();
            if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA)
                throw new InvalidOperationException("폴더 선택은 앱 창에서 실행해야 합니다.");

            IFileOpenDialog dialog = null;
            IShellItem selected = null;
            IntPtr name = IntPtr.Zero;
            try
            {
                dialog = (IFileOpenDialog)new FileOpenDialog();
                uint options;
                dialog.GetOptions(out options);
                dialog.SetOptions(options | PickFolders | ForceFileSystem | PathMustExist | NoChangeDirectory);
                dialog.SetTitle("Excel 파일이 있는 폴더 선택");
                dialog.SetOkButtonLabel("이 폴더 선택");
                int result = dialog.Show(new WindowInteropHelper(owner).EnsureHandle());
                if (result == Cancelled) return null;
                Marshal.ThrowExceptionForHR(result);
                dialog.GetResult(out selected);
                selected.GetDisplayName(FileSystemPath, out name);
                string path = Marshal.PtrToStringUni(name);
                if (String.IsNullOrWhiteSpace(path)) throw new IOException("선택한 폴더 경로를 읽지 못했습니다.");
                return Path.GetFullPath(path);
            }
            finally
            {
                if (name != IntPtr.Zero) Marshal.FreeCoTaskMem(name);
                try { if (selected != null) Marshal.FinalReleaseComObject(selected); }
                finally { if (dialog != null) Marshal.FinalReleaseComObject(dialog); }
            }
        }

        [ComImport, Guid("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7")]
        class FileOpenDialog { }

        // Preserve the native IModalWindow + IFileDialog + IFileOpenDialog
        // vtable order. Unused pointer arguments stay opaque; no extra shell
        // interfaces or event handlers are created by this picker.
        [ComImport, Guid("D57C7288-D4AD-4768-BE02-9D969532D960"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IFileOpenDialog
        {
            [PreserveSig] int Show(IntPtr owner);
            void SetFileTypes(uint count, IntPtr filters);
            void SetFileTypeIndex(uint index);
            void GetFileTypeIndex(out uint index);
            void Advise(IntPtr events, out uint cookie);
            void Unadvise(uint cookie);
            void SetOptions(uint options);
            void GetOptions(out uint options);
            void SetDefaultFolder(IShellItem folder);
            void SetFolder(IShellItem folder);
            void GetFolder(out IShellItem folder);
            void GetCurrentSelection(out IShellItem item);
            void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
            void GetFileName(out IntPtr name);
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
            void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
            void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
            void GetResult(out IShellItem item);
            void AddPlace(IShellItem item, uint placement);
            void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string extension);
            void Close(int result);
            void SetClientGuid(ref Guid guid);
            void ClearClientData();
            void SetFilter(IntPtr filter);
            void GetResults(out IntPtr items);
            void GetSelectedItems(out IntPtr items);
        }

        [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IShellItem
        {
            void BindToHandler(IntPtr bindContext, ref Guid handler, ref Guid interfaceId, out IntPtr result);
            void GetParent(out IShellItem parent);
            void GetDisplayName(uint kind, out IntPtr name);
            void GetAttributes(uint mask, out uint attributes);
            void Compare(IShellItem item, uint hint, out int order);
        }
    }
}
