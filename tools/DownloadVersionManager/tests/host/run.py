"""Real Windows subprocess/NTFS tests. All writes are under owned fixtures."""
from __future__ import annotations
import argparse, concurrent.futures, ctypes as C, hashlib, json, os, pathlib, re, struct, subprocess, sys, time, traceback, uuid
from ctypes import wintypes as W

K = C.WinDLL('kernel32', use_last_error=True)
K.CreateFileW.argtypes=[W.LPCWSTR,W.DWORD,W.DWORD,W.LPVOID,W.DWORD,W.DWORD,W.HANDLE]; K.CreateFileW.restype=W.HANDLE
K.CloseHandle.argtypes=[W.HANDLE]
ORIGIN='chrome-extension://knahdnpoplcleaoklikjmgpocealjogc/'

def frame(value):
    data=json.dumps(value,ensure_ascii=False,separators=(',',':')).encode('utf-8'); return struct.pack('<I',len(data))+data

def invoke(exe, value, origin=ORIGIN, raw=None):
    p=subprocess.run([str(exe),origin],input=frame(value) if raw is None else raw,capture_output=True,timeout=45)
    assert not p.stderr, p.stderr
    assert len(p.stdout)>=4, (p.returncode,p.stdout)
    n=struct.unpack('<I',p.stdout[:4])[0]; assert len(p.stdout)==n+4, 'stdout must be exactly one framed response'
    return json.loads(p.stdout[4:]),p.returncode

def request(path,name='보고서.xlsx',**extra):
    return {'protocolVersion':1,'operation':'process','downloadId':1,'logicalName':name,'newPath':str(path),**extra}

