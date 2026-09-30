"""Windows release construction; no installation or interactive browser actions."""
from __future__ import annotations
import argparse, base64, hashlib, json, os, pathlib, shutil, subprocess, sys, uuid
import xml.etree.ElementTree as ET

PRODUCT = pathlib.Path(__file__).resolve().parents[1]
REPO = PRODUCT.parents[1]
NS = 'http://wixtoolset.org/schemas/v4/wxs'
ET.register_namespace('', NS)

def sha(p):
    with open(p, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def command(args, cwd, env=None, log=None):
    result = subprocess.run([str(x) for x in args], cwd=cwd, env=env, capture_output=True, timeout=180)
    output = result.stdout + result.stderr
    if log: pathlib.Path(log).write_bytes(output)
    if result.returncode:
        print(output.decode('utf-8', errors='replace'))
        raise RuntimeError(f'{pathlib.Path(args[0]).name} exit {result.returncode}; log={log}')
    return result

def find_msvc(explicit):
    if explicit: return pathlib.Path(explicit).resolve()
    if os.environ.get('VCToolsInstallDir'): return pathlib.Path(os.environ['VCToolsInstallDir'])
    local = REPO / '.tools/image-copy-save-native/msvc'
    if (local / 'bin/Hostx64/x64/cl.exe').is_file(): return local
    vswhere = pathlib.Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/Installer/vswhere.exe'
    if vswhere.is_file():
        roots = subprocess.check_output([str(vswhere), '-all', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath'], text=True).splitlines()
        for root in roots:
            versions = sorted((pathlib.Path(root) / 'VC/Tools/MSVC').glob('*'), reverse=True)
            if versions: return versions[0]
    raise RuntimeError('MSVC C++ x64 toolchain required; pass --msvc. No system toolchain is installed automatically.')

def find_sdk(explicit):
    if explicit: root = pathlib.Path(explicit).resolve()
    elif (REPO / '.tools/image-copy-save-native/sdk/Include').is_dir(): root = REPO / '.tools/image-copy-save-native/sdk'
    else:
        import winreg
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r'SOFTWARE\Microsoft\Windows Kits\Installed Roots') as key:
            root = pathlib.Path(winreg.QueryValueEx(key, 'KitsRoot10')[0])
    versions = sorted((root / 'Include').glob('10.0.*'), key=lambda p: tuple(map(int, p.name.split('.'))), reverse=True)
    if not versions: raise RuntimeError('Windows SDK headers and x64 libraries required.')
    return root, versions[0].name

def extension_id(manifest):
    hex_id = hashlib.sha256(base64.b64decode(manifest['key'], validate=True)).hexdigest()[:32]
    return ''.join(chr(97 + int(x, 16)) for x in hex_id)

def build(args):
    sys.stdout.reconfigure(encoding='utf-8')
    if sys.platform != 'win32': raise RuntimeError('Build requires Windows x64.')
    spec = json.loads((PRODUCT / 'version.json').read_text('utf-8'))
    version = args.version or spec['version']
    if len(version.split('.')) != 3 or any(not x.isdecimal() for x in version.split('.')): raise ValueError('Invalid version')
    out = REPO / 'artifacts/download-version-manager' / (version + '-evaluation')
    out.mkdir(parents=True, exist_ok=True)
    build_dir = out / 'build'; build_dir.mkdir(exist_ok=True)
    manifest = json.loads((PRODUCT / 'extension/manifest.json').read_text('utf-8'))
    if manifest['version'] != spec['version'] or extension_id(manifest) != spec['developmentExtensionId']: raise RuntimeError('Extension version/identity mismatch')
    origin = 'chrome-extension://' + extension_id(manifest) + '/'
    (build_dir / 'identity.h').write_text(f'#pragma once\n#define DVM_VERSION L"{version}"\n#define DVM_ORIGIN L"{origin}"\n', 'utf-8')
    msvc = find_msvc(args.msvc); sdk, sdkver = find_sdk(args.sdk)
    includes = [msvc / 'include'] + [sdk / 'Include' / sdkver / x for x in ['ucrt', 'shared', 'um']]
    env = os.environ.copy()
    env['LIB'] = ';'.join(str(p) for p in [msvc / 'lib/x64', sdk / 'Lib' / sdkver / 'ucrt/x64', sdk / 'Lib' / sdkver / 'um/x64'])
    env['PATH'] = str(msvc / 'bin/Hostx64/x64') + ';' + str(sdk / 'bin' / sdkver / 'x64') + ';' + env['PATH']
    cl = msvc / 'bin/Hostx64/x64/cl.exe'
    common = ['/nologo', '/std:c++17', '/EHsc', '/MT', '/O2', '/W4', '/WX', '/utf-8', '/guard:cf', '/DUNICODE', '/D_UNICODE', '/DWIN32_LEAN_AND_MEAN', '/DNOMINMAX', '/D_WIN32_WINNT=0x0A00']
    common += ['/I' + str(p) for p in includes + [build_dir]]
    link = ['/link', '/DYNAMICBASE', '/NXCOMPAT', '/GUARD:CF', '/WX', '/MACHINE:X64']
    rc = sdk / 'bin' / sdkver / 'x64/rc.exe'
    numbers = version.replace('.', ',') + ',0'
    rc_text = f'''1 24 "{(PRODUCT / 'source/host.manifest').as_posix()}"
1 VERSIONINFO
 FILEVERSION {numbers}
 PRODUCTVERSION {numbers}
 FILETYPE 1
BEGIN
 BLOCK "StringFileInfo"
 BEGIN
  BLOCK "040904B0"
  BEGIN
   VALUE "FileDescription", "DownloadVersionManager Native Host"
   VALUE "FileVersion", "{version}"
   VALUE "ProductVersion", "{version}"
   VALUE "ProductName", "DownloadVersionManager"
  END
 END
 BLOCK "VarFileInfo"
 BEGIN
  VALUE "Translation", 0x0409, 1200
 END
END
'''
    (build_dir / 'host.rc').write_text(rc_text, 'utf-8')
    command([rc, '/nologo', '/fo', build_dir / 'host.res', build_dir / 'host.rc'], build_dir, env, build_dir / 'resource.log')
    binaries = {}
    for testing in [False, True]:
        location = build_dir / ('test' if testing else 'production'); location.mkdir(exist_ok=True)
        binary = location / ('DownloadVersionHost.Tests.exe' if testing else 'DownloadVersionHost.exe')
        if not args.package_only:
            command([cl] + common + (['/DDVM_TESTING'] if testing else []) + ['/Fe' + str(binary), PRODUCT / 'source/host.cpp', PRODUCT / 'source/engine.cpp', build_dir / 'host.res'] + link + ['/SUBSYSTEM:WINDOWS', 'bcrypt.lib', 'shell32.lib'], location, env, build_dir / ('test-compile.log' if testing else 'host-compile.log'))
        binaries['test' if testing else 'host'] = binary
    node = args.node or shutil.which('node')
    if not node: raise RuntimeError('Node.js required for extension tests.')
    command([sys.executable, PRODUCT / 'tests/integration/gates_test.py'], REPO, log=out / 'release-gate-tests.log')
    command([sys.executable, PRODUCT / 'tests/integration/fixture_test.py'], REPO, log=out / 'fixture-tests.log')
    if args.package_only:
        previous = json.loads((out / 'build-manifest.json').read_text('utf-8'))
        for source in list((PRODUCT / 'source').glob('*')) + list((PRODUCT / 'extension').glob('*')):
            if source.is_file() and previous['sources'].get(source.relative_to(PRODUCT).as_posix()) != sha(source):
                raise RuntimeError('package-only requires unchanged previously tested host/extension sources')
        assert previous['version'] == version
        assert sha(binaries['host']) == previous['hostSha256']
        assert previous['automaticTestsPassed'] is True
    else:
        extension_test = command([node, '--test', PRODUCT / 'tests/extension/controller.test.mjs'], REPO, log=out / 'extension-tests.log')
        print(extension_test.stdout.decode('utf-8', errors='replace').strip())
        command([sys.executable, PRODUCT / 'tests/host/run.py', '--host', binaries['host'], '--test-host', binaries['test'], '--expected-version', version, '--output', out / 'host-results.json'], REPO, log=out / 'host-tests.log')
    report = json.loads((out / 'host-results.json').read_text('utf-8'))
    print(f"Host tests: {report['passed']} PASS / {report['failed']} FAIL / {report['notRun']} NOT RUN")
    if not args.package_only:
        command([sys.executable, PRODUCT / 'tests/integration/resources.py', '--host', binaries['host'], '--output', out / 'resource-results.json'], REPO, log=out / 'resources.log')
    stage = out / 'payload'; stage.mkdir(exist_ok=True)
    files = ['controller.mjs', 'worker.mjs', 'popup.mjs', 'popup.html', 'popup.css', 'icon.png']
    (stage / 'extension').mkdir(exist_ok=True)
    for file in files: shutil.copy2(PRODUCT / 'extension' / file, stage / 'extension' / file)
    manifest['version'] = version
    (stage / 'extension/manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', 'utf-8')
    shutil.copy2(binaries['host'], stage / 'DownloadVersionHost.exe')
    for file in ['README.md', 'KNOWN_LIMITATIONS.md']: shutil.copy2(PRODUCT / file, stage / file)
    shutil.copy2(PRODUCT / 'installer/setup.html', stage / 'setup.html')
    if version != spec['version']:
        p = stage / 'setup.html'; p.write_text(p.read_text('utf-8').replace(spec['version'], version), 'utf-8')
    (stage / 'native-host.json').write_text(json.dumps({'name': spec['nativeHostName'], 'description': 'DownloadVersionManager', 'path': 'DownloadVersionHost.exe', 'type': 'stdio', 'allowed_origins': [origin]}, indent=2) + '\n', 'utf-8')
    payload = sorted(['DownloadVersionHost.exe', 'README.md', 'KNOWN_LIMITATIONS.md', 'setup.html', 'native-host.json', 'extension/manifest.json'] + ['extension/' + f for f in files])
    inventory = 'DVM-OWNERSHIP-1\n' + ''.join(sha(stage / p) + '\t' + p + '\n' for p in payload)
    (stage / 'ownership.tsv').write_text(inventory, 'ascii', newline='\n'); payload += ['ownership.tsv']
    (build_dir / 'payload.h').write_text('#pragma once\nstatic const wchar_t* const DVM_FILES[] = {' + ','.join('L"' + p.replace('/', '\\\\') + '"' for p in payload) + '};\n', 'utf-8')
    guard = build_dir / 'DvmGuard.dll'
    command([cl] + common + ['/LD', '/Fe' + str(guard), PRODUCT / 'installer/guard.cpp'] + link + ['bcrypt.lib', 'msi.lib', 'advapi32.lib'], build_dir, env, build_dir / 'guard-compile.log')
    rollback_guard = build_dir / 'DvmRollbackFixture.dll'
    if args.lifecycle_packages:
        command([cl] + common + ['/DDVM_INSTALLER_TESTING', '/LD', '/Fe' + str(rollback_guard), PRODUCT / 'installer/guard.cpp'] + link + ['bcrypt.lib', 'msi.lib', 'advapi32.lib'], build_dir, env, build_dir / 'rollback-guard-compile.log')
    xml = ET.Element('{'+NS+'}Wix'); fragment = ET.SubElement(xml, 'Fragment'); group = ET.SubElement(fragment, 'ComponentGroup', {'Id': 'Payload'})
    for p in payload:
        ident = 'F' + hashlib.sha256(p.encode('ascii')).hexdigest()[:24]
        folder = 'ExtensionFolder' if p.startswith('extension/') else 'INSTALLFOLDER'
        component = ET.SubElement(group, 'Component', {'Id': ident, 'Directory': folder, 'Guid': str(uuid.uuid5(uuid.NAMESPACE_URL, 'dvm/file/' + p)), 'Bitness': 'always64'})
        ET.SubElement(component, 'File', {'Id': ident + 'File', 'Source': str(stage / p), 'Name': pathlib.Path(p).name})
        ET.SubElement(component, 'RegistryValue', {'Root': 'HKCU', 'Key': r'Software\Workspace\DownloadVersionManager\Files', 'Name': ident, 'Value': version, 'Type': 'string', 'KeyPath': 'yes'})
    ref = ET.SubElement(fragment, 'DirectoryRef', {'Id': 'INSTALLFOLDER'}); ET.SubElement(ref, 'Directory', {'Id': 'ExtensionFolder', 'Name': 'extension'})
    ET.ElementTree(xml).write(build_dir / 'Files.wxs', encoding='utf-8', xml_declaration=True)
    wix = args.wix or shutil.which('wix')
    if not wix and (REPO / '.tools/wix/wix.exe').is_file(): wix = str(REPO / '.tools/wix/wix.exe')
    if not wix: raise RuntimeError('WiX 4 required; pass --wix. CI installs WiX locally.')
    msi = out / f'DownloadVersionManager-{version}-x64.msi'
    product_code = '{' + str(uuid.uuid5(uuid.NAMESPACE_URL, 'dvm/evaluation/' + version)).upper() + '}'
    def package(target, rollback=False):
        command([wix, 'build', '-arch', 'x64', '-d', 'Version=' + version, '-d', 'ProductCode=' + product_code, '-d', 'GuardDll=' + str(guard), '-d', 'RollbackGuardDll=' + str(rollback_guard), '-d', 'InventorySha256=' + sha(stage / 'ownership.tsv'), '-d', 'RollbackTest=' + ('1' if rollback else '0'), '-o', target, PRODUCT / 'installer/Product.wxs', build_dir / 'Files.wxs'], REPO, log=out / ('rollback-msi.log' if rollback else 'msi-build.log'))
    package(msi)
    if args.lifecycle_packages: package(out / 'DownloadVersionManager-rollback-test.msi', True)
    command([sys.executable, PRODUCT / 'build/verify.py', '--msi', msi, '--payload', stage, '--version', version, '--output', out / 'package-verification.json'], REPO, log=out / 'package-verification.log')
    (out / 'SHA256SUMS.txt').write_text(sha(msi) + '  ' + msi.name + '\n', 'ascii')
    source_files = sorted(p for p in PRODUCT.rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    metadata = {'version': version, 'protocolVersion': 1, 'channel': 'evaluation', 'signed': False, 'compiler': str(msvc), 'sdk': sdkver, 'architecture': 'x64', 'runtime': 'static CRT / Windows APIs', 'installer': msi.name, 'sha256': sha(msi), 'hostSha256': sha(binaries['host']), 'automaticTestsPassed': report['failed'] == 0 and report['notRun'] == 0, 'sources': {p.relative_to(PRODUCT).as_posix(): sha(p) for p in source_files}, 'interactiveGates': 'NOT RUN by build; separate browser and installer evidence required'}
    (out / 'build-manifest.json').write_text(json.dumps(metadata, indent=2) + '\n', 'utf-8')
    print(f'Evaluation package built and verified: {msi}')
    return out

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ['msvc', 'sdk', 'wix', 'node', 'version']: parser.add_argument('--' + name)
    parser.add_argument('--lifecycle-packages', action='store_true')
    parser.add_argument('--package-only', action='store_true', help='Reuse unchanged tested host/extension, rebuild and verify installer only')
    build(parser.parse_args())
