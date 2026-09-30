"""Fail closed: never equate a missing, failed or skipped gate with PASS."""
import argparse, hashlib, json, pathlib, sys
GATES=['host','extension','chromeContract','edgeContract','chromeE2E','edgeE2E','sameContent','changedHistory','lockedPreservation','completionOrder','idleZero','installerLifecycle','nativeHandshake','singleDistribution','limitations','checksum']
def evaluate(evidence):
    failures={key:evidence.get('gates',{}).get(key,'NOT RUN') for key in GATES if evidence.get('gates',{}).get(key)!='PASS'}
    if evidence.get('channel')!='stable': failures['channel']=evidence.get('channel','missing')
    return failures
if __name__=='__main__':
    p=argparse.ArgumentParser(); p.add_argument('--evidence',required=True); p.add_argument('--msi',required=True); p.add_argument('--checksums',required=True); a=p.parse_args()
    evidence=json.loads(pathlib.Path(a.evidence).read_text('utf-8')); failures=evaluate(evidence)
    file=pathlib.Path(a.msi)
    with file.open('rb') as stream: digest=hashlib.file_digest(stream,'sha256').hexdigest()
    lines=pathlib.Path(a.checksums).read_text('ascii').splitlines()
    if digest+'  '+file.name not in lines: failures['checksum']='FAIL'
    if failures:
        print(json.dumps({'stableAllowed':False,'blocked':failures},ensure_ascii=False,indent=2)); sys.exit(1)
    print(json.dumps({'stableAllowed':True,'sha256':digest,'tag':'download-version-manager-v0.1.0'}))
