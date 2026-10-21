using System;
using System.Collections.Generic;

namespace VisibleCellsPaste
{
    public static class Planner
    {
        public static void ValidateSelectionShape(SelectionSnapshot selection)
        {
            if (selection == null) throw new ArgumentNullException("selection");
            if (String.IsNullOrEmpty(selection.SheetKey) || selection.FirstRow < 1 || selection.LastRow > Limits.ExcelRows ||
                selection.FirstRow > selection.LastRow || selection.FirstColumn < 1 || selection.ColumnCount < 1 ||
                (long)selection.FirstColumn + selection.ColumnCount - 1 > Limits.ExcelColumns)
                throw new ValidationException("VCP-TARGET-BOUNDARY", "대상 선택 범위를 확인할 수 없습니다. 변경된 셀은 없습니다.");
            if (selection.AreaCount != 1 || selection.GroupedSheets)
                throw new ValidationException("VCP-TARGET-SHAPE", "한 워크시트에서 연속된 직사각형 범위를 선택해 주세요. 변경된 셀은 없습니다.");
            if (selection.CellCount != ((long)selection.LastRow - selection.FirstRow + 1) * selection.ColumnCount)
                throw new ValidationException("VCP-TARGET-COUNT", "대상 선택 크기가 일치하지 않습니다. 변경된 셀은 없습니다.");
            if (!selection.IsAnchorExpansion && ((selection.FirstRow == 1 && selection.LastRow == Limits.ExcelRows) ||
                (selection.FirstColumn == 1 && selection.ColumnCount == Limits.ExcelColumns)))
                throw new ValidationException("VCP-TARGET-WHOLE", "전체 행·열은 지원하지 않습니다. 필요한 범위만 선택해 주세요. 변경된 셀은 없습니다.");
            if (selection.CellCount > Limits.MaxSelectionCells)
                throw new ValidationException("VCP-TARGET-SCAN-LIMIT", "선택 범위는 최대 200,000칸입니다. 변경된 셀은 없습니다.");
            if (selection.ColumnHidden)
                throw new ValidationException("VCP-TARGET-HIDDEN-COLUMN", "숨긴 열에는 붙여넣을 수 없습니다. 변경된 셀은 없습니다.");
        }

        internal static void ValidateSource(ClipboardSnapshot source)
        {
            if (source == null) throw new ArgumentNullException("source");
            if (!source.ShapeIsVerified || source.SourceRows < 1 || source.SourceColumns < 1 ||
                source.SourceRows > Limits.ExcelRows || source.SourceColumns > Limits.ExcelColumns ||
                (long)source.SourceRows * source.SourceColumns != source.Items.Count)
                throw new ValidationException("VCP-SOURCE-SHAPE", "복사한 셀의 개수 또는 데이터 형식을 정확히 확인할 수 없습니다. 변경된 셀은 없습니다.");
            if (source.Items.Count > Limits.MaxItems)
                throw new ValidationException("VCP-SOURCE-LIMIT", "복사 항목은 최대 50,000개입니다. 변경된 셀은 없습니다.");
        }

        // Visibility-only queries: grow the search window, then split mixed spans.
        // Uniform visible/hidden spans need one query regardless of their length.
        internal static int FindVisibleAxisEnd(int first, int last, int count, Func<int, int, bool?> hidden)
        {
            if (first < 1 || last < first || last > Limits.ExcelRows || count < 1 || count > Limits.MaxItems)
                throw new ArgumentOutOfRangeException("count");
            if (hidden == null) throw new ArgumentNullException("hidden");
            int remaining = count, span = count;
            for (int start = first; start <= last; )
            {
                int end = (int)Math.Min(last, (long)start + span - 1);
                int found = FindVisibleAxisEndCore(start, end, ref remaining, hidden);
                if (found != 0) return found;
                start = end + 1;
                span = Math.Min(last - first + 1, span * 2);
            }
            throw new ValidationException("VCP-ANCHOR-SPACE", "시작 셀부터 붙여넣을 보이는 칸이 부족하거나 대상 범위가 200,000칸을 넘습니다. 변경된 셀은 없습니다.");
        }

