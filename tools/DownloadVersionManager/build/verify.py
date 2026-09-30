"""Read MSI tables and extract embedded payload without installing the product."""
import argparse, ctypes as C, hashlib, json, pathlib, shutil, subprocess, sys, tempfile
from ctypes import wintypes as W
msi = C.WinDLL('msi', use_last_error=True)
msi.MsiOpenDatabaseW.argtypes = [W.LPCWSTR, W.LPCWSTR, C.POINTER(W.UINT)]
msi.MsiDatabaseOpenViewW.argtypes = [W.UINT, W.LPCWSTR, C.POINTER(W.UINT)]
msi.MsiViewExecute.argtypes = [W.UINT, W.UINT]
msi.MsiViewFetch.argtypes = [W.UINT, C.POINTER(W.UINT)]
msi.MsiRecordGetStringW.argtypes = [W.UINT, W.UINT, W.LPWSTR, C.POINTER(W.DWORD)]
msi.MsiRecordGetFieldCount.argtypes = [W.UINT]
msi.MsiCloseHandle.argtypes = [W.UINT]

def query(file, sql):
    db = W.UINT(); view = W.UINT()
    if msi.MsiOpenDatabaseW(str(file), None, C.byref(db)): raise RuntimeError('MSI open failed')
    try:
        if msi.MsiDatabaseOpenViewW(db, sql, C.byref(view)): return []
        if msi.MsiViewExecute(view, 0): raise RuntimeError('MSI query failed')
        rows = []
        while True:
            rec = W.UINT(); err = msi.MsiViewFetch(view, C.byref(rec))
            if err == 259: return rows
            if err: raise RuntimeError('MSI fetch failed')
            try:
                row = []
                for i in range(1, msi.MsiRecordGetFieldCount(rec) + 1):
                    n = W.DWORD(65536); b = C.create_unicode_buffer(n.value)
                    if msi.MsiRecordGetStringW(rec, i, b, C.byref(n)): raise RuntimeError('MSI field failed')
                    row.append(b.value)
                rows.append(row)
            finally: msi.MsiCloseHandle(rec)
    finally:
        if view.value: msi.MsiCloseHandle(view)
        msi.MsiCloseHandle(db)

def digest(p):
    with p.open('rb') as f: return hashlib.file_digest(f, 'sha256').hexdigest()

def verify(args):
    file = pathlib.Path(args.msi).resolve(); payload = pathlib.Path(args.payload).resolve()
    props = dict(query(file, 'SELECT `Property`, `Value` FROM `Property`'))
    assert props['ProductVersion'] == args.version
    assert props.get('ALLUSERS', '') != '1'
    assert props['MSIRESTARTMANAGERCONTROL'] == 'Disable' and props['REBOOT'] == 'ReallySuppress'
    regs = query(file, 'SELECT `Root`, `Key`, `Name`, `Value` FROM `Registry`')
    assert all(r[0] == '1' for r in regs), regs
    native = [r for r in regs if '\\NativeMessagingHosts\\' in r[1]]
    assert len(native) == 2 and all(r[3] == '[INSTALLFOLDER]native-host.json' for r in native)
    assert not any(any(word in r[1].lower() for word in ['\\run', 'policies', '\\extensions\\']) for r in regs)
    assert not query(file, 'SELECT * FROM `ServiceInstall`')
    assert not query(file, 'SELECT * FROM `ServiceControl`')
    assert not query(file, 'SELECT * FROM `RemoveFile` WHERE `FileName` IS NOT NULL')
    actions = query(file, 'SELECT `Action`, `Type`, `Source`, `Target` FROM `CustomAction`')
    assert all(a[0] in ['DvmPreflight', 'SetARPINSTALLLOCATION', 'SetINSTALLFOLDER'] for a in actions), actions
    files = query(file, 'SELECT `File`, `FileName` FROM `File`')
    assert len(files) == len(list(payload.rglob('*'))) - len([p for p in payload.rglob('*') if p.is_dir()])
    assert not any('_history' in r[1] or '.Tests.' in r[1] for r in files)
    # Administrative extraction runs AdminExecuteSequence, not InstallExecuteSequence;
    # it creates no NativeMessagingHosts registration and is not a lifecycle PASS.
    extract = file.parent / ('extract-' + args.version)
    extract.mkdir(exist_ok=True)
    p = subprocess.run(['msiexec.exe', '/a', str(file), '/qn', 'TARGETDIR=' + str(extract), 'REBOOT=ReallySuppress'], capture_output=True, timeout=90)
    assert p.returncode == 0, p.returncode
    found = list(extract.rglob('DownloadVersionHost.exe')); assert len(found) == 1, found
    root = found[0].parent
    matches = {}
    for source in payload.rglob('*'):
        if source.is_file():
            rel = source.relative_to(payload); actual = root / rel
            assert actual.is_file() and digest(actual) == digest(source), rel
            matches[rel.as_posix()] = digest(actual)
    ext = json.loads((root / 'extension/manifest.json').read_text('utf-8'))
    native_manifest = json.loads((root / 'native-host.json').read_text('utf-8'))
    assert ext['version'] == args.version and ext['manifest_version'] == 3
    assert native_manifest['path'] == 'DownloadVersionHost.exe' and len(native_manifest['allowed_origins']) == 1
    assert b'crash_after_old_move' not in (root / 'DownloadVersionHost.exe').read_bytes()
    result = {'status': 'PASS', 'version': args.version, 'files': len(matches), 'registry': len(regs), 'perUser': True, 'nativeRegistrations': len(native), 'services': 0, 'startup': 0, 'sha256': digest(file), 'payload': matches, 'lifecycle': 'NOT RUN', 'extensionActivation': 'NOT RUN'}
    pathlib.Path(args.output).write_text(json.dumps(result, indent=2) + '\n', 'utf-8')
    print(json.dumps({k:v for k,v in result.items() if k != 'payload'}))

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    for name in ['msi', 'payload', 'version', 'output']: p.add_argument('--' + name, required=True)
    verify(p.parse_args())
