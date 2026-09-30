"""Completion ordering, durable object selection and bounded state fixtures."""
import concurrent.futures, pathlib, subprocess, uuid, winreg

def add_cases(case,host,test_host,pair,request,invoke,frame,order_name,order_key):
    def send(exe,path,at,name='report.bin',**extra):
        r,c=invoke(exe,request(path,name,completedAt=at,**extra)); return r,c
    def reversed_requests(d,same=False):
        target=d/'report.bin'; a=d/'a.bin'; b=d/'b.bin'
        target.write_bytes(b'equal' if same else b'initial'); a.write_bytes(b'equal' if same else b'A-earlier'); b.write_bytes(b'equal' if same else b'B-later')
        newest=b.stat(); first,_=send(host,b,2000); late,_=send(host,a,1000)
        assert first['ok'] and late['ok'],(first,late)
        assert target.stat().st_ino==newest.st_ino and target.stat().st_mtime_ns==newest.st_mtime_ns
        assert target.read_bytes()==(b'equal' if same else b'B-later') and not a.exists() and not b.exists()
        if same: assert late['status']=='superseded_same_content' and not (d/'_history').exists()
        else:
            assert late['status']=='superseded_archived'
            assert {p.read_bytes() for p in (d/'_history').iterdir()}=={b'initial',b'A-earlier'}
    case('completion order: B processed before A still leaves newer B object',lambda d:reversed_requests(d))
    case('completion order: equal stale download removed, newest object kept, no history',lambda d:reversed_requests(d,True))
    def parallel(d):
        target=d/'report.bin'; target.write_bytes(b'initial'); values={b'initial'}; inputs=[]
        for i in range(16):
            p=d/f'incoming-{i}.bin'; content=f'payload-{i:04}'.encode(); p.write_bytes(content); values.add(content)
            inputs.append((p,request(p,'report.bin',downloadId=1,completedAt=1000+i)))
        newest=inputs[-1][0].stat().st_ino
        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            results=list(pool.map(lambda x:invoke(host,x[1]),reversed(inputs)))
        assert all(r['ok'] and c==0 for r,c in results),results
        assert target.stat().st_ino==newest and target.read_bytes()==b'payload-0015'
        assert {p.read_bytes() for p in d.rglob('*') if p.is_file()}==values
        assert len(list((d/'_history').iterdir()))==16
    case('completion order: 16 processes and colliding browser IDs retain maximum endTime',parallel)
    def tied(d):
        target,new=pair(d,name='report.bin'); first,_=send(host,target,1000); before=target.stat().st_ino
        r,_=send(host,new,1000); assert first['ok'] and r['status']=='completion_order_ambiguous',r
        assert target.stat().st_ino==before and target.read_bytes()==b'AAAA' and new.read_bytes()==b'BBBB' and not (d/'_history').exists()
    case('equal completion timestamps: preserve both, do not invent ordering',tied)
    def reused(d):
        target,new=pair(d,name='report.bin'); token=uuid.uuid4().hex; send(host,target,1000,requestToken=token)
        r,_=send(host,new,2000,requestToken=token); assert r['status']=='request_token_reused',r
        assert target.read_bytes()==b'AAAA' and new.read_bytes()==b'BBBB'
    case('download request token cannot be reused for another object',reused)
    def invalid(d,field,value):
        target,new=pair(d,name='report.bin'); r,_=invoke(host,request(new,target.name,**{field:value}))
        assert r['status']=='invalid_request' and target.read_bytes()==b'AAAA' and new.read_bytes()==b'BBBB',r
    for field,value in [('completedAt',0),('completedAt',253402300800000),('requestToken','x'*32),('requestToken','a'*31)]:
        case('invalid completion metadata '+field+' '+str(value),lambda d,f=field,v=value:invalid(d,f,v))
    def missing(d,field):
        target,new=pair(d,name='report.bin'); message=request(new,target.name); del message[field]
        r,_=invoke(host,message); assert r['status']=='invalid_request' and target.read_bytes()==b'AAAA' and new.read_bytes()==b'BBBB',r
    for field in ['completedAt','requestToken']: case('required completion field '+field,lambda d,f=field:missing(d,f))
    case('old protocol rejected explicitly',lambda d: (lambda r: r[0]['status']=='protocol_mismatch' or (_ for _ in ()).throw(AssertionError(r)))(invoke(host,{'protocolVersion':1,'operation':'ping'})))
    def prewrite_failure(d):
        target,new=pair(d,name='report.bin'); r,_=send(test_host,new,2000,_fault='order_write')
        assert r['status']=='order_state_unavailable' and target.read_bytes()==b'AAAA' and new.read_bytes()==b'BBBB' and not (d/'_history').exists(),r
    case('order state write failure precedes every file change',prewrite_failure)
    def crashed(d,fault):
        target,new=pair(d,name='report.bin'); send(host,target,1000)
        newest=new.stat().st_ino
        p=subprocess.run([str(test_host),'chrome-extension://knahdnpoplcleaoklikjmgpocealjogc/'],input=frame(request(new,target.name,completedAt=2000,_fault=fault)),capture_output=True,timeout=10)
        assert p.returncode==77 and not p.stdout
        incoming=d/'delayed.bin'; incoming.write_bytes(b'delayed'); r,_=send(host,incoming,1500)
        assert r['ok'],r
        if fault=='crash_after_new_move':
            assert r['status']=='superseded_archived' and target.stat().st_ino==newest and target.read_bytes()==b'BBBB'
            assert {p.read_bytes() for p in d.rglob('*') if p.is_file()}=={b'AAAA',b'BBBB',b'delayed'}
        else:
            assert r['status']=='changed_content_replaced' and target.read_bytes()==b'delayed' and new.read_bytes()==b'BBBB'
    case('process interrupted after preparation: unrenamed object is not a committed head',lambda d:crashed(d,'crash_after_order_prepare'))
    case('process interrupted after incoming rename: file ID recognizes newer committed head',lambda d:crashed(d,'crash_after_new_move'))
    def rollback(d,failed=False):
        target,new=pair(d,name='report.bin'); send(host,target,1000)
        r,_=send(test_host,new,2000,_fault='rollback' if failed else 'new_move')
        assert r['status']==('rollback_failed' if failed else 'rename_failed_rolled_back'),r
        late=d/'delayed.bin'; late.write_bytes(b'delayed'); r,_=send(host,late,1500)
        if failed:
            assert r['status']=='order_state_uncertain' and not target.exists() and late.read_bytes()==b'delayed' and new.read_bytes()==b'BBBB'
            assert any(p.read_bytes()==b'AAAA' for p in (d/'_history').iterdir())
        else: assert r['ok'] and target.read_bytes()==b'delayed' and new.read_bytes()==b'BBBB',r
    case('successful rollback selects previous committed file ID',rollback)
    case('failed rollback and detached order state preserve subsequent delayed input',lambda d:rollback(d,True))
    def external(d,newer=False):
        target,new=pair(d,name='report.bin'); send(host,target,2000)
        other=d/'external.bin'; other.write_bytes(b'external'); other.replace(target)
        r,_=send(host,new,3000 if newer else 1000)
        if newer: assert r['ok'] and target.read_bytes()==b'BBBB' and any(p.read_bytes()==b'external' for p in (d/'_history').iterdir()),r
        else: assert r['status']=='order_state_uncertain' and target.read_bytes()==b'external' and new.read_bytes()==b'BBBB',r
    case('external target replacement cannot silently discard ordering for delayed request',external)
    case('later completion safely establishes head after external replacement',lambda d:external(d,True))
    def corrupt(d):
        target,new=pair(d,name='report.bin'); send(host,target,1000)
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,order_key,0,winreg.KEY_READ|winreg.KEY_SET_VALUE|winreg.KEY_WOW64_64KEY) as key:
            data,typ=winreg.QueryValueEx(key,order_name(target,target.name)); assert typ==winreg.REG_BINARY and len(data)==138
            assert str(target).encode('utf8') not in data and b'AAAA' not in data
            data=data[:-1]+bytes([data[-1]^1]); winreg.SetValueEx(key,order_name(target,target.name),0,winreg.REG_BINARY,data)
        r,_=send(host,new,2000); assert r['status']=='order_state_invalid' and target.read_bytes()==b'AAAA' and new.read_bytes()==b'BBBB',r
    case('bounded order state integrity failure preserves files',corrupt)
    def unrelated(d):
        marker='UnrelatedFixture-'+uuid.uuid4().hex
        with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER,order_key,0,winreg.KEY_READ|winreg.KEY_SET_VALUE|winreg.KEY_WOW64_64KEY) as key:
            winreg.SetValueEx(key,marker,0,winreg.REG_SZ,'preserve')
            try:
                target,new=pair(d,name='report.bin'); r,_=send(host,new,1000); assert r['ok'] and winreg.QueryValueEx(key,marker)[0]=='preserve'
            finally: winreg.DeleteValue(key,marker)
    case('completion state updates preserve unrelated registry values',unrelated)
