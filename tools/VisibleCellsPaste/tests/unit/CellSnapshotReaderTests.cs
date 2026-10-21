using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using VisibleCellsPaste;

public sealed class SnapshotFakeCell
{
    public object Value2 { get; set; }
    public object NumberFormat { get; set; }
    public bool HasFormula { get; set; }
    public string Address { get; set; }
    public object Formula2 { get; set; }
    public object Formula { get { return Formula2; } }
}
public sealed class SnapshotFakeSheet
{
    // Row-only aliases keep the original vertical cases concise; reads always use both coordinates.
    public readonly Dictionary<int, SnapshotFakeCell> Data = new Dictionary<int, SnapshotFakeCell>();
    public readonly Dictionary<string, SnapshotFakeCell> Grid = new Dictionary<string, SnapshotFakeCell>();
    public readonly List<string> RangesRead = new List<string>();
    public int CellReads, PropertyReads, LowerBound = 1;
    public bool LegacyFormula, TransposeArrays;
    public SnapshotFakeCell At(int row, int column) { return Grid[row + ":" + column]; }
    public SnapshotFakeRanges Range { get { return new SnapshotFakeRanges(this); } }
    public SnapshotFakeCells Cells { get { return new SnapshotFakeCells(this); } }
}
public sealed class SnapshotFakeCells
{
    readonly SnapshotFakeSheet sheet;
    public SnapshotFakeCells(SnapshotFakeSheet sheet) { this.sheet = sheet; }
    public SnapshotFakeCell this[int row, int col] { get { sheet.CellReads++; return sheet.At(row,col); } }
}
public sealed class SnapshotFakeRanges
{
    readonly SnapshotFakeSheet sheet;
    public SnapshotFakeRanges(SnapshotFakeSheet sheet) { this.sheet = sheet; }
    public SnapshotFakeRange this[string address]
    {
        get
        {
            sheet.RangesRead.Add(address);
            Match match = Regex.Match(address, @"^\$([A-Z]+)\$(\d+):\$([A-Z]+)\$(\d+)$");
            if (!match.Success) throw new Exception("Bad range address");
            return new SnapshotFakeRange(sheet, Int32.Parse(match.Groups[2].Value), Int32.Parse(match.Groups[4].Value),
                ColumnNumber(match.Groups[1].Value),ColumnNumber(match.Groups[3].Value));
        }
    }
    static int ColumnNumber(string letters) { int column=0;foreach(char letter in letters)column=column*26+letter-'A'+1;return column; }
}
public sealed class SnapshotFakeRange
{
    readonly SnapshotFakeSheet sheet; readonly int firstRow, firstColumn, rows, columns;
    public SnapshotFakeRange(SnapshotFakeSheet sheet, int first, int last, int firstColumn, int lastColumn)
    { this.sheet=sheet; firstRow=first; this.firstColumn=firstColumn; rows=last-first+1; columns=lastColumn-firstColumn+1; }
    IEnumerable<SnapshotFakeCell> Cells { get { return Enumerable.Range(firstRow,rows).SelectMany(row=>Enumerable.Range(firstColumn,columns).Select(column=>sheet.At(row,column))); } }
    public object HasFormula { get { sheet.PropertyReads++; var flags=Cells.Select(c=>c.HasFormula).Distinct().ToArray(); return flags.Length==1 ? (object)flags[0] : DBNull.Value; } }
    public object NumberFormat { get { sheet.PropertyReads++; var formats=Cells.Select(c=>c.NumberFormat).Distinct().ToArray(); return formats.Length==1 ? formats[0] : DBNull.Value; } }
    public object Value2 { get { sheet.PropertyReads++; return Values(false); } }
    public object Formula2 { get { sheet.PropertyReads++; if(sheet.LegacyFormula)throw new COMException("Unsupported Formula2");return Values(true); } }
    public object Formula { get { sheet.PropertyReads++; return Values(true); } }
    object Values(bool formula)
    {
        if(rows*columns==1)return formula?sheet.At(firstRow,firstColumn).Formula2:sheet.At(firstRow,firstColumn).Value2;
        Array values=Array.CreateInstance(typeof(object),sheet.TransposeArrays?new[]{columns,rows}:new[]{rows,columns},new[]{sheet.LowerBound,sheet.LowerBound});
        for(int row=0;row<rows;row++)for(int column=0;column<columns;column++) {
            var cell=sheet.At(firstRow+row,firstColumn+column);
            values.SetValue(formula?cell.Formula2:cell.Value2,(sheet.TransposeArrays?column:row)+sheet.LowerBound,(sheet.TransposeArrays?row:column)+sheet.LowerBound);
        }
        return values;
    }
}
internal static class CellSnapshotReaderTests
{
    static int passed, failed;
    static void Check(bool condition,string message){if(!condition)throw new Exception(message);}
    static void Test(string name,Action action){try{action();passed++;Console.WriteLine("PASS "+name);}catch(Exception e){failed++;Console.WriteLine("FAIL "+name+": "+e);}}
    static string Letters(int column) { string text="";while(column>0){column--;text=(char)('A'+column%26)+text;column/=26;}return text; }
    static PastePlan Plan(int[] rows,int column)
    {
        var source=new ClipboardSnapshot("unit",1,rows.Length,1,true,rows.Select(r=>CellValue.Empty()),"");
        var selection=new SelectionSnapshot("sheet",rows.Min(),rows.Max(),column,1,rows.Max()-rows.Min()+1,1,false,false,rows.Select(r=>new TargetCell("sheet",r,column,false)));
        return Planner.Build(source,selection);
    }
    static PastePlan RectanglePlan(int[] rows,int[] columns)
    {
        var targets=rows.SelectMany(row=>columns.Select(column=>new TargetCell("sheet",row,column,false)));
        var source=new ClipboardSnapshot("unit",1,rows.Length,columns.Length,true,targets.Select(t=>CellValue.Empty()),"");
        var selection=new SelectionSnapshot("sheet",rows.Min(),rows.Max(),columns.Min(),columns.Max()-columns.Min()+1,
            (long)(rows.Max()-rows.Min()+1)*(columns.Max()-columns.Min()+1),1,false,false,targets);
        return Planner.Build(source,selection);
    }
    static SnapshotFakeSheet Sheet(int[] rows,int column=5)
    {
        var sheet=new SnapshotFakeSheet();
        foreach(int row in rows) {
            sheet.Data[row]=new SnapshotFakeCell{Address="$"+Letters(column)+"$"+row,Value2=(double)row,NumberFormat="0.00"};
            sheet.Grid[row+":"+column]=sheet.Data[row];
        }
        return sheet;
    }
    static SnapshotFakeSheet RectangleSheet(int[] rows,int[] columns)
    {
        var sheet=new SnapshotFakeSheet();
        foreach(int row in rows)foreach(int column in columns)
            sheet.Grid[row+":"+column]=new SnapshotFakeCell{Address="$"+Letters(column)+"$"+row,Value2=(double)(row*100+column),NumberFormat="0.00"};
        return sheet;
    }
    static void RejectBeforeReading(SnapshotFakeSheet sheet,PastePlan plan)
    {
        try { CellSnapshotReader.Capture(sheet,plan); }
        catch(ValidationException error) {
            Check(error.Code=="VCP-SNAPSHOT-BOUNDARY","rejection code");
            Check(sheet.CellReads==0&&sheet.PropertyReads==0&&sheet.RangesRead.Count==0,"invalid plan read worksheet");return;
        }
        throw new Exception("Invalid plan was accepted");
    }
    static int Main()
    {
        Test("uniform constant segments 1-based array no per-cell reads",delegate{
            int[] rows={2,3,5,6};var sheet=Sheet(rows);sheet.Data[2].Value2="00123";sheet.Data[3].Value2=null;sheet.Data[5].Value2=true;
            var cells=CellSnapshotReader.Capture(sheet,Plan(rows,5));
            Check(cells.Length==4&&cells[0].Value.Equals(CellValue.Text("00123"))&&cells[1].Value.Kind==CellValueKind.Empty&&cells[2].Value.Equals(CellValue.Boolean(true)),"typed values");
            Check(sheet.CellReads==0&&sheet.PropertyReads==6,"expected three bulk reads per segment");
            Check(sheet.RangesRead.SequenceEqual(new[]{"$E$2:$E$3","$E$5:$E$6"}),"must never bridge hidden row4");
            Check(cells.Select(c=>c.Address).SequenceEqual(new[]{"$E$2","$E$3","$E$5","$E$6"}),"addresses");
        });
        Test("zero-based bulk arrays retain positions",delegate{int[] rows={2,3,4};var sheet=Sheet(rows);sheet.LowerBound=0;var cells=CellSnapshotReader.Capture(sheet,Plan(rows,5));Check(cells[0].Value.Equals(CellValue.Number(2))&&cells[2].Value.Equals(CellValue.Number(4))&&sheet.CellReads==0,"zero bounds");});
        Test("single-cell scalar and null retained",delegate{int[] rows={2};var sheet=Sheet(rows);sheet.Data[2].Value2=null;var cells=CellSnapshotReader.Capture(sheet,Plan(rows,5));Check(cells[0].Value.Kind==CellValueKind.Empty&&sheet.CellReads==0,"scalar empty");});
        Test("uniform formulas bulk preserve Formula2 and cached typed values",delegate{
            int[] rows={2,3,4};var sheet=Sheet(rows);foreach(int row in rows){sheet.Data[row].HasFormula=true;sheet.Data[row].Formula2="=ROW()";}
            sheet.Data[3].Value2="";sheet.Data[4].Value2=new ErrorWrapper(unchecked((int)0x800A07FA));
            var cells=CellSnapshotReader.Capture(sheet,Plan(rows,5));
            Check(cells.All(c=>c.Formula&&c.FormulaProperty=="Formula2"&&Object.Equals(c.FormulaValue,"=ROW()")),"formula definitions");
            Check(cells[1].Value.Equals(CellValue.Text(""))&&cells[2].Value.Equals(CellValue.Error(2042))&&sheet.CellReads==0,"cached typed values");
        });
        Test("legacy Formula fallback retains selected property",delegate{int[] rows={2,3};var sheet=Sheet(rows);sheet.LegacyFormula=true;foreach(int row in rows){sheet.Data[row].HasFormula=true;sheet.Data[row].Formula2="=1+1";}var cells=CellSnapshotReader.Capture(sheet,Plan(rows,5));Check(cells.All(c=>c.FormulaProperty=="Formula")&&sheet.CellReads==0,"legacy formulas");});
        Test("mixed formula range uses per-cell safe fallback",delegate{int[] rows={2,3};var sheet=Sheet(rows);sheet.Data[2].HasFormula=true;sheet.Data[2].Formula2="=1+1";var cells=CellSnapshotReader.Capture(sheet,Plan(rows,5));Check(cells[0].Formula&&!cells[1].Formula&&sheet.CellReads==2,"mixed formulas");});
        Test("mixed number formats preserve individual exact values",delegate{int[] rows={2,3};var sheet=Sheet(rows);sheet.Data[2].NumberFormat="@";var cells=CellSnapshotReader.Capture(sheet,Plan(rows,5));Check(Object.Equals(cells[0].Format,"@")&&Object.Equals(cells[1].Format,"0.00")&&sheet.CellReads==2,"mixed formats");});
        Test("last Excel column produces XFD absolute addresses",delegate{int[] rows={2,3};var sheet=Sheet(rows,16384);var cells=CellSnapshotReader.Capture(sheet,Plan(rows,16384));Check(cells[0].Address=="$XFD$2"&&sheet.RangesRead[0]=="$XFD$2:$XFD$3","column address");});
        Test("horizontal typed values and blank retain column positions",delegate{
            int[] rows={4};int[] columns={3,4,5,6};var sheet=RectangleSheet(rows,columns);
            sheet.At(4,3).Value2="00123";sheet.At(4,4).Value2=null;sheet.At(4,5).Value2=true;sheet.At(4,6).Value2=new ErrorWrapper(unchecked((int)0x800A07FA));
            var cells=CellSnapshotReader.Capture(sheet,RectanglePlan(rows,columns));
            Check(cells[0].Value.Equals(CellValue.Text("00123"))&&cells[1].Value.Kind==CellValueKind.Empty&&cells[2].Value.Equals(CellValue.Boolean(true))&&cells[3].Value.Equals(CellValue.Error(2042)),"horizontal types");
            Check(cells.Select(c=>c.Address).SequenceEqual(new[]{"$C$4","$D$4","$E$4","$F$4"})&&sheet.CellReads==0,"horizontal address mapping");
            Check(sheet.RangesRead.SequenceEqual(new[]{"$C$4:$F$4"}),"horizontal bulk range");
        });
        Test("horizontal formula arrays keep cached results and individual definitions",delegate{
            int[] rows={2,5};int[] columns={5,6};var sheet=RectangleSheet(rows,columns);sheet.LowerBound=0;
            foreach(var cell in sheet.Grid.Values){cell.HasFormula=true;cell.Formula2="=ROW()+COLUMN()";}
            sheet.At(2,6).Formula2="=\"\"";sheet.At(2,6).Value2="";
            var cells=CellSnapshotReader.Capture(sheet,RectanglePlan(rows,columns));
            Check(cells.All(c=>c.Formula&&c.FormulaProperty=="Formula2")&&Object.Equals(cells[1].FormulaValue,"=\"\"")&&cells[1].Value.Equals(CellValue.Text("")),"horizontal formulas");
            Check(sheet.CellReads==0&&cells[2].Value.Equals(CellValue.Number(505)),"row-major zero-based formula arrays");
        });
        Test("horizontal mixed formats and formulas use exact-cell fallback",delegate{
            int[] rows={2,4};int[] columns={5,6};var sheet=RectangleSheet(rows,columns);
            sheet.At(2,5).NumberFormat="@";sheet.At(4,6).HasFormula=true;sheet.At(4,6).Formula2="=1+1";
            var cells=CellSnapshotReader.Capture(sheet,RectanglePlan(rows,columns));
            Check(sheet.CellReads==4&&Object.Equals(cells[0].Format,"@")&&Object.Equals(cells[1].Format,"0.00"),"per-column format");
            Check(!cells[2].Formula&&cells[3].Formula&&Object.Equals(cells[3].FormulaValue,"=1+1"),"per-column formula");
        });
        Test("rectangular gaps read only exact visible rows and columns",delegate{
            int[] rows={3,7};int[] columns={2,3,6};var sheet=RectangleSheet(rows,columns);
            var cells=CellSnapshotReader.Capture(sheet,RectanglePlan(rows,columns));
            Check(sheet.RangesRead.SequenceEqual(new[]{"$B$3:$C$3","$F$3:$F$3","$B$7:$C$7","$F$7:$F$7"}),"hidden row or column range bridged");
            Check(cells.Select(c=>c.Value).SequenceEqual(new[]{302d,303d,306d,702d,703d,706d}.Select(CellValue.Number)),"rectangular source positions");
            Check(sheet.CellReads==0,"rectangle bulk reads");
        });
        Test("wrong bulk array orientation falls back without transposing values",delegate{
            int[] rows={2};int[] columns={5,6,7};var sheet=RectangleSheet(rows,columns);sheet.TransposeArrays=true;
            var cells=CellSnapshotReader.Capture(sheet,RectanglePlan(rows,columns));
            Check(sheet.CellReads==3&&cells.Select(c=>c.Value).SequenceEqual(new[]{205d,206d,207d}.Select(CellValue.Number)),"shape fallback");
        });
        Test("horizontal segment mutation rejected before touching worksheet",delegate{
            int[] rows={2};int[] columns={5,6};var sheet=RectangleSheet(rows,columns);var plan=RectanglePlan(rows,columns);
            typeof(PasteSegment).GetProperty("Horizontal").SetValue(plan.Segments[0],false,null);
            RejectBeforeReading(sheet,plan);
        });
        Test("hidden target mutation rejected before touching worksheet",delegate{
            int[] rows={2};int[] columns={5,6};var sheet=RectangleSheet(rows,columns);var plan=RectanglePlan(rows,columns);
            typeof(TargetCell).GetProperty("Hidden").SetValue(plan.Targets[1],true,null);
            RejectBeforeReading(sheet,plan);
        });
        Console.WriteLine("RESULT: "+passed+" passed; "+failed+" failed");return failed==0?0:1;
    }
}