def run(args):
    sys.stdout.reconfigure(encoding='utf-8')
    root=pathlib.Path(args.output).resolve().parent/('host-fixtures-'+uuid.uuid4().hex); root.mkdir()
    results=[]
    def case(name,fn):
        directory=root/str(len(results)); directory.mkdir()
        try: fn(directory); result={'name':name,'status':'PASS'}
        except Exception as e: result={'name':name,'status':'FAIL','reason':str(e),'trace':traceback.format_exc()}
        results.append(result); print(name,result['status'])
    host=pathlib.Path(args.host); test_host=pathlib.Path(args.test_host)
    def pair(d,old=b'AAAA',new=b'BBBB',name='보고서.xlsx'):
        target=d/name; incoming=d/('incoming-'+name); target.write_bytes(old); incoming.write_bytes(new); return target,incoming
    def replace(d,old,new,name='보고서.xlsx'):
        target,incoming=pair(d,old,new,name); before=incoming.stat(); r,code=invoke(host,request(incoming,name))
        assert code==0 and r['ok'],r; assert target.read_bytes()==new and not incoming.exists(); assert target.stat().st_ino==before.st_ino
        assert target.stat().st_birthtime_ns==before.st_birthtime_ns and target.stat().st_mtime_ns==before.st_mtime_ns
        if old==new:
            assert r['status']=='same_content_replaced',r; assert not (d/'_history').exists(); assert len(list(d.iterdir()))==1
        else:
            assert r['status']=='changed_content_replaced',r; history=list((d/'_history').iterdir()); assert len(history)==1 and history[0].read_bytes()==old
            dot=name.rfind('.'); split=dot if dot>0 else len(name); assert re.fullmatch(re.escape(name[:split])+r'_\d{8}_\d{6}'+re.escape(name[split:]),history[0].name)
        assert r['hashBytes']==(len(old)+len(new) if len(old)==len(new) else 0),r
        return r
    def missing(d):
        new=d/'incoming.xlsx'; new.write_bytes(b'new'); before=new.stat(); r,c=invoke(host,request(new)); assert c==0 and r['status']=='renamed',r
        assert (d/'보고서.xlsx').stat().st_ino==before.st_ino and not (d/'_history').exists()
    case('target missing: incoming object gets original name',missing)
    def current(d):
        p=d/'보고서.xlsx'; p.write_bytes(b'new'); before=p.stat(); r,c=invoke(host,request(p)); assert r['status']=='already_current' and c==0 and p.stat().st_ino==before.st_ino
    case('already at target: no redundant operation',current)
    case('size differs: no hash reads',lambda d:replace(d,b'a',b'new'))
    case('equal size equal SHA256: new object and times retained',lambda d:replace(d,b'same',b'same'))
    case('equal size different SHA256: old content archived',lambda d:replace(d,b'AAAA',b'BBBB'))
    case('empty files: equal and no history',lambda d:replace(d,b'',b''))
    for name in ['회의자료 (1).pdf','회의자료 (2).pdf','한글 이름.xlsx','Unicode-😀-é.txt','space name.csv','one.two.three.xlsx','extensionless','.hidden']:
        case('filename '+name,lambda d,n=name:replace(d,b'old',b'new',n))
    def long_path(d):
        deep=d/('a'*150)/('b'*150); deep.mkdir(parents=True); replace(deep,b'old',b'new','긴 경로.xlsx')
    case('long path beyond 260 characters',long_path)
    case('long filename within NTFS history suffix limit',lambda d:replace(d,b'old',b'new','a'*225+'.pdf'))
    def too_long(d):
        target,new=pair(d,name='a'*240+'.pdf'); r,_=invoke(host,request(new,target.name)); assert r['status']=='history_name_too_long',r; assert target.read_bytes()==b'AAAA' and new.read_bytes()==b'BBBB'
    case('history name too long: preserve both files',too_long)
    def collision(d):
        t,n=pair(d); h=d/'_history'; h.mkdir(); (h/'unrelated-user.txt').write_bytes(b'user'); (h/'보고서_20260930_094512.xlsx').write_bytes(b'collision'); (h/'보고서_20260930_094512_001.xlsx').write_bytes(b'collision2')
        r,_=invoke(test_host,request(n,_timestamp='20260930_094512')); assert r['ok'],r
        assert (h/'보고서_20260930_094512_002.xlsx').read_bytes()==b'AAAA'; assert (h/'unrelated-user.txt').read_bytes()==b'user' and (h/'보고서_20260930_094512.xlsx').read_bytes()==b'collision'
    case('same-second history collisions and unrelated history preservation',collision)
    def locked(d,newer):
        t,n=pair(d); h=K.CreateFileW(str(n if newer else t),0x80000000,1,None,3,0,None)
        assert h not in [None,C.c_void_p(-1).value]
        try: r,_=invoke(host,request(n)); assert r['status']==('new_file_locked' if newer else 'target_locked'),r
        finally: K.CloseHandle(h)
        assert t.read_bytes()==b'AAAA' and n.read_bytes()==b'BBBB' and not (d/'_history').exists()
    case('target locked by real Windows handle: no history or loss',lambda d:locked(d,False))
    case('incoming locked by real Windows handle: no changes',lambda d:locked(d,True))
    def denied(d):
        t,n=pair(d); h=d/'_history'; h.mkdir()
        sid=subprocess.check_output(['whoami','/user','/fo','csv','/nh'],text=True).strip().split(',')[-1].strip('"')
        subprocess.run(['icacls',str(h),'/deny','*'+sid+':(WD)'],check=True,capture_output=True)
        try: r,_=invoke(host,request(n)); assert r['status']=='permission_denied',r; assert t.read_bytes()==b'AAAA' and n.read_bytes()==b'BBBB'
        finally: subprocess.run(['icacls',str(h),'/remove:d','*'+sid],check=True,capture_output=True)
    case('history write permission denied using real ACL',denied)
    def failure(d,fault,same=False):
        t,n=pair(d,new=b'AAAA' if same else b'BBBB'); value=b'AAAA' if same else b'BBBB'
        r,_=invoke(test_host,request(n,_fault=fault)); assert n.read_bytes()==value,r
        if fault=='old_move': assert r['status']=='permission_denied' and t.read_bytes()==b'AAAA',r
        elif fault=='rollback': assert r['status']=='rollback_failed' and r['rollbackError'] and r['changed'] and not t.exists() and pathlib.Path(r['oldPath']).read_bytes()==b'AAAA',r
        else: assert r['status']=='rename_failed_rolled_back' and t.read_bytes()==b'AAAA' and not r['changed'],r
    case('old history move failure: both originals unchanged',lambda d:failure(d,'old_move'))
    case('history move succeeded then incoming rename failed: rollback succeeds',lambda d:failure(d,'new_move'))
    case('same-content incoming rename failure: old object rolled back',lambda d:failure(d,'new_move',True))
    case('rollback failed: accurate retained old/new paths and errors',lambda d:failure(d,'rollback'))
    def no_target_failure(d):
        p=d/'incoming'; p.write_bytes(b'new'); r,_=invoke(test_host,request(p,_fault='new_move')); assert r['status']=='rename_failed' and p.read_bytes()==b'new'
    case('target rename failure without prior target preserves incoming',no_target_failure)
    def cleanup_failure(d):
        t,n=pair(d,new=b'AAAA'); r,_=invoke(test_host,request(n,_fault='cleanup')); assert r['ok'] and r['status']=='cleanup_required' and t.read_bytes()==b'AAAA' and pathlib.Path(r['oldPath']).read_bytes()==b'AAAA' and not (d/'_history').exists(),r
    case('same-content cleanup failure keeps newest and residual copy',cleanup_failure)
    def crash(d,same=False):
        t,n=pair(d,new=b'AAAA' if same else b'BBBB'); p=subprocess.run([str(test_host),ORIGIN],input=frame(request(n,_fault='crash_after_old_move')),capture_output=True,timeout=10)
        assert p.returncode==77 and not p.stdout and n.exists(); remaining=[p for p in d.rglob('*') if p.is_file()]; assert len(remaining)==2
        assert any(p.read_bytes()==b'AAAA' for p in remaining)
    case('forced interruption after history move preserves both versions',lambda d:crash(d))
    case('forced interruption after equal-content staging preserves both objects',lambda d:crash(d,True))
    def simultaneous(d,count,same_target=True):
        inputs=[]; contents={b'initial'}
        if same_target: (d/'report.bin').write_bytes(b'initial')
        for i in range(count):
            n=d/f'incoming-{i}.bin'; content=f'payload-{i:04}'.encode(); n.write_bytes(content); contents.add(content); inputs.append((n,'report.bin' if same_target else f'report-{i}.bin'))
        with concurrent.futures.ThreadPoolExecutor(max_workers=count) as pool: replies=list(pool.map(lambda v:invoke(host,request(v[0],v[1])),inputs))
        assert all(r['ok'] and code==0 for r,code in replies),replies
        if same_target: assert {p.read_bytes() for p in d.rglob('*') if p.is_file()}==contents and len(list((d/'_history').iterdir()))==count
        else: assert len(list(d.iterdir()))==count and not (d/'_history').exists()
    for count in [2,8,16]: case(f'{count} simultaneous processes same target (Chrome/Edge simulation)',lambda d,n=count:simultaneous(d,n))
    case('different targets process in parallel',lambda d:simultaneous(d,8,False))
    def hardlink(d):
        t,n=pair(d); os.link(t,d/'unrelated-link'); r,_=invoke(host,request(n)); assert r['status']=='unsupported_file' and t.read_bytes()==b'AAAA' and n.read_bytes()==b'BBBB'
    case('hardlinked target rejected without changing unrelated link',hardlink)
    def history_file(d):
        t,n=pair(d); (d/'_history').write_bytes(b'user'); r,_=invoke(host,request(n)); assert not r['ok'] and t.read_bytes()==b'AAAA' and n.read_bytes()==b'BBBB' and (d/'_history').read_bytes()==b'user'
    case('history path occupied by unrelated file',history_file)
    def stream_large(d):
        t=d/'report.bin'; n=d/'incoming.bin'
        for p in [t,n]:
            with p.open('wb') as f:
                for _ in range(64): f.write(b'x'*1024*1024)
        before=n.stat(); r,_=invoke(host,request(n,t.name)); assert r['status']=='same_content_replaced' and r['hashBytes']==128*1024*1024 and t.stat().st_ino==before.st_ino and not (d/'_history').exists(),r
    case('64 MiB file streaming SHA256 processes 128 MiB with bounded buffer',stream_large)
    def protocol(d,value=None,raw=None,status='invalid_request',origin=ORIGIN):
        r,c=invoke(host,value or {'protocolVersion':1,'operation':'ping'},origin=origin,raw=raw); assert r['status']==status and c==1,r; assert not list(d.iterdir())
    case('Native Messaging ping and version',lambda d: (lambda r: (r[0]['status']=='ready' and r[0]['version']==args.expected_version and r[1]==0) or (_ for _ in ()).throw(AssertionError(r)))(invoke(host,{'protocolVersion':1,'operation':'ping'})))
    for name,val,status in [('future protocol',{'protocolVersion':2,'operation':'ping'},'protocol_mismatch'),('missing version',{'operation':'ping'},'invalid_request'),('numeric coercion forbidden',{'protocolVersion':'1','operation':'ping'},'invalid_request'),('unknown operation',{'protocolVersion':1,'operation':'delete'},'invalid_request'),('extra ping property',{'protocolVersion':1,'operation':'ping','newPath':'C:\\file'},'invalid_request'),('fault injection excluded in production',request(root/'missing',_fault='new_move'),'invalid_request')]:
        case(name,lambda d,v=val,s=status:protocol(d,v,status=s))
    case('untrusted caller origin denied',lambda d:protocol(d,status='origin_denied',origin='chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/'))
    for name,raw,status in [('short frame',b'\x01','invalid_frame'),('oversized frame',struct.pack('<I',65537),'invalid_frame'),('truncated payload',struct.pack('<I',20)+b'{}','truncated_frame'),('duplicate JSON keys',b'{"protocolVersion":1,"protocolVersion":1,"operation":"ping"}','invalid_request'),('non-UTF8',b'{"protocolVersion":1,"operation":"\xff"}','invalid_request'),('invalid surrogate',b'{"protocolVersion":1,"operation":"\\ud800"}','invalid_request'),('nested JSON',b'{"protocolVersion":1,"operation":{}}','invalid_request'),('trailing JSON',b'{"protocolVersion":1,"operation":"ping"}{}','invalid_request')]:
        wire=raw if status in ['invalid_frame','truncated_frame'] else struct.pack('<I',len(raw))+raw
        case(name,lambda d,b=wire,s=status:protocol(d,raw=b,status=s))
    for bad in ['C:relative','\\\\server\\share\\file','\\\\?\\C:\\file','C:\\a\\..\\b','C:\\a.txt:stream','C:\\NUL.txt','C:\\a.','C:\\a ']:
        case('reject path '+bad,lambda d,p=bad:protocol(d,request(p),status='invalid_path'))
    def single_request(d):
        ping=frame({'protocolVersion':1,'operation':'ping'}); p=subprocess.run([str(host),ORIGIN],input=ping+ping,capture_output=True,timeout=5); assert p.returncode==0 and len(p.stdout)==struct.unpack('<I',p.stdout[:4])[0]+4
    case('one input request and response only then exit',single_request)
    output={'environment':{'platform':sys.platform,'windows':sys.getwindowsversion().build,'fixtureRoot':str(root)},'passed':sum(r['status']=='PASS' for r in results),'failed':sum(r['status']=='FAIL' for r in results),'notRun':0,'tests':results}
    pathlib.Path(args.output).write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n','utf-8'); return int(output['failed']!=0)

if __name__=='__main__':
    p=argparse.ArgumentParser()
    for key in ['host','test-host','output']: p.add_argument('--'+key,required=True)
    p.add_argument('--expected-version',default='0.1.0')
    sys.exit(run(p.parse_args()))
