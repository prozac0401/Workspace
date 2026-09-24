using System;
using System.Collections.Generic;

namespace ExcelSelectionExport
{
    // Pure coordinate planning: no Excel object, file, clipboard or source mutation.
    public sealed class VisibleRangePlan
    {
        public const long MaximumInputCells = 1000000;
        public const long MaximumOutputCells = 100000;
        readonly int sourceRow, sourceColumn, rowCount, columnCount;
        public int[] Rows { get; private set; }
        public int[] Columns { get; private set; }
        public long CellCount { get { return (long)Rows.Length * Columns.Length; } }

        VisibleRangePlan(int row, int column, int height, int width, int[] rows, int[] columns)
        {
            sourceRow = row; sourceColumn = column; rowCount = height; columnCount = width;
            Rows = rows; Columns = columns;
        }

        public static VisibleRangePlan Create(int sourceRow, int sourceColumn, int rowCount, int columnCount,
            IList<int> visibleRows, IList<int> visibleColumns)
        {
            if (sourceRow < 1 || sourceColumn < 1 || rowCount < 1 || columnCount < 1 ||
                (long)sourceRow + rowCount - 1 > 1048576 || (long)sourceColumn + columnCount - 1 > 16384)
                throw new InvalidOperationException("선택 범위의 행 또는 열 좌표가 올바르지 않습니다.");
            if (rowCount == 1048576 || columnCount == 16384)
                throw new InvalidOperationException("전체 행이나 열 대신 내보낼 셀 범위를 유한하게 선택해 주세요.");
            if ((long)rowCount * columnCount > MaximumInputCells)
                throw new InvalidOperationException("선택 범위는 숨긴 셀을 포함하여 1,000,000개 셀 위치 이내로 선택해 주세요.");
            int[] rows = ValidateIndices(visibleRows, sourceRow, rowCount, "행");
            int[] columns = ValidateIndices(visibleColumns, sourceColumn, columnCount, "열");
            if ((long)rows.Length * columns.Length > MaximumOutputCells)
                throw new InvalidOperationException("보이는 셀이 100,000개를 넘습니다. 내보낼 범위를 나누어 선택해 주세요.");
            return new VisibleRangePlan(sourceRow, sourceColumn, rowCount, columnCount, rows, columns);
        }
        static int[] ValidateIndices(IList<int> indices, int start, int length, string label)
        {
            if (indices == null || indices.Count == 0)
                throw new InvalidOperationException("선택 범위에 보이는 " + label + "이 없습니다.");
            if (indices.Count > length) throw new InvalidOperationException("보이는 " + label + "의 좌표 수가 선택 범위를 벗어났습니다.");
            int[] result = new int[indices.Count];
            for (int i = 0; i < indices.Count; i++)
            {
                int value = indices[i];
                if (value < start || (long)value >= (long)start + length || (i > 0 && value <= result[i - 1]))
                    throw new InvalidOperationException("보이는 " + label + "의 순서 또는 좌표가 올바르지 않습니다.");
                result[i] = value;
            }
            return result;
        }
        public int OutputRow(int absolute) { return Find(Rows, absolute, "행"); }
        public int OutputColumn(int absolute) { return Find(Columns, absolute, "열"); }
        static int Find(int[] indices, int absolute, string label)
        {
            int position = Array.BinarySearch(indices, absolute);
            if (position < 0) throw new InvalidOperationException("결과에 포함되지 않는 " + label + " 좌표입니다.");
            return position + 1;
        }
        public void ValidateMerge(int row, int column, int rows, int columns)
        {
            if (rows < 1 || columns < 1 || row < sourceRow || column < sourceColumn ||
                (long)row + rows > (long)sourceRow + rowCount ||
                (long)column + columns > (long)sourceColumn + columnCount)
                throw new InvalidOperationException("병합 셀이 선택 범위에 일부만 포함되어 있습니다. 병합 전체가 포함되도록 선택해 주세요.");
            int firstRow = Array.BinarySearch(Rows, row);
            int lastRow = Array.BinarySearch(Rows, checked(row + rows - 1));
            int firstColumn = Array.BinarySearch(Columns, column);
            int lastColumn = Array.BinarySearch(Columns, checked(column + columns - 1));
            if (firstRow < 0 || lastRow < 0 || firstColumn < 0 || lastColumn < 0 ||
                lastRow - firstRow + 1 != rows || lastColumn - firstColumn + 1 != columns)
                throw new InvalidOperationException("병합 셀의 일부 행이나 열이 숨겨져 있습니다. 병합 전체가 보이는 범위를 선택해 주세요.");
        }
    }
}
