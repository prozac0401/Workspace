using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

namespace VisibleCellsPaste
{
    // Observer only: never changes Excel selection, contents, Cancel flags or event settings.
    // DispIds/signatures checked against the installed Excel 15.0 PIA AppEvents interface.
    // Availability means connection points were attached; it does not prove that Excel emits
    // every structural change. The engine must also validate identity, state and Undo status.
    public sealed class UndoEpoch : IDisposable
    {
        private static readonly Guid EventInterface = new Guid("00024413-0000-0000-C000-000000000046");
        private readonly object application;
        private readonly List<Subscription> subscriptions = new List<Subscription>();
        private long version;
        private bool disposed;
        private bool available;

        private delegate void OneObject(object first);
        private delegate void TwoObjects(object first, object second);
        private delegate void BeforeClose(object workbook, ref bool cancel);
        private delegate void BeforeSave(object workbook, bool saveAsUI, ref bool cancel);

        private sealed class Subscription
        {
            public int DispId;
            public Delegate Handler;
            public Subscription(int id, Delegate handler) { DispId = id; Handler = handler; }
        }

        public bool Available { get { return available && !disposed; } }
        public long Version { get { return Interlocked.Read(ref version); } }

        // Excel callbacks and the engine run on the same STA. Only suppress the engine's
        // own synchronous write/restore interval; always restore this flag in a finally.
        public bool Suppress { get; set; }

        public UndoEpoch(object app)
        {
            application = app;
            if (app == null || !Marshal.IsComObject(app)) return;
            try
            {
                Attach(1558, new TwoObjects(OnTwo));   // SheetSelectionChange
                Attach(1561, new OneObject(OnOne));    // SheetActivate
                Attach(1562, new OneObject(OnOne));    // SheetDeactivate
                Attach(1564, new TwoObjects(OnTwo));   // SheetChange
                Attach(1565, new OneObject(OnOne));    // NewWorkbook
                Attach(1567, new OneObject(OnOne));    // WorkbookOpen
                Attach(1568, new OneObject(OnOne));    // WorkbookActivate
                Attach(1569, new OneObject(OnOne));    // WorkbookDeactivate
                Attach(1570, new BeforeClose(OnBeforeClose));
                Attach(1571, new BeforeSave(OnBeforeSave));
                Attach(1573, new TwoObjects(OnTwo));   // WorkbookNewSheet
                Attach(1556, new TwoObjects(OnTwo));   // WindowActivate
                Attach(1557, new TwoObjects(OnTwo));   // WindowDeactivate
                Attach(3079, new OneObject(OnOne));    // SheetBeforeDelete
                available = true;
            }
            catch
            {
                // Partial subscription is never enough to enable custom Undo.
                available = false;
                RemoveSubscriptions();
                Invalidate();
            }
        }

        private void Attach(int dispId, Delegate handler)
        {
            ComEventsHelper.Combine(application, EventInterface, dispId, handler);
            subscriptions.Add(new Subscription(dispId, handler));
        }

        public void Invalidate()
        {
            // Explicit invalidation is unconditional, even while own writes are suppressed.
            Interlocked.Increment(ref version);
        }

        private void Observe()
        {
            if (!disposed && !Suppress) Invalidate();
        }

        private void OnOne(object first) { Observe(); }
        private void OnTwo(object first, object second) { Observe(); }
        private void OnBeforeClose(object workbook, ref bool cancel) { Observe(); }
        private void OnBeforeSave(object workbook, bool saveAsUI, ref bool cancel) { Observe(); }

        private void RemoveSubscriptions()
        {
            for (int i = subscriptions.Count - 1; i >= 0; i--)
            {
                Subscription subscription = subscriptions[i];
                try { ComEventsHelper.Remove(application, EventInterface, subscription.DispId, subscription.Handler); }
                catch { /* Excel may already be disconnecting. Never modify someone else's sink. */ }
            }
            subscriptions.Clear();
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            available = false;
            Invalidate();
            RemoveSubscriptions();
            // The shared Application RCW belongs to the add-in; do not FinalReleaseComObject.
        }
    }
}
