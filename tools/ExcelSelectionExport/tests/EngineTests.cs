using System;
using System.Collections.Generic;
using System.Linq;
using ExcelSelectionExport;
internal static class EngineTests
{
    static int checks;
    static void Check(bool result, string name) { if (!result) throw new Exception(name); checks++; Console.WriteLine("PASS " + name); }
    static void Reject(Action action, string name)
    {
        try { action(); } catch (InvalidOperationException) { checks++; Console.WriteLine("PASS " + name); return; }
        throw new Exception("Expected rejection: " + name);
    }
    static int[] Sequence(int start, int count) { return Enumerable.Range(start, count).ToArray(); }
    static int Main()
    {
        try
        {
            var one = VisibleRangePlan.Create(8, 4, 1, 1, new[] { 8 }, new[] { 4 });
            Check(one.CellCount == 1 && one.OutputRow(8) == 1 && one.OutputColumn(4) == 1, "One cell preserves coordinate mapping");
            var plan = VisibleRangePlan.Create(10, 2, 100, 5, Sequence(10, 18), new[] { 2, 4, 6 });
            Check(plan.CellCount == 54 && plan.Rows.Length == 18 && plan.Columns.Length == 3, "100 input rows to 18 visible rows with hidden columns");
            Check(plan.OutputRow(27) == 18 && plan.OutputColumn(4) == 2, "Visible rows and columns map independently");
            var holes = VisibleRangePlan.Create(1, 1, 5, 5, new[] { 1, 3, 5 }, new[] { 1, 3, 5 });
            Check(holes.CellCount == 9 && holes.OutputRow(5) == 3 && holes.OutputColumn(5) == 3, "Alternating hidden rows/columns keep rectangular relationships");
            Check(VisibleRangePlan.Create(1, 1, 1, 6, new[] { 1 }, Sequence(1, 6)).CellCount == 6, "Horizontal finite list");
            Check(VisibleRangePlan.Create(1, 1, 6, 1, Sequence(1, 6), new[] { 1 }).CellCount == 6, "Vertical finite list");
            Check(VisibleRangePlan.Create(1, 1, 1000, 1000, Sequence(1, 100), Sequence(1, 1000)).CellCount == 100000, "Input/output exact limits accepted without truncation");
            Reject(delegate { VisibleRangePlan.Create(1, 1, 1001, 1000, new[] { 1 }, new[] { 1 }); }, "Input limit exceeded");
            Reject(delegate { VisibleRangePlan.Create(1, 1, 101, 1000, Sequence(1, 101), Sequence(1, 1000)); }, "Output limit exceeded");
            Reject(delegate { VisibleRangePlan.Create(1, 1, 2, 2, new int[0], new[] { 1 }); }, "No visible rows");
            Reject(delegate { VisibleRangePlan.Create(1, 1, 2, 2, new[] { 1 }, new int[0]); }, "No visible columns");
            Reject(delegate { VisibleRangePlan.Create(1, 1, 2, 2, new[] { 1, 1 }, new[] { 1 }); }, "Duplicate indices rejected");
            Reject(delegate { VisibleRangePlan.Create(1, 1, 2, 2, new[] { 2, 1 }, new[] { 1 }); }, "Unordered indices rejected");
            Reject(delegate { VisibleRangePlan.Create(2, 2, 2, 2, new[] { 1 }, new[] { 2 }); }, "Out-of-bounds visible indices");
            Reject(delegate { VisibleRangePlan.Create(Int32.MaxValue, 1, 2, 2, new[] { Int32.MaxValue }, new[] { 1 }); }, "Overflow-safe source bounds");
            Reject(delegate { VisibleRangePlan.Create(1, 1, 1, 16384, new[] { 1 }, new[] { 1 }); }, "Whole-row selection rejected");
            Reject(delegate { VisibleRangePlan.Create(1, 1, 1048576, 1, new[] { 1 }, new[] { 1 }); }, "Whole-column selection rejected");
            Reject(delegate { holes.OutputRow(2); }, "Hidden row has no output coordinate");
            Reject(delegate { holes.OutputColumn(2); }, "Hidden column has no output coordinate");
            var merge = VisibleRangePlan.Create(5, 3, 4, 4, Sequence(5, 4), Sequence(3, 4));
            merge.ValidateMerge(5, 3, 2, 3); Check(true, "Fully visible merge accepted");
            Reject(delegate { merge.ValidateMerge(4, 3, 2, 2); }, "Partial merge begins before selection");
            Reject(delegate { merge.ValidateMerge(8, 3, 2, 2); }, "Partial merge extends past selection");
            Reject(delegate { holes.ValidateMerge(1, 1, 3, 1); }, "Merge cut by hidden row rejected");
            Reject(delegate { holes.ValidateMerge(1, 1, 1, 3); }, "Merge cut by hidden column rejected");
            Reject(delegate { merge.ValidateMerge(5, 3, Int32.MaxValue, 1); }, "Overflow-safe merge bounds");
            int[] sourceRows = new[] { 5, 6 };
            var copied = VisibleRangePlan.Create(5, 3, 2, 1, sourceRows, new[] { 3 }); sourceRows[0] = 1;
            Check(copied.Rows[0] == 5, "Input coordinate arrays are snapshotted");
            Console.WriteLine(checks + " planner checks passed"); return 0;
        }
        catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
    }
}
