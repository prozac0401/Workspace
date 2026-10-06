"""Read-only snapshots for an already approved disposable Windows installer trial."""
from __future__ import annotations
import ctypes as C
from ctypes import wintypes as W
import hashlib
import os
import pathlib
import socket
import winreg
from installer_evidence import TrialBlocked
msi = C.WinDLL('msi')
msi.MsiOpenDatabaseW.argtypes=[W.LPCWSTR,W.LPCWSTR,C.POINTER(W.UINT)]
msi.MsiDatabaseOpenViewW.argtypes=[W.UINT,W.LPCWSTR,C.POINTER(W.UINT)]
msi.MsiViewExecute.argtypes=[W.UINT,W.UINT]
msi.MsiViewFetch.argtypes=[W.UINT,C.POINTER(W.UINT)]
msi.MsiCloseHandle.argtypes=[W.UINT]
msi.MsiEnumRelatedProductsW.argtypes=[W.LPCWSTR,W.DWORD,W.DWORD,W.LPWSTR]
msi.MsiQueryProductStateW.argtypes=[W.LPCWSTR]
msi.MsiQueryProductStateW.restype=C.c_int
adv = C.WinDLL('advapi32', use_last_error=True)
kernel = C.WinDLL('kernel32', use_last_error=True)
adv.GetSecurityInfo.argtypes=[W.HANDLE,W.DWORD,W.DWORD,C.c_void_p,C.c_void_p,C.c_void_p,C.c_void_p,C.POINTER(C.c_void_p)]
adv.GetNamedSecurityInfoW.argtypes=[W.LPWSTR,W.DWORD,W.DWORD,C.c_void_p,C.c_void_p,C.c_void_p,C.c_void_p,C.POINTER(C.c_void_p)]
adv.ConvertSecurityDescriptorToStringSecurityDescriptorW.argtypes=[C.c_void_p,W.DWORD,W.DWORD,C.POINTER(W.LPWSTR),C.POINTER(W.DWORD)]
kernel.LocalFree.argtypes=[C.c_void_p]
kernel.GetCurrentProcess.restype=W.HANDLE
adv.OpenProcessToken.argtypes=[W.HANDLE,W.DWORD,C.POINTER(W.HANDLE)]
adv.GetTokenInformation.argtypes=[W.HANDLE,C.c_int,C.c_void_p,W.DWORD,C.POINTER(W.DWORD)]
adv.ConvertSidToStringSidW.argtypes=[C.c_void_p,C.POINTER(W.LPWSTR)]
kernel.CloseHandle.argtypes=[W.HANDLE]

def context():
    token=W.HANDLE()
    if not adv.OpenProcessToken(kernel.GetCurrentProcess(),8,C.byref(token)):
        raise TrialBlocked('BLOCKED: execution token cannot be read')
    def info(kind):
        size=W.DWORD()
        adv.GetTokenInformation(token,kind,None,0,C.byref(size))
        buf=C.create_string_buffer(size.value)
        if not adv.GetTokenInformation(token,kind,buf,size,C.byref(size)):
            raise TrialBlocked('BLOCKED: token information unavailable')
        return buf
    def sid_text(buf):
        sid=C.cast(buf,C.POINTER(C.c_void_p))[0]; text=W.LPWSTR()
        if not adv.ConvertSidToStringSidW(sid,C.byref(text)):
            raise TrialBlocked('BLOCKED: token SID unavailable')
        try:return text.value
        finally:kernel.LocalFree(text)
    try:
        user=sid_text(info(1)); integrity_sid=sid_text(info(25))
        rid=int(integrity_sid.rsplit('-',1)[1])
        return {'machine':socket.gethostname(),'userSid':user,'elevated':bool(C.cast(info(20),C.POINTER(W.DWORD))[0]),
                'integrity':'medium' if rid==8192 else 'other','integritySid':integrity_sid,
                'appContainer':bool(C.cast(info(29),C.POINTER(W.DWORD))[0])}
    finally:kernel.CloseHandle(token)

def descriptor(handle=None,path=None):
    sd=C.c_void_p()
    if handle is not None:
        code=adv.GetSecurityInfo(W.HANDLE(handle),4,5,None,None,None,None,C.byref(sd))
    else:
        code=adv.GetNamedSecurityInfoW(str(path),1,5,None,None,None,None,C.byref(sd))
    if code:return {'status':'UNKNOWN','win32':code}
    text=W.LPWSTR(); n=W.DWORD()
    try:
        if not adv.ConvertSecurityDescriptorToStringSecurityDescriptorW(sd,1,5,C.byref(text),C.byref(n)):
            return {'status':'UNKNOWN','win32':C.get_last_error()}
        try:return {'status':'KNOWN','ownerDacl':text.value}
        finally:kernel.LocalFree(text)
    finally:kernel.LocalFree(sd)

