"""Opt-in late failure trials. Existing installations stop preflight. If this
trial leaves its exact product registered, use only the official MSI removal API;
never delete Windows Installer registry state or alter OS permissions."""
import argparse, json, pathlib, subprocess, uuid

def run(args):
    # Keep evidence/control-flow tests portable without loading Windows APIs.
    import installer as life
    output=pathlib.Path(args.output).resolve(); output.parent.mkdir(parents=True,exist_ok=True)
    expected='{'+str(uuid.uuid5(uuid.NAMESPACE_URL,'dvm/evaluation/'+args.version)).upper()+'}'
    packages=[('post-publication-deferred',args.late),('post-InstallExecute-immediate',args.postexecute)]
    trials=[{'name':name,'state':None,'tests':[],'cleaned':False,'finished':False,'status':'NOT RUN'} for name,_ in packages]

    def checkpoint(state=None):
        summary={'environment':'current Windows user, dedicated fixture; not a clean VM','trials':trials,
                 'passed':sum(t['status']=='PASS' for r in trials for t in r['tests']),
                 'failed':sum(t['status']=='FAIL' for r in trials for t in r['tests']),
                 'notRun':sum(t['status']=='NOT RUN' for r in trials for t in r['tests'])+sum(r['status']=='NOT RUN' and not r['tests'] for r in trials)}
        try:
            if state is not None: life.save(state)
        finally:
            output.write_text(json.dumps(summary,indent=2)+'\n','utf8')
        return summary

    checkpoint()
    for trial,(name,msi) in zip(trials,packages):
        state=None; phase='isolated trial preflight'; trial['status']='RUNNING'
        try:
            state=life.fixture(msi,output.parent/(name+'-state.json'))
            trial['state']=state['state']; trial['tests']=state['tests']
            state['cleaned']=False; state['finished']=False
            app=pathlib.Path(state['install'])
            phase=name+'-failure'
            life.execute(state,msi,['/i','INSTALLFOLDER='+str(app)],phase,1603)
            phase='file and native registration rollback'
            life.check_files(state)
            if (app/'DownloadVersionHost.exe').exists() or any(life.value(key) is not None for key in life.KEYS):
                raise AssertionError('Failed installation retained the native host file or registration.')
            state['tests'].append({'name':phase,'status':'PASS'})
            phase='MSI product registration rollback'
            registrations=life.related()
            state['tests'].append({'name':phase,'status':'FAIL' if registrations else 'PASS','relatedProducts':registrations})
            checkpoint(state)
            if registrations:
                phase='verify exact trial product before cleanup'
                if registrations!=[expected]:
                    raise AssertionError('Unexpected product registration; stop without cleanup.')
                phase='reinstall-without-cleanup'
                code=life.execute(state,args.production,['/i','INSTALLFOLDER='+str(app)],phase,(0,1638))
                state['tests'][-1]['status']='PASS' if code==0 else 'FAIL'
                checkpoint(state)
                # This product did not exist at preflight and was created by this
                # exact isolated trial. No other product or browser setting is changed.
                phase='official-removal-of-trial-registration'
                life.execute(state,msi,['/x'],phase)
            phase='verify clean preflight and preserved files before reinstall'
            life.preflight(); life.check_files(state)
            phase='fresh-install-after-failure-cleanup'
            life.execute(state,args.production,['/i','INSTALLFOLDER='+str(app)],phase)
            phase='verify fresh installation after failure cleanup'
            life.check_registered(state)
            phase='trial-final-uninstall'
            life.execute(state,args.production,['/x'],phase)
            phase='verify final uninstall and preserved files'
            life.preflight(); life.check_files(state)
            if (app/'DownloadVersionHost.exe').exists():
                raise AssertionError('Final uninstall retained the native host file.')
            state['cleaned']=True; state['finished']=True
            trial['cleaned']=True; trial['finished']=True
            trial['status']='FAIL' if any(t['status']=='FAIL' for t in trial['tests']) else 'PASS'
            checkpoint(state)
        except Exception as error:
            # Preserve unexpected evidence before stopping. Never add recovery
            # actions here: a failed assertion does not authorize forced cleanup.
            status='NOT RUN' if isinstance(error,subprocess.TimeoutExpired) else 'FAIL'
            failure={'name':phase,'status':status,'reason':type(error).__name__+': '+str(error)}
            if trial['tests'] and trial['tests'][-1]['name']==phase and trial['tests'][-1]['status']==status:
                trial['tests'][-1]['reason']=failure['reason']
            else: trial['tests'].append(failure)
            trial['status']=status
            checkpoint(state)
            raise
    summary=checkpoint(); print(json.dumps(summary,indent=2))
    return int(summary['failed']!=0)

if __name__=='__main__':
    p=argparse.ArgumentParser()
    for name in ['production','late','postexecute','output']: p.add_argument('--'+name,required=True)
    p.add_argument('--version',default='0.1.0'); raise SystemExit(run(p.parse_args()))
