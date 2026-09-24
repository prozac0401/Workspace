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
                selection.FirstRow > selection.LastRow || selection.FirstColumn < 1 || selection.FirstColumn > Limits.ExcelColumns)
                throw new ValidationException("VCP-TARGET-BOUNDARY", "대상 선택 범위를 확인할 수 없습니다. 변경된 셀은 없습니다.");
            if (selection.AreaCount != 1 || selection.ColumnCount != 1 || selection.GroupedSheets)
                throw new ValidationException("VCP-TARGET-SHAPE", "한 워크시트에서 연속된 한 열 범위를 선택해 주세요. 변경된 셀은 없습니다.");
            if (selection.CellCount != (long)selection.LastRow - selection.FirstRow + 1)
                throw new ValidationException("VCP-TARGET-COUNT", "대상 선택 크기가 일치하지 않습니다. 변경된 셀은 없습니다.");
            if (selection.FirstRow == 1 && selection.LastRow == Limits.ExcelRows)
                throw new ValidationException("VCP-TARGET-WHOLE", "전체 행·열은 지원하지 않습니다. 필요한 범위만 선택해 주세요. 변경된 셀은 없습니다.");
            if (selection.CellCount > Limits.MaxSelectionCells)
                throw new ValidationException("VCP-TARGET-SCAN-LIMIT", "선택 범위는 최대 200,000칸입니다. 변경된 셀은 없습니다.");
            if (selection.ColumnHidden)
                throw new ValidationException("VCP-TARGET-HIDDEN-COLUMN", "숨긴 열에는 붙여넣을 수 없습니다. 변경된 셀은 없습니다.");
        }

        public static PastePlan Build(ClipboardSnapshot source, SelectionSnapshot selection)
        {
            if (source == null) throw new ArgumentNullException("source");
            ValidateSelectionShape(selection);
            if (!source.ShapeIsVerified || source.SourceRows < 1 || source.SourceColumns < 1 ||
                (source.SourceRows != 1 && source.SourceColumns != 1) ||
                (long)source.SourceRows * source.SourceColumns != source.Items.Count)
                throw new ValidationException("VCP-SOURCE-SHAPE", "복사한 셀의 개수 또는 데이터 형식을 정확히 확인할 수 없습니다. 변경된 셀은 없습니다.");
            if (source.Items.Count > Limits.MaxItems)
                throw new ValidationException("VCP-SOURCE-LIMIT", "복사 항목은 최대 50,000개입니다. 변경된 셀은 없습니다.");
            var targets = new List<TargetCell>(selection.VisibleTargets);
            targets.Sort(delegate(TargetCell a, TargetCell b) { return a == null ? -1 : (b == null ? 1 : a.Row.CompareTo(b.Row)); });
            int previousRow = 0;
            foreach (TargetCell cell in targets)
            {
                if (cell == null || cell.SheetKey != selection.SheetKey || cell.Column != selection.FirstColumn ||
                    cell.Row < selection.FirstRow || cell.Row > selection.LastRow || cell.Hidden || cell.Row == previousRow)
                    throw new ValidationException("VCP-TARGET-BOUNDARY", "가시 셀에 중복·숨김 또는 선택 밖 주소가 있습니다. 변경된 셀은 없습니다.");
                previousRow = cell.Row;
            }
            if (targets.Count == 0)
                throw new ValidationException("VCP-TARGET-EMPTY", "선택 범위에 보이는 칸이 없습니다. 변경된 셀은 없습니다.");
            if (targets.Count != source.Items.Count)
                throw new ValidationException("VCP-COUNT-MISMATCH", "붙여넣을 수 없습니다.\n복사한 항목: " + source.Items.Count + "개\n선택한 범위의 보이는 칸: " + targets.Count + "개\n변경된 셀은 없습니다.");
            var segments = new List<PasteSegment>();
            int start = 0;
            for (int index = 1; index <= targets.Count; index++)
            {
                if (index == targets.Count || targets[index].Row != targets[index - 1].Row + 1)
                {
                    segments.Add(new PasteSegment(start, index - start, targets[start].Row, targets[start].Column));
                    if (segments.Count > Limits.MaxSegments)
                        throw new ValidationException("VCP-SEGMENT-LIMIT", "보이는 연속 구간은 최대 20,000개입니다. 변경된 셀은 없습니다.");
                    start = index;
                }
            }
            return new PastePlan(source, selection, targets, segments);
        }
    }
}
