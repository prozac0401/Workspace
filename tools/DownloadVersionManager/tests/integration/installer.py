"""Opt-in Windows MSI lifecycle in a dedicated artifact folder; never remove a
pre-existing installation. Preserve the business/history fixtures after testing."""
from __future__ import annotations
import argparse, ctypes as C, hashlib, json, pathlib, struct, subprocess, sys, time, uuid, winreg
from ctypes import wintypes as W
sys.stdout.reconfigure(encoding='utf-8')
PRODUCT_KEY=r'Software\Workspace\DownloadVersionManager'
HOST='com.workspace.download_version_manager'
KEYS=[r'Software\Google\Chrome\NativeMessagingHosts'+'\\'+HOST,r'Software\Microsoft\Edge\NativeMessagingHosts'+'\\'+HOST]
UPGRADE='{79E6679C-B762-48DB-B27D-B10963DC1530}'
ORDER_KEY=PRODUCT_KEY+r'\CompletionOrder'
MSI=C.WinDLL('msi'); MSI.MsiEnumRelatedProductsW.argtypes=[W.LPCWSTR,W.DWORD,W.DWORD,W.LPWSTR]
MSI.MsiSetInternalUI.argtypes=[W.UINT,C.POINTER(W.HANDLE)]
MSI.MsiEnableLogW.argtypes=[W.DWORD,W.LPCWSTR,W.DWORD]
MSI.MsiInstallProductW.argtypes=[W.LPCWSTR,W.LPCWSTR]
MSI.MsiConfigureProductExW.argtypes=[W.LPCWSTR,W.INT,W.INT,W.LPCWSTR]

def value(key,name=None,root=winreg.HKEY_CURRENT_USER,view=winreg.KEY_WOW64_64KEY):
    try:
        with winreg.OpenKey(root,key,0,winreg.KEY_READ|view) as h: return winreg.QueryValueEx(h,name)[0]
    except FileNotFoundError: return None
def related():
    found=[]
    for i in range(64):
        b=C.create_unicode_buffer(39); e=MSI.MsiEnumRelatedProductsW(UPGRADE,0,i,b)
        if e==259: return found
        if e: raise RuntimeError('Related product preflight failed: '+str(e))
        found.append(b.value)
    raise RuntimeError('Unexpected number of related products')
def checksum(p):
    with p.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()
def execute(state,msi,args,name,expected=0):
    log=pathlib.Path(state['work'])/(name+'.log')
    # Supported Windows Installer API in a bounded child, with UI disabled.
    result=pathlib.Path(state['work'])/(name+'-exit.json')
    try:
        p=subprocess.run([sys.executable,__file__,'msi-child','--msi',str(msi),'--output',str(result),'--log',str(log),'--action',args[0]]+['--property='+x for x in args[1:]],capture_output=True,timeout=60)
        code=json.loads(result.read_text('utf-8'))['exitCode'] if result.exists() else p.returncode
    except subprocess.TimeoutExpired:
        state['tests'].append({'name':name,'status':'NOT RUN','reason':'Windows Installer call did not complete within 60s; no lifecycle PASS. Inspect exact registration/files before any retry.'});save(state);raise
    accepted=code in expected if isinstance(expected,(list,tuple)) else code==expected
    state['tests'].append({'name':name,'exitCode':code,'status':'PASS' if accepted else 'FAIL'})
    save(state)
    if not accepted: raise RuntimeError(f'{name}: expected {expected}, actual {code}; no forced cleanup. Log={log}')
    return code
def save(state): pathlib.Path(state['state']).write_text(json.dumps(state,indent=2)+'\n','utf-8')
def check_files(state):
    for p,expected in state['preserve'].items(): assert checksum(pathlib.Path(p))==expected,p