        private static int FindVisibleAxisEndCore(int first, int last, ref int remaining, Func<int, int, bool?> hidden)
        {
            bool? state = hidden(first, last);
            if (state == true) return 0;
            if (state == false)
            {
                int length = last - first + 1;
                if (length >= remaining) return first + remaining - 1;
                remaining -= length;
                return 0;
            }
            if (first == last)
                throw new ValidationException("VCP-TARGET-VISIBILITY", "대상 행·열의 숨김 상태를 확인할 수 없습니다. 변경된 셀은 없습니다.");
            int middle = first + (last - first) / 2;
            int found = FindVisibleAxisEndCore(first, middle, ref remaining, hidden);
            return found != 0 ? found : FindVisibleAxisEndCore(middle + 1, last, ref remaining, hidden);
        }

        public static PastePlan Build(ClipboardSnapshot source, SelectionSnapshot selection)
        {
            ValidateSelectionShape(selection);
            ValidateSource(source);
            var targets = new List<TargetCell>(selection.VisibleTargets);
            targets.Sort(delegate(TargetCell a, TargetCell b) {
                if (a == null) return b == null ? 0 : -1;
                if (b == null) return 1;
                int rowOrder = a.Row.CompareTo(b.Row);
                return rowOrder == 0 ? a.Column.CompareTo(b.Column) : rowOrder;
            });
            var visibleRows = new HashSet<int>();
            var visibleColumns = new HashSet<int>();
            TargetCell previous = null;
            foreach (TargetCell cell in targets)
            {
                if (cell == null || cell.SheetKey != selection.SheetKey || cell.Column < selection.FirstColumn || cell.Column > selection.LastColumn ||
                    cell.Row < selection.FirstRow || cell.Row > selection.LastRow || cell.Hidden ||
                    (previous != null && cell.Row == previous.Row && cell.Column == previous.Column))
                    throw new ValidationException("VCP-TARGET-BOUNDARY", "가시 셀에 중복·숨김 또는 선택 밖 주소가 있습니다. 변경된 셀은 없습니다.");
                visibleRows.Add(cell.Row); visibleColumns.Add(cell.Column); previous = cell;
            }
            if (targets.Count == 0)
                throw new ValidationException("VCP-TARGET-EMPTY", "선택 범위에 보이는 칸이 없습니다. 변경된 셀은 없습니다.");
            if ((long)visibleRows.Count * visibleColumns.Count != targets.Count)
                throw new ValidationException("VCP-TARGET-GRID", "선택 범위의 보이는 칸이 직사각형 행·열 구성을 이루지 않습니다. 변경된 셀은 없습니다.");
            if (targets.Count != source.Items.Count)
                throw new ValidationException("VCP-COUNT-MISMATCH", "붙여넣을 수 없습니다.\n복사한 항목: " + source.Items.Count + "개\n선택한 범위의 보이는 칸: " + targets.Count + "개\n변경된 셀은 없습니다.");
            bool legacyRowToColumn = !selection.IsAnchorExpansion && source.SourceRows == 1 && visibleColumns.Count == 1;
            if (!legacyRowToColumn && (source.SourceRows != visibleRows.Count || source.SourceColumns != visibleColumns.Count))
                throw new ValidationException("VCP-SHAPE-MISMATCH", "붙여넣을 수 없습니다.\n복사한 영역: " + source.SourceRows + "행 × " + source.SourceColumns + "열\n선택한 범위의 보이는 영역: " + visibleRows.Count + "행 × " + visibleColumns.Count + "열\n변경된 셀은 없습니다.");
            var segments = new List<PasteSegment>();
            bool horizontal = visibleColumns.Count > 1;
            int start = 0;
            for (int index = 1; index <= targets.Count; index++)
            {
                bool consecutive = index < targets.Count && (horizontal
                    ? targets[index].Row == targets[index - 1].Row && targets[index].Column == targets[index - 1].Column + 1
                    : targets[index].Column == targets[index - 1].Column && targets[index].Row == targets[index - 1].Row + 1);
                if (!consecutive)
                {
                    segments.Add(new PasteSegment(start, index - start, targets[start].Row, targets[start].Column, horizontal));
                    if (segments.Count > Limits.MaxSegments)
                        throw new ValidationException("VCP-SEGMENT-LIMIT", "보이는 연속 구간은 최대 20,000개입니다. 변경된 셀은 없습니다.");
                    start = index;
                }
            }
            return new PastePlan(source, selection, targets, segments);
        }
    }
}