def registry(key_path,recursive=True,hive=winreg.HKEY_CURRENT_USER):
    try:
        with winreg.OpenKey(hive,key_path,0,winreg.KEY_READ|winreg.KEY_WOW64_64KEY) as key:
            values={}; children={}; count=winreg.QueryInfoKey(key)
            for i in range(count[1]):
                name,data,kind=winreg.EnumValue(key,i)
                if isinstance(data,bytes):data={'hex':data.hex()}
                values[name]={'kind':kind,'data':data}
            if recursive:
                for i in range(count[0]):
                    name=winreg.EnumKey(key,i); children[name]=registry(key_path+chr(92)+name,hive=hive)
            return {'present':True,'values':values,'children':children,'security':descriptor(handle=int(key))}
    except FileNotFoundError:return {'present':False}
    except OSError as error:return {'status':'UNKNOWN','win32':error.winerror}

def file_tree(root):
    root=pathlib.Path(root)
    if not root.exists():return {'present':False}
    result={}
    for path in [root,*sorted(root.rglob('*'))]:
        st=path.lstat()
        if st.st_file_attributes & 0x400:
            raise TrialBlocked('BLOCKED: fixture contains a reparse point')
        entry={'kind':'directory' if path.is_dir() else 'file','attributes':st.st_file_attributes,
               'fileId':st.st_ino,'security':descriptor(path=path)}
        if path.is_file():
            entry.update(size=st.st_size,mtimeNs=st.st_mtime_ns,creationNs=st.st_ctime_ns,
                         sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        result[path.relative_to(root).as_posix()]=entry
    return {'present':True,'entries':result}

def related(upgrade):
    found=[]
    for index in range(64):
        code_buffer=C.create_unicode_buffer(39)
        code=msi.MsiEnumRelatedProductsW(upgrade,0,index,code_buffer)
        if code==259:return sorted(found)
        if code:raise TrialBlocked('BLOCKED: related product enumeration failed: '+str(code))
        found.append(code_buffer.value)
    raise TrialBlocked('BLOCKED: too many related products')

def packed_guid(value):
    parts=value.strip('{}').split('-')
    return ''.join(p[::-1] for p in parts[:3])+''.join(p[i+1]+p[i] for p in parts[3:] for i in range(0,len(p),2))

def snapshot(product,upgrade,legacy_upgrade,fixture,shortcut_dir):
    product_packed=packed_guid(product); slash=chr(92)
    keys=['Software'+slash+'Workspace'+slash+'DownloadVersionManager',
          'Software'+slash+'Microsoft'+slash+'Windows'+slash+'CurrentVersion'+slash+'Run',
          'Software'+slash+'Microsoft'+slash+'Windows'+slash+'CurrentVersion'+slash+'Uninstall'+slash+product,
          'Software'+slash+'Microsoft'+slash+'Installer'+slash+'Products'+slash+product_packed,
          'Software'+slash+'Microsoft'+slash+'Installer'+slash+'UpgradeCodes'+slash+packed_guid(upgrade)]
    user_data='Software'+slash+'Microsoft'+slash+'Windows'+slash+'CurrentVersion'+slash+'Installer'+slash+'UserData'+slash+context()['userSid']+slash+'Products'+slash+product_packed
    return {'installerUserData':registry(user_data,hive=winreg.HKEY_LOCAL_MACHINE),'productState':msi.MsiQueryProductStateW(product),
            'related':related(upgrade),'legacyRelated':related(legacy_upgrade),
            'registry':{key:registry(key) for key in keys},
            'fixture':{'install':file_tree(pathlib.Path(fixture)/'Installed Program'),'watched':file_tree(pathlib.Path(fixture)/'Watched Folder')},'shortcuts':file_tree(shortcut_dir)}


def stream_fingerprints(path):
    from verify import query
    quote=chr(96)
    names=[row[0] for row in query(path,'SELECT '+quote+'Name'+quote+' FROM '+quote+'_Streams'+quote)]
    wanted=[name for name in names if name.startswith('Binary.') or name.endswith('.cab')]
    msi.MsiRecordReadStream.argtypes=[W.UINT,W.UINT,C.c_void_p,C.POINTER(W.DWORD)]
    result={}
    for name in wanted:
        db=W.UINT(); view=W.UINT(); record=W.UINT()
        assert msi.MsiOpenDatabaseW(str(path),None,C.byref(db))==0
        try:
            escaped=name.replace("'","''")
            sql='SELECT '+quote+'Data'+quote+' FROM '+quote+'_Streams'+quote+' WHERE '+quote+'Name'+quote+"='"+escaped+"'"
            assert msi.MsiDatabaseOpenViewW(db,sql,C.byref(view))==0
            assert msi.MsiViewExecute(view,0)==0 and msi.MsiViewFetch(view,C.byref(record))==0
            hash=hashlib.sha256()
            while True:
                n=W.DWORD(65536); buf=C.create_string_buffer(n.value)
                assert msi.MsiRecordReadStream(record,1,buf,C.byref(n))==0
                if not n.value:break
                hash.update(buf.raw[:n.value])
            result[name]=hash.hexdigest()
        finally:
            if record.value:msi.MsiCloseHandle(record)
            if view.value:msi.MsiCloseHandle(view)
            msi.MsiCloseHandle(db)
    if not any(name.endswith('.cab') for name in result) or not any(name.startswith('Binary.') for name in result):
        raise TrialBlocked('BLOCKED: embedded payload/custom action streams not found')
    return result
