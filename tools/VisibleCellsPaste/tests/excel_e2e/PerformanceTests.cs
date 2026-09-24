using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using VisibleCellsPaste;

// Synthetic test-only benchmark. Direct engine measurements do not prove actual menu
// click, clipboard provenance or installation. Never opens, saves or closes a workbook.
class PerformanceTests
{
    static dynamic app, book;
    static string output;
    static readonly List<string> lines = new List<string>();
    static int passed, failed, sheetNumber;
    static void Log(string text) { lines.Add(text); File.WriteAllLines(output, lines, new UTF8Encoding(false)); Console.WriteLine(text); }
    static void Check(bool value, string why) { if (!value) throw new Exception(why); }
    static double Number(int index) { return index + 0.25; }
    static ClipboardSnapshot Source(int count)
    { return new ClipboardSnapshot("Synthetic-number-benchmark", 0, count, 1, true, Enumerable.Range(0,count).Select(i=>CellValue.Number(Number(i))), "Synthetic values; no clipboard read"); }
    static SelectionSnapshot Selection(int count, bool alternating)
    {
        int rows=alternating?2*count:count;
        return new SelectionSnapshot("synthetic-benchmark",2,rows+1,5,1,rows,1,false,false,
            Enumerable.Range(0,count).Select(i=>new TargetCell("synthetic-benchmark",2+(alternating?2*i:i),5,false)));
    }
    static void Model(int count, bool alternating)
    {
        string label="MODEL count="+count+" scenario="+(alternating?"alternating":"contiguous");
        var watch=Stopwatch.StartNew();
        try
        {
            var source=Source(count); var selection=Selection(count,alternating); watch.Restart();
            bool shouldReject=alternating&&count>Limits.MaxSegments;
            PastePlan plan=null;
            try { plan=Planner.Build(source,selection); }
            catch(ValidationException e) { if(!shouldReject||e.Code!="VCP-SEGMENT-LIMIT")throw; }
            watch.Stop();
            Check((plan==null)==shouldReject,"Expected model segment limit rejection");
            if(plan!=null) Check(plan.RequiresSizeConfirmation==(count>=Limits.WarnItems||(alternating&&count>=Limits.WarnSegments)),"Warning boundary");
            passed++; Log(label+" PASS planner_ms="+watch.Elapsed.TotalMilliseconds.ToString("F3",CultureInfo.InvariantCulture)+" expected_rejection="+shouldReject+" segments="+(plan==null?"over-limit":plan.Segments.Count.ToString())+" warning="+(plan==null?"n/a":plan.RequiresSizeConfirmation.ToString()));
        }
        catch(Exception e){failed++;Log(label+" FAIL "+e);}
    }
    static dynamic Fixture(int count, bool alternating)
    {
        int rows=alternating?2*count:count, last=rows+1;
        dynamic sheet=book.Worksheets.Add(Type.Missing,book.Worksheets[book.Worksheets.Count],1,-4167);
        sheet.Name="VCP_Perf_"+DateTime.UtcNow.ToString("HHmmss")+"_"+(++sheetNumber);
        bool events=app.EnableEvents, screen=app.ScreenUpdating;object calculation=app.Calculation,status=app.StatusBar;
        try
        {
            app.EnableEvents=false;app.ScreenUpdating=false;app.Calculation=-4135;
            sheet.Range["A1"].Value2="Visible";sheet.Range["E1"].Value2="Target";
            var flags=new object[rows,1]; for(int i=0;i<rows;i++)flags[i,0]=!alternating||i%2==0?1.0:0.0;
            sheet.Range["A2:A"+last].Value2=flags;
            sheet.Range["E2:E"+last].Value2=-777.0;sheet.Range["E2:E"+last].NumberFormat="0.00";
            sheet.Range["D2"].Value2="outside-sentinel";sheet.Range["F2"].Formula2="=E2*2";
            sheet.Range["E"+(last+1)].Value2=-123456.0;sheet.Range["E"+(last+1)].Font.Bold=true;
            if(alternating) { sheet.Range["E3"].Formula2="=9+9";sheet.Range["A1:E"+last].AutoFilter(1,"1"); }
            sheet.Range["E2:E"+last].Select();
        }
        finally {app.Calculation=calculation;app.ScreenUpdating=screen;app.StatusBar=status;app.EnableEvents=events;}
        Application.DoEvents();return sheet;
    }
    static void Sentinels(dynamic sheet,int count,bool alternating,bool rejected)
    {
        int last=(alternating?2*count:count)+1;
        foreach(int index in new[]{0,count/2,count-1}.Distinct())
        {
            int row=2+(alternating?2*index:index);
            CellState state=ExcelEngine.ReadCell((object)sheet,row,5);
            Check(!state.Formula&&state.Value.Kind==CellValueKind.Number&&Convert.ToDouble(state.Value.Value)==(rejected?-777.0:Number(index)),"Sampled target value "+index);
            Check((string)state.Format=="0.00","Sampled target format");
            Check(!(bool)sheet.Rows[row].Hidden,"Sampled target visibility");
        }
        Check((string)sheet.Range["D2"].Value2=="outside-sentinel","Outside constant");
        Check((string)sheet.Range["F2"].Formula2=="=E2*2","Outside formula definition");
        Check((string)sheet.Range["E1"].Value2=="Target","Selection upper boundary");
        Check((double)sheet.Range["E"+(last+1)].Value2==-123456.0&&(bool)sheet.Range["E"+(last+1)].Font.Bold,"Selection lower boundary");
        if(alternating)
        {
            Check((bool)sheet.Rows[3].Hidden&&(string)sheet.Range["E3"].Formula2=="=9+9","Hidden formula definition");
            if(count>1)Check((bool)sheet.Rows[last].Hidden&&(double)sheet.Range["E"+last].Value2==-777.0,"Hidden trailing constant");
        }
    }
    static void Real(int count,bool alternating)
    {
        string label="EXCEL count="+count+" scenario="+(alternating?"alternating-filter":"contiguous");
        dynamic sheet=null; long prepareMs=0;var setup=Stopwatch.StartNew();
        try
        {
            sheet=Fixture(count,alternating);setup.Stop();var source=Source(count);
            using(var engine=new ExcelEngine(app))
            {
                bool shouldReject=alternating&&count>Limits.MaxSegments;PreparedPaste prepared=null;
                Log(label+" START fixture_ms="+setup.ElapsedMilliseconds+" expectation="+(shouldReject?"VCP-SEGMENT-LIMIT":"success"));
                var timer=Stopwatch.StartNew();
                try { prepared=engine.Prepare(source); }
                catch(ValidationException e){if(!shouldReject||e.Code!="VCP-SEGMENT-LIMIT")throw;}
                timer.Stop();prepareMs=timer.ElapsedMilliseconds;
                Check((prepared==null)==shouldReject,"Expected segment-limit rejection");
                if(shouldReject){Sentinels(sheet,count,alternating,true);passed++;Log(label+" PASS rejected=VCP-SEGMENT-LIMIT prepare_ms="+prepareMs+" writes=0 sampled_targets_hidden_outside=PASS");return;}
                bool expectedWarning=count>=Limits.WarnItems||(alternating&&count>=Limits.WarnSegments);
                Check(prepared.Plan.RequiresSizeConfirmation==expectedWarning,"Size warning flag");
                int writeCallbacks=0;long firstWrite=-1,verify=-1;timer.Restart();
                engine.Apply(prepared,null,delegate(string progress){if(progress.StartsWith("쓰기 ",StringComparison.Ordinal)){if(firstWrite<0)firstWrite=timer.ElapsedMilliseconds;writeCallbacks++;}else if(progress=="검증 중")verify=timer.ElapsedMilliseconds;});
                timer.Stop();long apply=timer.ElapsedMilliseconds;
                Check(engine.LastOutcome=="success"&&engine.LastCount==count,"Engine committed item count");
                Check(writeCallbacks==(alternating?count:(count+511)/512),"Write-run count");
                var check=Stopwatch.StartNew();Sentinels(sheet,count,alternating,false);check.Stop();
                passed++;Log(label+" PASS prepare_ms="+prepareMs+" apply_total_ms="+apply+" apply_revalidate_before_first_write_ms="+firstWrite+" write_phase_ms="+(verify-firstWrite)+" verify_commit_restore_ms="+(apply-verify)+" sampled_check_ms="+check.ElapsedMilliseconds+" segments="+prepared.Plan.Segments.Count+" write_calls="+writeCallbacks+" warning_flag="+prepared.Plan.RequiresSizeConfirmation+" warning_dialog=NOT_RUN direct_engine=true sampled_targets_hidden_outside=PASS");
            }
        }
        catch(Exception e){failed++;Log(label+" FAIL prepare_ms="+prepareMs+" "+e);}
        finally { if(sheet!=null)ExcelEngine.Release((object)sheet); }
    }
    [STAThread]static int Main(string[] args)
    {
        if(args.Length<2){Console.Error.WriteLine("Usage: PerformanceTests.exe <owned-Excel-PID|model> <report-file> [100,1000,5000,50000] [both|contiguous|alternating]");return 2;}
        output=args[1];int[] sizes=(args.Length>2?args[2]:"100,1000,5000,50000").Split(',').Select(Int32.Parse).ToArray();
        if(sizes.Any(x=>x<1||x>Limits.MaxItems))throw new ArgumentException("Benchmark sizes must be 1..50000.");
        string scenarios=args.Length>3?args[3]:"both";if(scenarios!="both"&&scenarios!="contiguous"&&scenarios!="alternating")throw new ArgumentException("Unknown scenario.");
        bool[] patterns=scenarios=="both"?new[]{false,true}:new[]{scenarios=="alternating"};
        Log("Synthetic-only performance benchmark UTC="+DateTime.UtcNow.ToString("o")+" CLR="+Environment.Version+" OS_compatibility_api="+Environment.OSVersion+" process_bits="+(IntPtr.Size*8));
        Log("MEASUREMENT_CONTEXT: MODEL entries are pure managed planner timings without Excel calls. EXCEL entries are external test EXE -> Excel cross-process COM timing, NOT in-process installed-addin product speed. Do not extrapolate these timings to the installed add-in UI.");
        Log("Timing note: Prepare includes target inspection and backup; Apply includes revalidation, write, verification, undo commit and global-state restoration. Progress timestamps divide approximate phases. Warning flag is tested; dialog click and clipboard are not tested. Sentinel sampling is not a full-sheet preservation proof.");
        foreach(bool alternating in patterns)foreach(int count in sizes)Model(count,alternating);
        if(args[0]!="model")
        {
            app=ExcelProbe.Attach(Int32.Parse(args[0]));book=app.ActiveWorkbook;
            if(book==null||!((string)book.Name).StartsWith("VCP-",StringComparison.Ordinal))throw new InvalidOperationException("A dedicated owned VCP- synthetic workbook must be active.");
            Log("EXCEL version="+app.Version+" build="+app.Build+" target_pid="+args[0]+" fixture_sheets=retained-unsaved; no workbook save/close/process termination");
            foreach(bool alternating in patterns)foreach(int count in sizes)Real(count,alternating);
        }
        Log("SUMMARY passed="+passed+" failed="+failed);return failed==0?0:1;
    }
}
