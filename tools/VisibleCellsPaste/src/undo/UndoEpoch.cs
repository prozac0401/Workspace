using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Threading;

namespace VisibleCellsPaste
{
    // Exact IDispatch vtable. Pointer arguments prevent unused event VARIANTs becoming RCWs.
    [ComImport, ComVisible(true), Guid("00020400-0000-0000-C000-000000000046"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IRawExcelEventDispatch
    {
        [PreserveSig] int GetTypeInfoCount(out uint count);
        [PreserveSig] int GetTypeInfo(uint index, uint lcid, out IntPtr info);
        [PreserveSig] int GetIDsOfNames(ref Guid iid, IntPtr names, uint count, uint lcid, IntPtr ids);
        [PreserveSig] int Invoke(int dispId, ref Guid iid, uint lcid, ushort flags,
            IntPtr parameters, IntPtr result, IntPtr exception, IntPtr argumentError);
    }

    // Observes event identifiers only. It never reads or writes event arguments, including Cancel.
    // Connection-point ownership is private to this observer; the Application remains borrowed.
    public sealed class UndoEpoch : IDisposable
    {
        internal static readonly Guid EventInterface = new Guid("00024413-0000-0000-C000-000000000046");
        private readonly Action<object> releaseConnection;
        private IConnectionPoint connection;
        private EventSink sink;
        private int cookie;
        private long version;
        private bool disposed, available;

        public bool Available { get { return available && !disposed; } }
        public long Version { get { return Interlocked.Read(ref version); } }
        public bool Suppress { get; set; }

        public UndoEpoch(object application)
        {
            releaseConnection = ReleaseConnection;
            if (application == null || !Marshal.IsComObject(application)) return;
            try { Attach((IConnectionPointContainer)application); }
            catch { available = false; Invalidate(); }
        }

        // Fault-injection seam for connection ownership. Production always uses the constructor above.
        internal UndoEpoch(IConnectionPointContainer source, Action<object> release)
        {
            if (release == null) throw new ArgumentNullException("release");
            releaseConnection = release;
            try { Attach(source); }
            catch { available = false; Invalidate(); }
        }

        private void Attach(IConnectionPointContainer source)
        {
            IConnectionPoint acquired = null; int acquiredCookie = 0; bool transferred = false;
            var observer = new EventSink(this);
            try
            {
                Guid iid = EventInterface;
                source.FindConnectionPoint(ref iid, out acquired);
                if (acquired == null) throw new COMException("Excel event connection point unavailable");
                acquired.Advise(observer, out acquiredCookie);
                if (acquiredCookie == 0) throw new COMException("Excel event subscription unavailable");
                connection = acquired; cookie = acquiredCookie; sink = observer;
                available = true; transferred = true;
            }
            finally
            {
                if (!transferred) Disconnect(acquired, acquiredCookie);
                GC.KeepAlive(observer);
            }
        }

        private static void ReleaseConnection(object value)
        {
            if (value != null && Marshal.IsComObject(value))
                try { Marshal.ReleaseComObject(value); } catch (InvalidComObjectException) { }
        }
        private void Disconnect(IConnectionPoint owned, int ownedCookie)
        {
            if (owned == null) return;
            try { if (ownedCookie != 0) owned.Unadvise(ownedCookie); }
            catch { /* Excel can be disconnecting; disposal remains conservative and idempotent. */ }
            finally { try { releaseConnection(owned); } catch { } }
        }
        public void Invalidate() { Interlocked.Increment(ref version); }
        private void Observe(int dispId)
        {
            if (disposed || Suppress) return;
            switch (dispId)
            {
                case 1558: // SheetSelectionChange
                case 1561: // SheetActivate
                case 1562: // SheetDeactivate
                case 1564: // SheetChange
                case 1565: // NewWorkbook
                case 1567: // WorkbookOpen
                case 1568: // WorkbookActivate
                case 1569: // WorkbookDeactivate
                case 1570: // WorkbookBeforeClose
                case 1571: // WorkbookBeforeSave
                case 1573: // WorkbookNewSheet
                case 1556: // WindowActivate
                case 1557: // WindowDeactivate
                case 3079: // SheetBeforeDelete
                    Invalidate(); break;
            }
        }
        public void Dispose()
        {
            if (disposed) return;
            disposed = true; available = false; Invalidate();
            IConnectionPoint owned = connection; int ownedCookie = cookie; EventSink observer = sink;
            connection = null; cookie = 0; sink = null;
            Disconnect(owned, ownedCookie);
            GC.KeepAlive(observer);
        }

        [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
        public sealed class EventSink : IRawExcelEventDispatch, ICustomQueryInterface
        {
            private static readonly Guid DispatchInterface = new Guid("00020400-0000-0000-C000-000000000046");
            private static readonly Guid ManagedObjectInterface = new Guid("C3FCC19E-A970-11D2-8B5A-00A0C9B7C9C4");
            private readonly UndoEpoch owner;
            [DllImport("oleaut32.dll")] private static extern void VariantInit(IntPtr variant);
            internal EventSink(UndoEpoch observer) { owner = observer; }
            public int GetTypeInfoCount(out uint count) { count = 0; return 0; }
            public int GetTypeInfo(uint index, uint lcid, out IntPtr info) { info = IntPtr.Zero; return unchecked((int)0x80004001); }
            public int GetIDsOfNames(ref Guid iid, IntPtr names, uint count, uint lcid, IntPtr ids) { return unchecked((int)0x80004001); }
            public int Invoke(int dispId, ref Guid iid, uint lcid, ushort flags,
                IntPtr parameters, IntPtr result, IntPtr exception, IntPtr argumentError)
            {
                if (iid != Guid.Empty) return unchecked((int)0x80020001);
                if (result != IntPtr.Zero) VariantInit(result);
                // Do not dereference DISPPARAMS/VARIANTs. No RCW, Cancel mutation, or byref copy-back.
                owner.Observe(dispId);
                return 0;
            }
            CustomQueryInterfaceResult ICustomQueryInterface.GetInterface(ref Guid iid, out IntPtr pointer)
            {
                pointer = IntPtr.Zero;
                if (iid == EventInterface || iid == DispatchInterface)
                {
                    pointer = Marshal.GetComInterfaceForObject(this, typeof(IRawExcelEventDispatch), CustomQueryInterfaceMode.Ignore);
                    return CustomQueryInterfaceResult.Handled;
                }
                if (iid == ManagedObjectInterface) return CustomQueryInterfaceResult.Failed;
                return CustomQueryInterfaceResult.NotHandled;
            }
        }
    }
}
