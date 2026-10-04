"""Build the native folder watcher and its isolated, per-user MSI."""
from __future__ import annotations
import argparse
import json
import os
import pathlib
import shutil
import sys
import uuid

from build import PRODUCT, REPO, command, find_msvc, find_sdk, sha

VERSION = '0.2.0'
UPGRADE_CODE = '{CBC7F202-BD84-4D52-9438-F01164572918}'


def build(args):
    sys.stdout.reconfigure(encoding='utf-8')
    if sys.platform != 'win32':
        raise RuntimeError('The watcher build requires Windows x64.')
    output_root = (REPO / 'artifacts/download-version-manager-watcher').resolve()
    out = pathlib.Path(args.output_dir).resolve() if args.output_dir else output_root / VERSION
    if out == output_root or not out.is_relative_to(output_root):
        raise RuntimeError('Output must be a dedicated directory under artifacts/download-version-manager-watcher.')
    out.mkdir(parents=True, exist_ok=True)
    build_dir = out / 'build'
    build_dir.mkdir(exist_ok=True)
    binary = out / 'DownloadVersionManager.exe'
    msvc = find_msvc(args.msvc)
    sdk, sdkver = find_sdk(args.sdk)
    includes = [msvc / 'include'] + [sdk / 'Include' / sdkver / p for p in ('ucrt', 'shared', 'um')]
    env = os.environ.copy()
    env['LIB'] = ';'.join(str(p) for p in (msvc / 'lib/x64', sdk / 'Lib' / sdkver / 'ucrt/x64', sdk / 'Lib' / sdkver / 'um/x64'))
    env['PATH'] = str(msvc / 'bin/Hostx64/x64') + ';' + str(sdk / 'bin' / sdkver / 'x64') + ';' + env['PATH']
    cl = msvc / 'bin/Hostx64/x64/cl.exe'
    common = ['/nologo', '/std:c++17', '/EHsc', '/MT', '/O2', '/W4', '/WX', '/utf-8', '/guard:cf', '/DUNICODE', '/D_UNICODE', '/DWIN32_LEAN_AND_MEAN', '/DNOMINMAX', '/D_WIN32_WINNT=0x0A00']
    common += ['/I' + str(p) for p in includes + [build_dir, PRODUCT / 'source']]
    link = ['/link', '/DYNAMICBASE', '/NXCOMPAT', '/GUARD:CF', '/WX', '/MACHINE:X64']
    libraries = ['bcrypt.lib', 'shell32.lib', 'advapi32.lib', 'user32.lib', 'gdi32.lib', 'ole32.lib', 'comctl32.lib', 'comdlg32.lib', 'uuid.lib']
    (build_dir / 'identity.h').write_text('#pragma once\n#define DVM_VERSION L"' + VERSION + '"\n', 'utf-8')

    def run_tests(selected):
        for name in selected:
            test_exe = out / ('DownloadVersionManager.' + name.title() + '.Tests.exe')
            main_file = {'engine': 'engine.cpp', 'watcher': 'smoke.cpp', 'review': 'review_smoke.cpp'}[name]
            main_object = build_dir / (name + '-test-main.obj')
            command([cl] + common + ['/DDVM_TESTING', '/c', '/Fo' + str(main_object), PRODUCT / 'tests/watcher' / main_file], build_dir, env, out / (name + '-test-main-compile.log'))
            test_sources = [PRODUCT / 'source/engine.cpp']
            if name != 'engine':
                test_sources += [PRODUCT / 'source/watcher.cpp']
            if name == 'review':
                test_sources += [PRODUCT / 'source/review.cpp']
            command([cl] + common + ['/DDVM_TESTING', '/Fe' + str(test_exe), main_object] + test_sources + link + ['/SUBSYSTEM:CONSOLE'] + libraries, build_dir, env, out / (name + '-test-compile.log'))
            fixture = out / (name + '-fixtures-' + uuid.uuid4().hex)
            if name != 'watcher':
                fixture.mkdir()
            invocation = [test_exe] + (['--root'] if name == 'engine' else []) + [fixture]
            command(invocation, REPO, log=out / (name + '-tests.log'))
            print(name + ' focused tests PASS; fixture=' + str(fixture))

    if args.test_only:
        run_tests([args.test_only])
        return
    resource = f'''1 24 "{(PRODUCT / 'source/host.manifest').as_posix()}"
1 VERSIONINFO
 FILEVERSION 0,2,0,0
 PRODUCTVERSION 0,2,0,0
 FILETYPE 1
BEGIN
 BLOCK "StringFileInfo"
 BEGIN
  BLOCK "040904B0"
  BEGIN
   VALUE "FileDescription", "DownloadVersionManager Folder Watcher"
   VALUE "FileVersion", "{VERSION}"
   VALUE "ProductVersion", "{VERSION}"
   VALUE "ProductName", "DownloadVersionManager"
  END
 END
 BLOCK "VarFileInfo"
 BEGIN
  VALUE "Translation", 0x0409, 1200
 END
END
'''
    (build_dir / 'watcher.rc').write_text(resource, 'utf-8')
    command([sdk / 'bin' / sdkver / 'x64/rc.exe', '/nologo', '/fo', build_dir / 'watcher.res', build_dir / 'watcher.rc'], build_dir, env, build_dir / 'resource.log')
    sources = [PRODUCT / 'source' / f for f in ('app.cpp', 'review.cpp', 'watcher.cpp', 'engine.cpp')]
    command([cl] + common + ['/Fe' + str(binary)] + sources + [build_dir / 'watcher.res'] + link + ['/SUBSYSTEM:WINDOWS'] + libraries, build_dir, env, out / 'compile.log')
    imports = command([msvc / 'bin/Hostx64/x64/dumpbin.exe', '/nologo', '/imports', binary], build_dir, env, out / 'imports.log').stdout.decode('utf-8', errors='replace').lower()
    if any(name in imports for name in ('vcruntime', 'msvcp', 'ucrtbase.dll', 'api-ms-win-crt-')):
        raise RuntimeError('The executable has an external C/C++ runtime dependency.')
    if args.tests:
        run_tests(['engine', 'watcher', 'review'])
    config_dll = build_dir / 'watcher-config.dll'
    command([cl] + common + ['/LD', '/Fe' + str(config_dll), PRODUCT / 'installer/watcher-config.cpp'] + link + libraries + ['msi.lib'], build_dir, env, out / 'config-compile.log')
    wix = args.wix or shutil.which('wix')
    if not wix and (REPO / '.tools/wix/wix.exe').is_file():
        wix = str(REPO / '.tools/wix/wix.exe')
    if not wix:
        raise RuntimeError('WiX 4 is required; pass --wix.')
    product_code = '{' + str(uuid.uuid5(uuid.NAMESPACE_URL, 'workspace/dvm/watcher/' + VERSION)).upper() + '}'
    installer = out / f'DownloadVersionManager-Watcher-{VERSION}-x64.msi'

    def package(destination, rollback=False):
        command([wix, 'build', '-arch', 'x64', '-d', 'Version=' + VERSION, '-d', 'ProductCode=' + product_code, '-d', 'ApplicationExe=' + str(binary), '-d', 'ConfigDll=' + str(config_dll), '-d', 'RollbackTest=' + str(int(rollback)), '-o', destination, PRODUCT / 'installer/Watcher.wxs'], REPO, log=out / ('rollback-msi-build.log' if rollback else 'msi-build.log'))

    package(installer)
    if args.rollback_test:
        package(out / 'DownloadVersionManager-Watcher-rollback-test.msi', True)
    tracked = sources + [PRODUCT / 'source' / name for name in ('engine.h', 'watcher.h', 'review.h', 'json.h', 'host.manifest')]
    tracked += [PRODUCT / 'installer/Watcher.wxs', PRODUCT / 'installer/watcher-config.cpp']
    tracked += [PRODUCT / 'build' / name for name in ('build-watcher.py', 'build-watcher.ps1', 'verify-watcher.py', 'build.py', 'verify.py')]
    metadata = {'version': VERSION, 'productCode': product_code, 'upgradeCode': UPGRADE_CODE, 'signed': False, 'architecture': 'x64', 'runtime': 'static CRT / Windows APIs', 'installer': installer.name, 'sha256': sha(installer), 'exeSha256': sha(binary), 'compiler': str(msvc), 'sdk': sdkver, 'focusedTests': 'PASS' if args.tests else 'NOT RUN by this build; retain separately recorded unchanged-source results', 'lifecycle': 'NOT RUN by build', 'sources': {p.relative_to(PRODUCT).as_posix(): sha(p) for p in tracked}}
    (out / 'build-manifest.json').write_text(json.dumps(metadata, indent=2) + '\n', 'utf-8')
    (out / 'SHA256SUMS.txt').write_text(sha(installer) + '  ' + installer.name + '\n', 'ascii')
    command([sys.executable, PRODUCT / 'build/verify-watcher.py', '--msi', installer, '--exe', binary, '--output', out / 'package-verification.json'], REPO, log=out / 'package-verification.log')
    print('Watcher MSI built and package verified: ' + str(installer))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ('msvc', 'sdk', 'wix', 'output-dir'):
        parser.add_argument('--' + name)
    parser.add_argument('--tests', action='store_true', help='Compile and run focused engine, watcher and initial-review tests in artifact folders.')
    parser.add_argument('--test-only', choices=('engine', 'watcher', 'review'), help='Run only one changed test area, without rebuilding the release payload.')
    parser.add_argument('--rollback-test', action='store_true', help='Build a separate, deliberately failing local MSI for one late rollback check.')
    build(parser.parse_args())
