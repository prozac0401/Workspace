using System;
using System.Collections;
using System.Reflection;
using System.IO;
using System.Text;
class EngineGuardTests
{
    static int count;
    static void Assert(bool value,string label) { if(!value)throw new Exception(label); count++; Console.WriteLine("PASS "+label); }
    // Pure tests cover state, block planning and unstarted-job cleanup; no Excel
    // process, COM activation, workbook, clipboard, or installation is accessed.
    static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        try
        {
            if(args.Length!=1)throw new ArgumentException("Usage: EngineGuardTests.exe <actual-addin-dll-path>");
            string assemblyPath=Path.GetFullPath(args[0]);
            if(!File.Exists(assemblyPath))throw new FileNotFoundException("The built add-in DLL is required.",assemblyPath);
            var assembly=Assembly.LoadFrom(assemblyPath);
            var type=assembly.GetType("ExcelSelectionExport.ExportEngine",true);
            var guard=type.GetMethod("CanReadCachedValues",BindingFlags.Static|BindingFlags.NonPublic);
            if(guard==null)throw new MissingMethodException(type.FullName,"CanReadCachedValues");
            int[,] states={{0,-4135,1},{0,-4105,1},{0,2,1},{1,-4135,0},{1,-4105,0},{1,2,0},{2,-4135,1},{2,-4105,0},{2,2,0},{3,-4135,0}};
            for(int i=0;i<states.GetLength(0);i++)Assert((bool)guard.Invoke(null,new object[]{states[i,0],states[i,1]})==(states[i,2]==1),"calculation state="+states[i,0]+" mode="+states[i,1]);
            var blocks=type.GetMethod("Blocks",BindingFlags.Static|BindingFlags.NonPublic);
            if(blocks==null)throw new MissingMethodException(type.FullName,"Blocks");
            int[,] sizes={{1,1},{1,256},{1,16383},{100000,1},{100,1000},{400,250},{3,257},{257,3}};
            for(int n=0;n<sizes.GetLength(0);n++)
            {
                int rows=sizes[n,0],columns=sizes[n,1],covered=0,blockCount=0;
                var seen=new bool[rows,columns];
                foreach(object block in (IEnumerable)blocks.Invoke(null,new object[]{rows,columns}))
                {
                    if(++blockCount>rows*columns)throw new Exception("Too many blocks for the finite input rectangle");
                    var bt=block.GetType(); var flags=BindingFlags.Instance|BindingFlags.Public|BindingFlags.NonPublic;
                    int row=(int)bt.GetField("Row",flags).GetValue(block),column=(int)bt.GetField("Column",flags).GetValue(block);
                    int height=(int)bt.GetField("Rows",flags).GetValue(block),width=(int)bt.GetField("Columns",flags).GetValue(block);
                    if(height<1||width<1||(long)height*width>256||row<0||column<0||(long)row+height>rows||(long)column+width>columns)throw new Exception("unbounded/outside block");
                    for(int r=row;r<row+height;r++)for(int c=column;c<column+width;c++){if(seen[r,c])throw new Exception("duplicate cell");seen[r,c]=true;covered++;}
                }
                Assert(covered==rows*columns,"bounded complete unique coverage "+rows+"x"+columns);
            }
            var jobType=type.GetNestedType("ExportJob",BindingFlags.NonPublic);
            if(jobType==null)throw new MissingMemberException(type.FullName,"ExportJob");
            var constructor=jobType.GetConstructor(BindingFlags.Instance|BindingFlags.NonPublic,null,new Type[]{typeof(object)},null);
            if(constructor==null)throw new MissingMethodException(jobType.FullName,".ctor(object)");
            var job=(IDisposable)constructor.Invoke(new object[]{new object()});
            job.Dispose();
            Assert(true,"unstarted job cleanup resolves outer static COM helpers");
            job.Dispose();
            Assert(true,"unstarted job repeated cleanup remains safe");
            var restore=jobType.GetMethod("RestoreState",BindingFlags.Instance|BindingFlags.NonPublic);
            if(restore==null)throw new MissingMethodException(jobType.FullName,"RestoreState");
            var flagNames=new[]{"oldEvents","oldScreenUpdating","oldInteractive","changedState"};
            var fake=new RestoreApplication();
            var restoreJob=(IDisposable)constructor.Invoke(new object[]{fake});
            foreach(string flag in flagNames)jobType.GetField(flag,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(restoreJob,true);
            restore.Invoke(restoreJob,null);
            Assert(fake.EnableEvents&&fake.ScreenUpdating&&fake.Interactive&&fake.Writes==3,"all UI flags restored independently");
            restore.Invoke(restoreJob,null);restoreJob.Dispose();
            Assert(fake.Writes==3,"successful restoration is idempotent through Dispose");
            var retryFake=new RestoreApplication{FailScreenOnce=true};
            var retryJob=(IDisposable)constructor.Invoke(new object[]{retryFake});
            foreach(string flag in flagNames)jobType.GetField(flag,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(retryJob,true);
            restore.Invoke(retryJob,null);
            Assert(retryFake.EnableEvents&&retryFake.Interactive&&!retryFake.ScreenUpdating&&retryFake.Writes==3,"one failed flag does not prevent restoring the others");
            retryJob.Dispose();
            Assert(retryFake.EnableEvents&&retryFake.ScreenUpdating&&retryFake.Interactive&&retryFake.Writes==6,"Dispose retries an incomplete state restoration");
            retryJob.Dispose();Assert(retryFake.Writes==6,"successful retry remains idempotent");
            var preparedType=type.GetNestedType("PreparedMenuExport",BindingFlags.NonPublic);
            var preparedConstructor=preparedType.GetConstructor(BindingFlags.Instance|BindingFlags.NonPublic,null,new Type[]{jobType},null);
            var pendingFake=new RestoreApplication();
            var pendingJob=(IDisposable)constructor.Invoke(new object[]{pendingFake});
            foreach(string flag in flagNames)jobType.GetField(flag,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(pendingJob,true);
            var prepared=(IDisposable)preparedConstructor.Invoke(new object[]{pendingJob});
            prepared.Dispose();
            Assert(pendingFake.EnableEvents&&pendingFake.ScreenUpdating&&pendingFake.Interactive&&pendingFake.Writes==3&&(bool)jobType.GetField("cancel",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(pendingJob),"discarded prepared request cancels and restores pinned-job state");
            prepared.Dispose();Assert(pendingFake.Writes==3,"prepared request disposal is idempotent");
            bool reused=false;
            try {preparedType.GetMethod("Run",BindingFlags.Instance|BindingFlags.NonPublic).Invoke(prepared,null);}
            catch(TargetInvocationException error) {reused=error.InnerException is InvalidOperationException;}
            Assert(reused,"disposed prepared request cannot run later");
            var prepareUi=jobType.GetMethod("PrepareOutputUi",BindingFlags.Instance|BindingFlags.NonPublic);
            var uiFake=new RestoreApplication();
            var uiJob=(IDisposable)constructor.Invoke(new object[]{uiFake});
            foreach(string flag in flagNames)jobType.GetField(flag,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(uiJob,true);
            prepareUi.Invoke(uiJob,null);
            Assert(uiFake.ScreenUpdating&&uiFake.Interactive&&!uiFake.EnableEvents&&uiFake.Writes==2,"new-window preparation restores UI without enabling output events");
            Assert((bool)jobType.GetField("changedState",BindingFlags.Instance|BindingFlags.NonPublic).GetValue(uiJob),"new-window preparation preserves final restoration responsibility");
            uiJob.Dispose();Assert(uiFake.EnableEvents&&uiFake.Writes==5,"final cleanup restores all flags after prepared-window state");
            var failedUi=new RestoreApplication{FailScreenOnce=true};
            var failedUiJob=(IDisposable)constructor.Invoke(new object[]{failedUi});
            foreach(string flag in flagNames)jobType.GetField(flag,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(failedUiJob,true);
            bool uiRejected=false;
            try {prepareUi.Invoke(failedUiJob,null);}
            catch(TargetInvocationException error) {uiRejected=error.InnerException is InvalidOperationException;}
            failedUiJob.Dispose();
            Assert(uiRejected&&failedUi.Interactive&&failedUi.ScreenUpdating&&failedUi.EnableEvents&&failedUi.Writes==5,"failed pre-creation UI restore stops creation and remains recoverable");
            var guardOutput=jobType.GetMethod("GuardOutputUi",BindingFlags.Instance|BindingFlags.NonPublic);
            var outputFake=new RestoreApplication{EnableEvents=false,ScreenUpdating=true,Interactive=true};
            var outputJob=(IDisposable)constructor.Invoke(new object[]{outputFake});
            foreach(string flag in flagNames)jobType.GetField(flag,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(outputJob,true);
            guardOutput.Invoke(outputJob,null);
            Assert(!outputFake.Interactive&&!outputFake.ScreenUpdating&&!outputFake.EnableEvents,"output writing blocks user input while events remain suppressed");
            outputJob.Dispose();
            Assert(outputFake.Interactive&&outputFake.ScreenUpdating&&outputFake.EnableEvents,"output guard leaves all application flags restorable");
            var partialGuard=new RestoreApplication{EnableEvents=false,ScreenUpdating=true,Interactive=true};
            partialGuard.FailScreenOnce=true;
            var partialJob=(IDisposable)constructor.Invoke(new object[]{partialGuard});
            foreach(string flag in flagNames)jobType.GetField(flag,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(partialJob,true);
            bool guardFailed=false;
            try {guardOutput.Invoke(partialJob,null);}
            catch(TargetInvocationException error) {guardFailed=error.InnerException is InvalidOperationException;}
            Assert(guardFailed&&!partialGuard.Interactive&&partialGuard.ScreenUpdating,"partial output guard failure is observable instead of continuing unlocked");
            partialJob.Dispose();
            Assert(partialGuard.Interactive&&partialGuard.ScreenUpdating&&partialGuard.EnableEvents,"cleanup restores user input after a partial output guard failure");
            var complete=jobType.GetMethod("Complete",BindingFlags.Instance|BindingFlags.NonPublic);
            foreach(bool persistent in new[]{true,false})
            {
                var completionFake=new RestoreApplication{FailScreenAlways=persistent,FailScreenOnce=!persistent};
                var completionJob=(IDisposable)constructor.Invoke(new object[]{completionFake});
                foreach(string flag in flagNames)jobType.GetField(flag,BindingFlags.Instance|BindingFlags.NonPublic).SetValue(completionJob,true);
                jobType.GetField("successful",BindingFlags.Instance|BindingFlags.NonPublic).SetValue(completionJob,true);
                bool blockedSuccess=false;
                try {complete.Invoke(completionJob,null);}
                catch(TargetInvocationException error) {blockedSuccess=error.InnerException is InvalidOperationException&&error.InnerException.Message.Contains("복원하지 못해");}
                Assert(blockedSuccess&&completionFake.EnableEvents&&completionFake.Interactive&&!completionFake.ScreenUpdating,"incomplete restoration blocks success before result activation; persistent="+persistent);
                completionJob.Dispose();
                Assert(completionFake.EnableEvents&&completionFake.Interactive&&completionFake.ScreenUpdating==!persistent&&completionFake.Writes==6,"cleanup independently retries all flags after completion rejection; persistent="+persistent);
            }
            Console.WriteLine("PASS "+count+" engine guards/block/cleanup cases");return 0;
        }
        catch(Exception ex){Console.Error.WriteLine(ex);return 1;}
    }
}

// A managed fake only: these tests never connect to an Excel process.
public sealed class RestoreApplication
{
    bool events,screen,interactive;
    public int Writes;
    public bool FailScreenOnce;
    public bool FailScreenAlways;
    public bool EnableEvents { get { return events; } set { Writes++; events=value; } }
    public bool ScreenUpdating { get { return screen; } set { Writes++; if(FailScreenAlways)throw new InvalidOperationException("persistent synthetic restoration failure"); if(FailScreenOnce){FailScreenOnce=false;throw new InvalidOperationException("synthetic restoration failure");} screen=value; } }
    public bool Interactive { get { return interactive; } set { Writes++; interactive=value; } }
}
