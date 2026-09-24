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
                string lastAddress = "$" + letters + "$" + segment.LastRow;
                dynamic range = sheet.Range[firstAddress + ":" + lastAddress];
                try
                {
                    object hasFormula = range.HasFormula;
                    object format = range.NumberFormat;
                    if (!(hasFormula is bool) || !(format is string))
                    {
                        CaptureIndividually(worksheet, plan, segment, result);
                        continue;
                    }
                    object values = range.Value2;
                    if (!Fits(values, segment.Count))
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
                        if (!Fits(formulas, segment.Count))
                        {
                            CaptureIndividually(worksheet, plan, segment, result);
                            continue;
                        }
                    }
                    for (int offset = 0; offset < segment.Count; offset++)
                    {
                        int row = segment.FirstRow + offset;
                        result[segment.StartIndex + offset] = new CellState
                        {
                            Row = row, Column = segment.Column, Address = "$" + letters + "$" + row,
                            Formula = formula, FormulaProperty = formulaProperty,
                            FormulaValue = formula ? Item(formulas, offset) : null,
                            Format = format, Value = ExcelEngine.ReadValue(Item(values, offset))
                        };
                    }
                }
                finally { ExcelEngine.Release((object)range); }
            }
            return result;
        }

        private static bool Fits(object value, int count)
        {
            Array array = value as Array;
            if (array == null) return count == 1;
            return array.Rank == 2 && array.GetLength(0) == count && array.GetLength(1) == 1;
        }
        private static object Item(object value, int offset)
        {
            Array array = value as Array;
            return array == null ? value : array.GetValue(array.GetLowerBound(0) + offset, array.GetLowerBound(1));
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
                    (long)segment.FirstRow + segment.Count - 1 > Limits.ExcelRows) throw InvalidPlan();
                for (int offset = 0; offset < segment.Count; offset++)
                {
                    TargetCell cell = plan.Targets[next + offset];
                    if (cell.Hidden || cell.Row != segment.FirstRow + offset || cell.Column != segment.Column ||
                        cell.SheetKey != plan.Selection.SheetKey || cell.Row < plan.Selection.FirstRow ||
                        cell.Row > plan.Selection.LastRow || cell.Column != plan.Selection.FirstColumn) throw InvalidPlan();
                }
                next += segment.Count;
            }
            if (next != plan.Targets.Count) throw InvalidPlan();
        }
        private static ValidationException InvalidPlan()
        { return new ValidationException("VCP-SNAPSHOT-BOUNDARY", "백업 범위와 가시 셀 계획이 일치하지 않습니다. 변경된 셀은 없습니다."); }
        private static string ColumnLetters(int column)
        {
            string letters = "";
            while (column > 0) { column--; letters = (char)('A' + column % 26) + letters; column /= 26; }
            return letters;
        }
    }
}
