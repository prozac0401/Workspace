"""Record real one-shot process lifetime, peak working set and hash timings."""
import argparse, ctypes as C, json, pathlib, statistics, struct, subprocess, sys, time, uuid
from ctypes import wintypes as W
K=C.WinDLL('kernel32',use_last_error=True); PS=C.WinDLL('psapi',use_last_error=True)
class Counters(C.Structure):
    _fields_=[('cb',W.DWORD),('PageFaultCount',W.DWORD)]+[(k,C.c_size_t) for k in ['PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage']]
PS.GetProcessMemoryInfo.argtypes=[W.HANDLE,C.POINTER(Counters),W.DWORD]
K.GetProcessTimes.argtypes=[W.HANDLE,C.POINTER(W.FILETIME),C.POINTER(W.FILETIME),C.POINTER(W.FILETIME),C.POINTER(W.FILETIME)]
class ProcessEntry(C.Structure):
    _fields_=[('dwSize',W.DWORD),('cntUsage',W.DWORD),('th32ProcessID',W.DWORD),('th32DefaultHeapID',C.c_size_t),('th32ModuleID',W.DWORD),('cntThreads',W.DWORD),('th32ParentProcessID',W.DWORD),('pcPriClassBase',W.LONG),('dwFlags',W.DWORD),('szExeFile',W.WCHAR*260)]
K.CreateToolhelp32Snapshot.argtypes=[W.DWORD,W.DWORD]; K.CreateToolhelp32Snapshot.restype=W.HANDLE
K.Process32FirstW.argtypes=[W.HANDLE,C.POINTER(ProcessEntry)]; K.Process32NextW.argtypes=[W.HANDLE,C.POINTER(ProcessEntry)]; K.CloseHandle.argtypes=[W.HANDLE]
def processes():
    snap=K.CreateToolhelp32Snapshot(2,0)
    if snap==C.c_void_p(-1).value: raise C.WinError(C.get_last_error())
    names=[]; entry=ProcessEntry(); entry.dwSize=C.sizeof(entry)
    try:
        ok=K.Process32FirstW(snap,C.byref(entry))
        while ok:
            if entry.szExeFile.lower()=='downloadversionhost.exe': names.append(entry.th32ProcessID)
            ok=K.Process32NextW(snap,C.byref(entry))
    finally: K.CloseHandle(snap)
    return names
def filetime(t): return (t.dwHighDateTime<<32)|t.dwLowDateTime
def measure(host,request):
    raw=json.dumps(request,ensure_ascii=False).encode('utf8'); start=time.perf_counter()
    with subprocess.Popen([str(host),'chrome-extension://knahdnpoplcleaoklikjmgpocealjogc/'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE) as p:
        output,error=p.communicate(struct.pack('<I',len(raw))+raw,timeout=40)
        elapsed=(time.perf_counter()-start)*1000; memory=Counters(); memory.cb=C.sizeof(memory)
        if not PS.GetProcessMemoryInfo(W.HANDLE(int(p._handle)),C.byref(memory),C.sizeof(memory)): raise C.WinError(C.get_last_error())
        created=W.FILETIME(); exited=W.FILETIME(); kernel=W.FILETIME(); user=W.FILETIME()
        if not K.GetProcessTimes(W.HANDLE(int(p._handle)),C.byref(created),C.byref(exited),C.byref(kernel),C.byref(user)): raise C.WinError(C.get_last_error())
        assert p.returncode==0 and not error and len(output)>=4
        response=json.loads(output[4:]); assert response['ok'],response
        return {'wallMilliseconds':round(elapsed,3),'processLifetimeMilliseconds':round((filetime(exited)-filetime(created))/10000,3),'peakWorkingSetBytes':memory.PeakWorkingSetSize,'compareMicroseconds':response['compareMicroseconds'],'hashBytes':response['hashBytes'],'exited':True}
def run(args):
    root=pathlib.Path(args.output).resolve().parent/('resource-fixtures-'+uuid.uuid4().hex); root.mkdir()
    host=pathlib.Path(args.host)
    assert processes()==[], 'Unexpected existing host process; do not terminate it.'
    startup=[measure(host,{'protocolVersion':1,'operation':'ping'}) for _ in range(10)]
    samples={}
    for mib in [10,100]+([1024] if args.gib else []):
        d=root/str(mib); d.mkdir(); target=d/'report.bin'; new=d/'incoming.bin'
        block=b'x'*(1024*1024)
        for p in [target,new]:
            with p.open('wb') as stream:
                for _ in range(mib): stream.write(block)
        sample=measure(host,{'protocolVersion':1,'operation':'process','downloadId':mib,'logicalName':'report.bin','newPath':str(new)})
        assert sample['hashBytes']==2*mib*1024*1024
        assert not (d/'_history').exists() and not new.exists()
        samples[str(mib)+'MiB']=sample
    idle=processes(); assert idle==[]
    results={'environment':{'windowsBuild':sys.getwindowsversion().build,'python':sys.version.split()[0],'architecture':'x64','volume':'local NTFS','cache':'OS cache not flushed; fresh-process startup, not reboot cold-disk measurement'},'executableBytes':host.stat().st_size,'startup':startup,'startupMedianWallMilliseconds':round(statistics.median(s['wallMilliseconds'] for s in startup),3),'hashSamples':samples,'idleNativeProcesses':len(idle),'allExited':True,'oneGiB':'RUN' if args.gib else 'NOT RUN (optional)','servicesTrayWatcherPolling':'No product entries in MSI; installer lifecycle records actual installation checks'}
    pathlib.Path(args.output).write_text(json.dumps(results,indent=2)+'\n','utf-8'); print(json.dumps(results,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--host',required=True); p.add_argument('--output',required=True); p.add_argument('--gib',action='store_true'); run(p.parse_args())
