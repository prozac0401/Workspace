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
    public readonly Dictionary<int, SnapshotFakeCell> Data = new Dictionary<int, SnapshotFakeCell>();
    public readonly List<string> RangesRead = new List<string>();
    public int CellReads, PropertyReads, LowerBound = 1;
    public bool LegacyFormula;
    public SnapshotFakeRanges Range { get { return new SnapshotFakeRanges(this); } }
    public SnapshotFakeCells Cells { get { return new SnapshotFakeCells(this); } }
}
public sealed class SnapshotFakeCells
{
    readonly SnapshotFakeSheet sheet;
    public SnapshotFakeCells(SnapshotFakeSheet sheet) { this.sheet = sheet; }
    public SnapshotFakeCell this[int row, int col] { get { sheet.CellReads++; return sheet.Data[row]; } }
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
            Match match = Regex.Match(address, @"^\$[A-Z]+\$(\d+):\$[A-Z]+\$(\d+)$");
            if (!match.Success) throw new Exception("Bad range address");
            return new SnapshotFakeRange(sheet, Int32.Parse(match.Groups[1].Value), Int32.Parse(match.Groups[2].Value));
        }
    }
}
public sealed class SnapshotFakeRange
{
    readonly SnapshotFakeSheet sheet; readonly int first, count;
    public SnapshotFakeRange(SnapshotFakeSheet sheet, int first, int last) { this.sheet=sheet; this.first=first; count=last-first+1; }
    public object HasFormula { get { sheet.PropertyReads++; var flags=Enumerable.Range(first,count).Select(r=>sheet.Data[r].HasFormula).Distinct().ToArray(); return flags.Length==1 ? (object)flags[0] : DBNull.Value; } }
    public object NumberFormat { get { sheet.PropertyReads++; var formats=Enumerable.Range(first,count).Select(r=>sheet.Data[r].NumberFormat).Distinct().ToArray(); return formats.Length==1 ? formats[0] : DBNull.Value; } }
    public object Value2 { get { sheet.PropertyReads++; return Values(false); } }
    public object Formula2 { get { sheet.PropertyReads++; if(sheet.LegacyFormula)throw new COMException("Unsupported Formula2");return Values(true); } }
    public object Formula { get { sheet.PropertyReads++; return Values(true); } }
    object Values(bool formula)
    {
        if(count==1)return formula?sheet.Data[first].Formula2:sheet.Data[first].Value2;
        Array values=Array.CreateInstance(typeof(object),new[]{count,1},new[]{sheet.LowerBound,sheet.LowerBound});
        for(int i=0;i<count;i++)values.SetValue(formula?sheet.Data[first+i].Formula2:sheet.Data[first+i].Value2,i+sheet.LowerBound,sheet.LowerBound);
        return values;
    }
}
internal static class CellSnapshotReaderTests
{
    static int passed, failed;
    static void Check(bool condition,string message){if(!condition)throw new Exception(message);}
    static void Test(string name,Action action){try{action();passed++;Console.WriteLine("PASS "+name);}catch(Exception e){failed++;Console.WriteLine("FAIL "+name+": "+e);}}
    static PastePlan Plan(int[] rows,int column)
    {
        var source=new ClipboardSnapshot("unit",1,rows.Length,1,true,rows.Select(r=>CellValue.Empty()),"");
        var selection=new SelectionSnapshot("sheet",rows.Min(),rows.Max(),column,1,rows.Max()-rows.Min()+1,1,false,false,rows.Select(r=>new TargetCell("sheet",r,column,false)));
        return Planner.Build(source,selection);
    }
    static SnapshotFakeSheet Sheet(int[] rows)
    {
        var sheet=new SnapshotFakeSheet();
        foreach(int row in rows)sheet.Data[row]=new SnapshotFakeCell{Address="$E$"+row,Value2=(double)row,NumberFormat="0.00"};
        return sheet;
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
        Test("last Excel column produces XFD absolute addresses",delegate{int[] rows={2,3};var sheet=Sheet(rows);var cells=CellSnapshotReader.Capture(sheet,Plan(rows,16384));Check(cells[0].Address=="$XFD$2"&&sheet.RangesRead[0]=="$XFD$2:$XFD$3","column address");});
        Console.WriteLine("RESULT: "+passed+" passed; "+failed+" failed");return failed==0?0:1;
    }
}
