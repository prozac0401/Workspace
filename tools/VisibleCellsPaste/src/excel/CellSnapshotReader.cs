using System;
using System.Runtime.InteropServices;

namespace VisibleCellsPaste
{
    // Reads exactly the already validated consecutive visible segments. It never expands a selection.
    public static class CellSnapshotReader
    {
        public static CellState[] Capture(object worksheet, PastePlan plan)
        {
            if (worksheet == null) throw new ArgumentNullException("worksheet");
            if (plan == null) throw new ArgumentNullException("plan");
            ValidateSegments(plan);
            var result = new CellState[plan.Targets.Count];
            dynamic sheet = worksheet;
            foreach (PasteSegment segment in plan.Segments)
            {
                string letters = ColumnLetters(segment.Column);
                string firstAddress = "$" + letters + "$" + segment.FirstRow;
                string lastAddress = "$" + ColumnLetters(segment.LastColumn) + "$" + segment.LastRow;
                using (var references = new ComScope())
                {
                    dynamic range = references.Own((object)sheet.Range[firstAddress + ":" + lastAddress]);
                    object hasFormula = range.HasFormula;
                    object format = range.NumberFormat;
                    if (!(hasFormula is bool) || !(format is string))
                    {
                        CaptureIndividually(worksheet, plan, segment, result);
                        continue;
                    }
                    object values = range.Value2;
                    if (!Fits(values, segment))
                    {
                        CaptureIndividually(worksheet, plan, segment, result);
                        continue;
                    }
                    bool formula = (bool)hasFormula;
                    object formulas = null;
                    string formulaProperty = null;
                    if (formula)
                    {
                        try { formulas = range.Formula2; formulaProperty = "Formula2"; }
                        catch (COMException) { formulas = range.Formula; formulaProperty = "Formula"; }
                        if (!Fits(formulas, segment))
                        {
                            CaptureIndividually(worksheet, plan, segment, result);
                            continue;
                        }
                    }
                    for (int offset = 0; offset < segment.Count; offset++)
                    {
                        TargetCell target = plan.Targets[segment.StartIndex + offset];
                        int row = target.Row;
                        result[segment.StartIndex + offset] = new CellState
                        {
                            Row = row, Column = target.Column, Address = "$" + ColumnLetters(target.Column) + "$" + row,
                            Formula = formula, FormulaProperty = formulaProperty,
                            FormulaValue = formula ? Item(formulas, offset, segment.Horizontal) : null,
                            Format = format, Value = ExcelEngine.ReadValue(Item(values, offset, segment.Horizontal))
                        };
                    }
                }
            }
            return result;
        }

        private static bool Fits(object value, PasteSegment segment)
        {
            Array array = value as Array;
            if (array == null) return segment.Count == 1;
            return array.Rank == 2 && array.GetLength(0) == (segment.Horizontal ? 1 : segment.Count) && array.GetLength(1) == (segment.Horizontal ? segment.Count : 1);
        }
        private static object Item(object value, int offset, bool horizontal)
        {
            Array array = value as Array;
            return array == null ? value : array.GetValue(array.GetLowerBound(0) + (horizontal ? 0 : offset), array.GetLowerBound(1) + (horizontal ? offset : 0));
        }
        private static void CaptureIndividually(object sheet, PastePlan plan, PasteSegment segment, CellState[] result)
        {
            for (int offset = 0; offset < segment.Count; offset++)
            {
                int index = segment.StartIndex + offset;
                TargetCell cell = plan.Targets[index];
                result[index] = ExcelEngine.ReadCell((dynamic)sheet, cell.Row, cell.Column);
            }
        }
        private static void ValidateSegments(PastePlan plan)
        {
            int next = 0;
            foreach (PasteSegment segment in plan.Segments)
            {
                if (segment.StartIndex != next || segment.Count < 1 || segment.Count > plan.Targets.Count - next ||
                    segment.Column < 1 || segment.Column > Limits.ExcelColumns || segment.FirstRow < 1 ||
                    (long)segment.FirstRow + (segment.Horizontal ? 0 : segment.Count - 1) > Limits.ExcelRows ||
                    (long)segment.Column + (segment.Horizontal ? segment.Count - 1 : 0) > Limits.ExcelColumns) throw InvalidPlan();
                for (int offset = 0; offset < segment.Count; offset++)
                {
                    TargetCell cell = plan.Targets[next + offset];
                    if (cell.Hidden || cell.Row != segment.FirstRow + (segment.Horizontal ? 0 : offset) || cell.Column != segment.Column + (segment.Horizontal ? offset : 0) ||
                        cell.SheetKey != plan.Selection.SheetKey || cell.Row < plan.Selection.FirstRow ||
                        cell.Row > plan.Selection.LastRow || cell.Column < plan.Selection.FirstColumn || cell.Column > plan.Selection.LastColumn) throw InvalidPlan();
                }
                next += segment.Count;
            }
            if (next != plan.Targets.Count) throw InvalidPlan();
        }
        private static ValidationException InvalidPlan()
        { return new ValidationException("VCP-SNAPSHOT-BOUNDARY", "백업 범위와 가시 셀 계획이 일치하지 않습니다. 변경된 셀은 없습니다."); }
        internal static string ColumnLetters(int column)
        {
            string letters = "";
            while (column > 0) { column--; letters = (char)('A' + column % 26) + letters; column /= 26; }
            return letters;
        }
    }
}
