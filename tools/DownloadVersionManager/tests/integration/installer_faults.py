"""Opt-in late failure trials. Existing installations stop preflight. If this
trial leaves its exact product registered, use only the official MSI removal API;
never delete Windows Installer registry state or alter OS permissions."""
import argparse, json, pathlib, uuid
import installer as life

def run(args):
    output=pathlib.Path(args.output).resolve(); output.parent.mkdir(parents=True,exist_ok=True)
    expected='{'+str(uuid.uuid5(uuid.NAMESPACE_URL,'dvm/evaluation/'+args.version)).upper()+'}'
    trials=[]
    for name,msi in [('post-publication-deferred',args.late),('post-InstallExecute-immediate',args.postexecute)]:
        state=life.fixture(msi,output.parent/(name+'-state.json'))
        app=pathlib.Path(state['install'])
        life.execute(state,msi,['/i','INSTALLFOLDER='+str(app)],name+'-failure',1603)
        life.check_files(state)
        registrations=life.related()
        assert not (app/'DownloadVersionHost.exe').exists() and all(life.value(key) is None for key in life.KEYS)
        state['tests'].append({'name':'file and native registration rollback','status':'PASS'})
        state['tests'].append({'name':'MSI product registration rollback','status':'FAIL' if registrations else 'PASS','relatedProducts':registrations})
        life.save(state)
        if registrations:
            assert registrations==[expected], 'Unexpected product registration; stop without cleanup.'
            code=life.execute(state,args.production,['/i','INSTALLFOLDER='+str(app)],'reinstall-without-cleanup',(0,1638))
            state['tests'][-1]['status']='PASS' if code==0 else 'FAIL'
            life.save(state)
            # This product did not exist at preflight and was created by this
            # exact isolated trial. No other product or browser setting is changed.
            life.execute(state,msi,['/x'],'official-removal-of-trial-registration')
        life.preflight(); life.check_files(state)
        life.execute(state,args.production,['/i','INSTALLFOLDER='+str(app)],'fresh-install-after-failure-cleanup')
        life.check_registered(state)
        life.execute(state,args.production,['/x'],'trial-final-uninstall')
        life.preflight(); life.check_files(state)
        assert not (app/'DownloadVersionHost.exe').exists()
        state['cleaned']=True; state['finished']=True; life.save(state)
        trials.append({'name':name,'state':state['state'],'tests':state['tests'],'cleaned':True})
        output.write_text(json.dumps({'environment':'current Windows user, dedicated fixture; not a clean VM','trials':trials},indent=2)+'\n','utf8')
    summary={'environment':'current Windows user, dedicated fixture; not a clean VM','trials':trials,
             'passed':sum(t['status']=='PASS' for r in trials for t in r['tests']),
             'failed':sum(t['status']=='FAIL' for r in trials for t in r['tests']),'notRun':0}
    output.write_text(json.dumps(summary,indent=2)+'\n','utf8'); print(json.dumps(summary,indent=2))
    return int(summary['failed']!=0)

if __name__=='__main__':
    p=argparse.ArgumentParser()
    for name in ['production','late','postexecute','output']: p.add_argument('--'+name,required=True)
    p.add_argument('--version',default='0.1.0'); raise SystemExit(run(p.parse_args()))
