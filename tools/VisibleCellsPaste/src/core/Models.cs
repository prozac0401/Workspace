using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;

namespace VisibleCellsPaste
{
    public static class Limits
    {
        public const int MaxItems = 50000;
        public const int MaxSelectionCells = 200000;
        public const int MaxPayloadBytes = 32 * 1024 * 1024;
        public const int MaxSegments = 20000;
        public const int WarnItems = 5000;
        public const int WarnSegments = 1000;
        public const int ExcelRows = 1048576;
        public const int ExcelColumns = 16384;
    }

    public sealed class ValidationException : Exception
    {
        public string Code { get; private set; }
        public string UserMessage { get { return Message; } }
        public ValidationException(string code, string message) : base(message) { Code = code; }
        public ValidationException(string code, string message, Exception inner) : base(message, inner) { Code = code; }
    }

    public enum CellValueKind { Empty, String, Number, Boolean, Error }

    public sealed class CellValue : IEquatable<CellValue>
    {
        public CellValueKind Kind { get; private set; }
        public object Value { get; private set; }
        public int ErrorCode { get { return Kind == CellValueKind.Error ? (int)Value : 0; } }
        private CellValue(CellValueKind kind, object value) { Kind = kind; Value = value; }
        public static CellValue Empty() { return new CellValue(CellValueKind.Empty, null); }
        public static CellValue Text(string value) { if (value == null) throw new ArgumentNullException("value"); return new CellValue(CellValueKind.String, value); }
        public static CellValue Number(double value)
        {
            if (Double.IsNaN(value) || Double.IsInfinity(value)) throw new ValidationException("VCP-SOURCE-NUMBER", "유효하지 않은 숫자입니다. 변경된 셀은 없습니다.");
            return new CellValue(CellValueKind.Number, value);
        }
        public static CellValue Boolean(bool value) { return new CellValue(CellValueKind.Boolean, value); }
        public static CellValue Error(int value) { return new CellValue(CellValueKind.Error, value); }
        public bool Equals(CellValue other) { return other != null && Kind == other.Kind && Object.Equals(Value, other.Value); }
        public override bool Equals(object other) { return Equals(other as CellValue); }
        public override int GetHashCode() { return ((int)Kind * 397) ^ (Value == null ? 0 : Value.GetHashCode()); }
    }

    public sealed class ClipboardSnapshot
    {
        public string CaptureId { get; private set; }
        public string SourceFormat { get; private set; }
        public uint ClipboardSequence { get; private set; }
        public int SourceRows { get; private set; }
        public int SourceColumns { get; private set; }
        public bool ShapeIsVerified { get; private set; }
        public ReadOnlyCollection<CellValue> Items { get; private set; }
        public string Evidence { get; private set; }
        public ClipboardSnapshot(string sourceFormat, uint sequence, int rows, int columns, bool verified, IEnumerable<CellValue> items, string evidence)
        {
            if (items == null) throw new ArgumentNullException("items");
            var copy = new List<CellValue>();
            foreach (CellValue item in items)
            {
                if (item == null) throw new ArgumentException("Null cell item.");
                if (copy.Count == Limits.MaxItems) throw new ValidationException("VCP-SOURCE-LIMIT", "복사 항목은 최대 50,000개입니다. 변경된 셀은 없습니다.");
                copy.Add(item);
            }
            CaptureId = Guid.NewGuid().ToString("N"); SourceFormat = sourceFormat; ClipboardSequence = sequence;
            SourceRows = rows; SourceColumns = columns; ShapeIsVerified = verified;
            Items = copy.AsReadOnly(); Evidence = evidence ?? "";
        }
    }

    public sealed class TargetCell
    {
        public string SheetKey { get; private set; }
        public int Row { get; private set; }
        public int Column { get; private set; }
        public bool Hidden { get; private set; }
        public TargetCell(string sheetKey, int row, int column, bool hidden)
        { SheetKey = sheetKey; Row = row; Column = column; Hidden = hidden; }
    }

    // Excel COM validation (protection, merge, spill, table and validation rules) stays in the adapter.
    public sealed class SelectionSnapshot
    {
        public string SheetKey { get; private set; }
        public int FirstRow { get; private set; }
        public int LastRow { get; private set; }
        public int FirstColumn { get; private set; }
        public int ColumnCount { get; private set; }
        public long CellCount { get; private set; }
        public int AreaCount { get; private set; }
        public bool ColumnHidden { get; private set; }
        public bool GroupedSheets { get; private set; }
        public ReadOnlyCollection<TargetCell> VisibleTargets { get; private set; }
        public SelectionSnapshot(string sheetKey, int firstRow, int lastRow, int firstColumn, int columnCount,
            long cellCount, int areaCount, bool columnHidden, bool groupedSheets, IEnumerable<TargetCell> targets)
        {
            SheetKey = sheetKey; FirstRow = firstRow; LastRow = lastRow; FirstColumn = firstColumn;
            ColumnCount = columnCount; CellCount = cellCount; AreaCount = areaCount;
            ColumnHidden = columnHidden; GroupedSheets = groupedSheets;
            var copy = new List<TargetCell>();
            if (targets == null) throw new ArgumentNullException("targets");
            foreach (TargetCell target in targets)
            {
                if (copy.Count == Limits.MaxItems) throw new ValidationException("VCP-TARGET-LIMIT", "보이는 대상은 최대 50,000칸입니다. 변경된 셀은 없습니다.");
                copy.Add(target);
            }
            VisibleTargets = copy.AsReadOnly();
        }
    }

    public sealed class PasteSegment
    {
        public int StartIndex { get; private set; }
        public int Count { get; private set; }
        public int FirstRow { get; private set; }
        public int LastRow { get { return FirstRow + Count - 1; } }
        public int Column { get; private set; }
        public PasteSegment(int start, int count, int row, int column) { StartIndex = start; Count = count; FirstRow = row; Column = column; }
    }

    public sealed class PastePlan
    {
        public ClipboardSnapshot Source { get; private set; }
        public SelectionSnapshot Selection { get; private set; }
        public ReadOnlyCollection<TargetCell> Targets { get; private set; }
        public ReadOnlyCollection<PasteSegment> Segments { get; private set; }
        public bool RequiresSizeConfirmation { get { return Targets.Count >= Limits.WarnItems || Segments.Count >= Limits.WarnSegments; } }
        internal PastePlan(ClipboardSnapshot source, SelectionSnapshot selection, List<TargetCell> targets, List<PasteSegment> segments)
        { Source = source; Selection = selection; Targets = targets.AsReadOnly(); Segments = segments.AsReadOnly(); }
    }
}
