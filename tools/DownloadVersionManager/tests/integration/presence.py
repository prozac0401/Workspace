"""Read-only native idle / startup / service / scheduled task inventory.
Only product-specific counts are persisted; unrelated user entries are omitted.
Run while the isolated MSI is installed, then after its owned cleanup.
"""
import argparse, ctypes as C, json, pathlib, subprocess, winreg
from ctypes import wintypes as W

def match(value):
    return 'downloadversion' in str(value).replace(' ', '').lower()

def processes():
    class Entry(C.Structure):
        _fields_=[('size',W.DWORD),('usage',W.DWORD),('pid',W.DWORD),('heap',C.c_size_t),('module',W.DWORD),('threads',W.DWORD),('parent',W.DWORD),('priority',W.LONG),('flags',W.DWORD),('exe',W.WCHAR*260)]
    k=C.WinDLL('kernel32',use_last_error=True)
    k.CreateToolhelp32Snapshot.argtypes=[W.DWORD,W.DWORD]; k.CreateToolhelp32Snapshot.restype=W.HANDLE
    k.Process32FirstW.argtypes=[W.HANDLE,C.POINTER(Entry)]; k.Process32NextW.argtypes=[W.HANDLE,C.POINTER(Entry)]; k.CloseHandle.argtypes=[W.HANDLE]
    snap=k.CreateToolhelp32Snapshot(2,0)
    if snap==C.c_void_p(-1).value: raise C.WinError(C.get_last_error())
    count=0; row=Entry(); row.size=C.sizeof(row)
    try:
        more=k.Process32FirstW(snap,C.byref(row))
        while more:
            if match(row.exe): count+=1
            more=k.Process32NextW(snap,C.byref(row))
        return count
    finally: k.CloseHandle(snap)

def startup():
    found=0
    for root in [winreg.HKEY_CURRENT_USER,winreg.HKEY_LOCAL_MACHINE]:
        for view in [winreg.KEY_WOW64_32KEY,winreg.KEY_WOW64_64KEY]:
            for leaf in ['Run','RunOnce']:
                try:
                    with winreg.OpenKey(root,r'Software\Microsoft\Windows\CurrentVersion'+'\\'+leaf,0,winreg.KEY_READ|view) as key:
                        for index in range(winreg.QueryInfoKey(key)[1]):
                            name,data,_=winreg.EnumValue(key,index)
                            if match(name) or match(data): found+=1
                except FileNotFoundError: pass
    return found

def cli_count(command):
    result=subprocess.run(command,capture_output=True,timeout=15)
    if result.returncode: return {'status':'NOT RUN','exitCode':result.returncode}
    # Only ASCII product-name matches, never retain full machine inventories.
    count=sum(match(line) for line in result.stdout.decode('utf-8',errors='replace').splitlines())
    return {'status':'PASS' if count==0 else 'FAIL','productMatches':count}

if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--output',required=True); a=p.parse_args()
    native=processes(); entries=startup()
    evidence={'nativeProcesses':native,'nativeIdle':'PASS' if native==0 else 'FAIL','startupMatches':entries,'startup':'PASS' if entries==0 else 'FAIL','services':cli_count(['sc.exe','query','type=','service','state=','all']),'scheduledTasks':cli_count(['schtasks.exe','/query','/fo','csv','/nh']),'scope':'Product-specific name matches plus MSI structure; enabled browser extension idle remains a separate gate.'}
    pathlib.Path(a.output).write_text(json.dumps(evidence,indent=2)+'\n','utf-8')
    print(json.dumps(evidence))