def create_order_fixture(state):
    folder=pathlib.Path(state['work'])/'Order fixture'; folder.mkdir()
    incoming=folder/'incoming.bin'; target=folder/'current.bin'; incoming.write_bytes(b'latest fixture')
    name=hashlib.sha256(str(target).lower().encode('utf8')).hexdigest()
    assert value(ORDER_KEY,name) is None, 'Existing order value must not be changed.'
    app=pathlib.Path(state['install']); manifest=json.loads((app/'native-host.json').read_text('utf8'))
    message={'protocolVersion':2,'operation':'process','downloadId':1,'logicalName':target.name,'newPath':str(incoming),'completedAt':time.time_ns()//1000000,'requestToken':uuid.uuid4().hex}
    raw=json.dumps(message).encode('utf8'); before=incoming.stat().st_ino
    result=subprocess.run([str(app/'DownloadVersionHost.exe'),manifest['allowed_origins'][0]],input=struct.pack('<I',len(raw))+raw,capture_output=True,timeout=10)
    assert result.returncode==0 and not result.stderr and json.loads(result.stdout[4:])['ok']
    assert target.stat().st_ino==before
    order=value(ORDER_KEY,name); assert isinstance(order,bytes) and len(order)==138
    state['orderFixture']={'name':name,'bytes':order.hex()}; state['preserve'][str(target)]=checksum(target); save(state)
def check_order_fixture(state):
    item=state.get('orderFixture')
    if item: assert value(ORDER_KEY,item['name'])==bytes.fromhex(item['bytes'])
def check_registered(state):
    app=pathlib.Path(state['install']); assert (app/'DownloadVersionHost.exe').is_file()
    for key in KEYS: assert value(key)==str(app/'native-host.json'),(key,value(key))
    manifest=json.loads((app/'native-host.json').read_text('utf-8'))
    extension=json.loads((app/'extension/manifest.json').read_text('utf-8'))
    request=json.dumps({'protocolVersion':2,'operation':'ping'}).encode('utf-8')
    host=subprocess.run([str(app/'DownloadVersionHost.exe'),manifest['allowed_origins'][0]],input=struct.pack('<I',len(request))+request,capture_output=True,timeout=10)
    assert host.returncode==0 and host.stderr==b''
    length=struct.unpack('<I',host.stdout[:4])[0]; assert len(host.stdout)==length+4
    response=json.loads(host.stdout[4:]); assert response['ok'] and response['status']=='ready' and response['protocolVersion']==2
    assert response['version']==extension['version']
    state['directHostVersion']=response['version'] # Direct protocol invocation, not a browser handshake.
    check_files(state)
    check_order_fixture(state)

def cleanup(args):
    state=json.loads(pathlib.Path(args.output).read_text('utf-8'))
    check_registered(state)
    execute(state,state['msi'],['/x'],'final-test-cleanup')
    assert not related() and value(PRODUCT_KEY,'InstallFolder') is None
    assert all(value(key) is None for key in KEYS)
    assert not (pathlib.Path(state['install'])/'DownloadVersionHost.exe').exists()
    check_files(state)
    check_order_fixture(state)
    item=state.get('orderFixture')
    if item:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,ORDER_KEY,0,winreg.KEY_SET_VALUE|winreg.KEY_WOW64_64KEY) as key: winreg.DeleteValue(key,item['name'])
    state['cleaned']=True; save(state); print('Owned test installation removed; user fixtures preserved.')
def preflight():
    assert not related(), 'An existing related installation must not be changed.'
    assert value(PRODUCT_KEY,'InstallFolder') is None
    for key in KEYS:
        for root in [winreg.HKEY_CURRENT_USER,winreg.HKEY_LOCAL_MACHINE]:
            for view in [winreg.KEY_WOW64_32KEY,winreg.KEY_WOW64_64KEY]: assert value(key,root=root,view=view) is None,'Native host registration already exists; stop.'
def fixture(msi,output):
    base=pathlib.Path(output).resolve().parent; base.mkdir(parents=True,exist_ok=True)
    preflight()
    work=base/('installer-fixture-'+uuid.uuid4().hex); install=work/'Installed Program'; install.mkdir(parents=True)
    history=install/'_history'; history.mkdir(); (history/'user-version.xlsx').write_bytes(b'user history')
    (install/'unrelated-user.txt').write_bytes(b'unrelated user file')
    downloads=work/'Downloads'; downloads.mkdir(); (downloads/'business.xlsx').write_bytes(b'user download')
    preserve={str(p):checksum(p) for p in [history/'user-version.xlsx',install/'unrelated-user.txt',downloads/'business.xlsx']}
    state={'state':str(pathlib.Path(output).resolve()),'work':str(work),'install':str(install),'msi':str(pathlib.Path(msi).resolve()),'msiSha256':checksum(pathlib.Path(msi)),'tests':[],'preserve':preserve,'prepared':True,'runtimeEvidence':'separate browser test','finished':False}
    save(state); return state
def prepare(args):
    state=fixture(args.msi,args.output); install=pathlib.Path(state['install'])
    save(state); execute(state,state['msi'],['/i','INSTALLFOLDER='+str(install)],'fresh-install'); check_registered(state)
    create_order_fixture(state)
    state['tests'].append({'name':'fresh host, Chrome/Edge HKCU and user data preserved','status':'PASS'}); save(state); print(json.dumps(state,indent=2))
def resume(args):
    state=json.loads(pathlib.Path(args.output).read_text('utf-8')); app=pathlib.Path(state['install']); msi=pathlib.Path(state['msi'])
    assert checksum(msi)==state['msiSha256']; check_registered(state)
    # Retain a user's unrelated named value in a product-specific browser key.
    for key in KEYS:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,key,0,winreg.KEY_SET_VALUE) as h: winreg.SetValueEx(h,'UnrelatedFixture',0,winreg.REG_SZ,'preserve')
    execute(state,msi,['/fa'],'same-version-repair'); check_registered(state)
    (app/'extension/popup.css').unlink() # Exact owned missing-file repair fixture only.
    execute(state,msi,['/fa'],'missing-file-repair'); assert (app/'extension/popup.css').is_file(); check_registered(state)
    execute(state,msi,['/i'],'same-version-install'); check_registered(state)
    # A user-modified installed file must cause a safe guard refusal.
    file=app/'extension/popup.css'; original=file.read_bytes(); file.write_bytes(original+b'\n/* user change */\n')
    execute(state,msi,['/fa'],'external-file-change-guard',1603); assert file.read_bytes().endswith(b'/* user change */\n'); file.write_bytes(original)
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER,KEYS[0],0,winreg.KEY_SET_VALUE) as h: winreg.SetValueEx(h,None,0,winreg.REG_SZ,'C:\\unrelated-fixture\\manifest.json')
    execute(state,msi,['/fa'],'external-native-registration-guard',1603)
    assert value(KEYS[0])=='C:\\unrelated-fixture\\manifest.json'
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER,KEYS[0],0,winreg.KEY_SET_VALUE) as h: winreg.SetValueEx(h,None,0,winreg.REG_SZ,str(app/'native-host.json'))
    if args.upgrade:
        execute(state,pathlib.Path(args.upgrade),['/i'],'upgrade-0.1.1'); check_registered(state)
        execute(state,pathlib.Path(args.upgrade),['/x'],'uninstall-upgrade')
    else: execute(state,msi,['/x'],'uninstall')
    for key in KEYS: assert value(key) is None and value(key,'UnrelatedFixture')=='preserve'
    assert not (app/'DownloadVersionHost.exe').exists(); check_files(state)
    check_order_fixture(state); state['tests'].append({'name':'uninstall preserves completion order state and downloaded object','status':'PASS'}); save(state)
    # Remove only test-owned extra registry values so a fresh MSI preflight can run.
    for key in KEYS:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,key,0,winreg.KEY_SET_VALUE) as h: winreg.DeleteValue(h,'UnrelatedFixture')
    if args.rollback:
        execute(state,pathlib.Path(args.rollback),['/i','INSTALLFOLDER='+str(app)],'failed-installer-rollback',1603)
        assert not (app/'DownloadVersionHost.exe').exists() and value(KEYS[0]) is None and value(KEYS[1]) is None; check_files(state)
        residue=related()
        state['tests'].append({'name':'failed install files, native registrations, MSI product registration rollback','status':'FAIL' if residue else 'PASS','relatedProducts':residue}); save(state)
        if residue: raise RuntimeError('Failed installation retained an MSI product registration; do not equate exit 1603 with rollback PASS.')
    execute(state,msi,['/i','INSTALLFOLDER='+str(app)],'reinstall'); check_registered(state)
    state['finished']=True; state['tests'].append({'name':'user download/history and unrelated file/registry preserved','status':'PASS'})
    state['installedVersion']='0.1.0'; save(state); print(json.dumps(state,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('mode',choices=['prepare','resume','cleanup','msi-child']); p.add_argument('--msi'); p.add_argument('--output',required=True); p.add_argument('--upgrade'); p.add_argument('--rollback');p.add_argument('--log');p.add_argument('--action');p.add_argument('--property',action='append',default=[]);a=p.parse_args()
    if a.mode=='msi-child':
        MSI.MsiSetInternalUI(2,None)
        if MSI.MsiEnableLogW(0xFFFF,str(pathlib.Path(a.log).resolve()),0): raise RuntimeError('MSI log enable failed')
        properties=' '.join(k.split('=',1)[0]+'="'+k.split('=',1)[1]+'"' for k in a.property)+' REBOOT=ReallySuppress MSIRESTARTMANAGERCONTROL=Disable'
        if a.action=='/fa': properties+=' REINSTALL=ALL REINSTALLMODE=vamus'
        if a.action=='/x':
            candidates=related()
            if len(candidates)!=1: raise RuntimeError('Exactly one owned related product required for uninstall')
            code=MSI.MsiConfigureProductExW(candidates[0],0,2,properties)
        else: code=MSI.MsiInstallProductW(str(pathlib.Path(a.msi).resolve()),properties)
        pathlib.Path(a.output).write_text(json.dumps({'exitCode':code})+'\n','utf-8')
    elif a.mode=='prepare': prepare(a)
    elif a.mode=='cleanup': cleanup(a)
    else: resume(a)
