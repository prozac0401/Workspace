"""Build the native folder watcher and its isolated, per-user MSI."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import sys
import uuid

from build import PRODUCT, REPO, command, find_msvc, find_sdk, sha
from installer_authoring import author_elevated_per_user, compile_source_provenance

VERSION = '0.2.1'
UPGRADE_CODE = '{CBC7F202-BD84-4D52-9438-F01164572918}'


def build(args):
    sys.stdout.reconfigure(encoding='utf-8')
    if sys.platform != 'win32':
        raise RuntimeError('The watcher build requires Windows x64.')
    if args.package_only and (args.compile_only or args.test_only or args.tests or args.rollback_test):
        raise RuntimeError('package-only cannot compile tests or build a failure-injection package.')
    if args.compile_only and (args.test_only or args.rollback_test):
        raise RuntimeError('compile-only cannot run test-only or package a failure injection.')
    if args.compile_recipe_snapshot and not args.package_only:
        raise RuntimeError('compile-recipe-snapshot is only valid for package-only reuse.')
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
            main_file = {'engine': 'engine.cpp', 'watcher': 'smoke.cpp', 'review': 'review_smoke.cpp', 'guidance': 'guidance.cpp', 'log': 'log_smoke.cpp', 'ux': 'ux_smoke.cpp', 'tray': 'tray_smoke.cpp', 'icon': 'icon_smoke.cpp'}[name]
            main_object = build_dir / (name + '-test-main.obj')
            command([cl] + common + ['/DDVM_TESTING', '/c', '/Fo' + str(main_object), PRODUCT / 'tests/watcher' / main_file], build_dir, env, out / (name + '-test-main-compile.log'))
            test_sources = [PRODUCT / 'source/engine.cpp']
            if name != 'engine':
                test_sources += [PRODUCT / 'source/watcher.cpp']
            if name in ('review', 'log', 'ux', 'tray', 'icon'):
                test_sources += [PRODUCT / 'source/review.cpp']
            test_objects = [main_object]
            if name in ('icon', 'tray', 'ux', 'log'):
                icon_rc = build_dir / 'icon-test.rc'
                icon_rc.write_text('101 ICON "' + (PRODUCT / 'assets/download-version-manager.ico').as_posix() + '"\n', 'utf-8')
                icon_resource = build_dir / 'icon-test.res'
                command([sdk / 'bin' / sdkver / 'x64/rc.exe', '/nologo', '/fo', icon_resource, icon_rc], build_dir, env, out / 'icon-resource-compile.log')
                test_objects.append(icon_resource)
            command([cl] + common + ['/DDVM_TESTING', '/Fe' + str(test_exe)] + test_objects + test_sources + link + ['/SUBSYSTEM:CONSOLE'] + libraries, build_dir, env, out / (name + '-test-compile.log'))
            fixture = out / (name + '-fixtures-' + uuid.uuid4().hex)
            if name not in ('watcher', 'log', 'tray', 'icon'):
                fixture.mkdir()
            invocation = [test_exe] + (['--root'] if name in ('engine', 'guidance') else []) + ([] if name == 'log' else [fixture])
            command(invocation, REPO, log=out / (name + '-tests.log'))
            print(name + ' focused tests PASS; fixture=' + str(fixture))

    if args.test_only:
        run_tests([args.test_only])
        return
    sources = [PRODUCT / 'source' / f for f in ('app.cpp', 'review.cpp', 'watcher.cpp', 'engine.cpp')]
    production_inputs = sources + [PRODUCT / 'source' / name for name in ('engine.h', 'watcher.h', 'review.h', 'json.h', 'ui.h', 'watcher.manifest')]
    production_inputs += [PRODUCT / 'build/build-watcher.py']
    production_inputs += [PRODUCT / 'assets' / name for name in ('download-version-manager.png', 'download-version-manager.ico')]
    def source_hashes():
        return {path.relative_to(PRODUCT).as_posix(): sha(path) for path in production_inputs}
    recipe_snapshot = pathlib.Path(args.compile_recipe_snapshot).resolve() if args.compile_recipe_snapshot else None
    def compile_provenance_for(record):
        return compile_source_provenance(record.get('sources'), source_hashes(), sha(recipe_snapshot) if recipe_snapshot else None)

    ux_evidence = None
    if args.package_only:
        if not (args.exe and args.production_manifest and args.ux_verification):
            raise RuntimeError('package-only requires --exe, --production-manifest and --ux-verification.')
        verified_exe = pathlib.Path(args.exe).resolve()
        production_manifest = pathlib.Path(args.production_manifest).resolve()
        production_manifest_bytes = production_manifest.read_bytes()
        compile_manifest_sha256 = hashlib.sha256(production_manifest_bytes).hexdigest()
        production_record = json.loads(production_manifest_bytes)
        ux_evidence = json.loads(pathlib.Path(args.ux_verification).read_text('utf-8'))
        if production_record.get('version') != VERSION or production_record.get('production') is not True:
            raise RuntimeError('A matching production compile manifest is required.')
        compile_provenance = compile_provenance_for(production_record)
        if production_record.get('exeSha256') != sha(verified_exe):
            raise RuntimeError('Production EXE differs from its compile manifest.')
        if ux_evidence.get('status') != 'PASS' or ux_evidence.get('exeSha256') != sha(verified_exe):
            raise RuntimeError('UX verification must pass for this exact production EXE.')
        if verified_exe != binary.resolve():
            shutil.copy2(verified_exe, binary)
    else:
        compiled_source_hashes = source_hashes()
        numbers = VERSION.replace('.', ',') + ',0'
        resource = f'''1 24 "{(PRODUCT / 'source/watcher.manifest').as_posix()}"
    101 ICON "{(PRODUCT / 'assets/download-version-manager.ico').as_posix()}"
    1 VERSIONINFO
     FILEVERSION {numbers}
     PRODUCTVERSION {numbers}
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
        command([cl] + common + ['/Fe' + str(binary)] + sources + [build_dir / 'watcher.res'] + link + ['/SUBSYSTEM:WINDOWS'] + libraries, build_dir, env, out / 'compile.log')
        imports = command([msvc / 'bin/Hostx64/x64/dumpbin.exe', '/nologo', '/imports', binary], build_dir, env, out / 'imports.log').stdout.decode('utf-8', errors='replace').lower()
        if any(name in imports for name in ('vcruntime', 'msvcp', 'ucrtbase.dll', 'api-ms-win-crt-')):
            raise RuntimeError('The executable has an external C/C++ runtime dependency.')
        if args.tests:
            run_tests(['engine', 'watcher', 'review', 'guidance', 'log', 'ux', 'tray', 'icon'])
        if source_hashes() != compiled_source_hashes:
            raise RuntimeError('Production sources changed during compilation.')
        production_record = {'version': VERSION, 'production': True, 'exeSha256': sha(binary), 'executable': str(binary), 'compiler': str(msvc), 'sdk': sdkver, 'runtime': 'static CRT / Windows APIs', 'sources': compiled_source_hashes}
        production_manifest = out / 'production-build-manifest.json'
        production_manifest.write_text(json.dumps(production_record, indent=2) + '\n', 'utf-8')
        compile_manifest_sha256 = sha(production_manifest)
        compile_provenance = compile_provenance_for(production_record)
    if args.compile_only:
        print('Production EXE compiled without packaging: ' + str(binary))
        print('Compile manifest: ' + str(out / 'production-build-manifest.json'))
        return
    packaging_inputs = list(production_inputs)
    packaging_inputs += [PRODUCT / 'installer/Watcher.wxs', PRODUCT / 'installer/watcher-config.cpp']
    packaging_inputs += [PRODUCT / 'build' / name for name in ('build-watcher.py', 'build-watcher.ps1', 'installer_authoring.py', 'verify-watcher.py', 'build.py', 'verify.py')]
    def packaging_hashes():
        return {path.relative_to(PRODUCT).as_posix(): sha(path) for path in packaging_inputs}
    packaging_before = packaging_hashes()
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
        return author_elevated_per_user(destination)

    installer_authoring = package(installer)
    if args.rollback_test:
        package(out / 'DownloadVersionManager-Watcher-rollback-test.msi', True)
    if sha(binary) != production_record['exeSha256'] or compile_provenance_for(production_record) != compile_provenance:
        raise RuntimeError('The production EXE or its compile provenance changed during packaging.')
    if sha(production_manifest) != compile_manifest_sha256:
        raise RuntimeError('The original compile manifest changed during packaging.')
    if packaging_hashes() != packaging_before:
        raise RuntimeError('Installer authoring inputs changed during packaging.')
    compile_provenance = compile_provenance | {
        'mode': 'verified EXE reused without compilation' if args.package_only else 'compiled by this build',
        'manifestPath': str(production_manifest), 'manifestSha256': compile_manifest_sha256,
        'exeSha256': production_record['exeSha256'],
        'compileRecipeSnapshotPath': str(recipe_snapshot) if recipe_snapshot else None,
    }
    metadata = {'version': VERSION, 'productCode': product_code, 'upgradeCode': UPGRADE_CODE, 'signed': False, 'architecture': 'x64', 'runtime': 'static CRT / Windows APIs', 'installer': installer.name, 'sha256': sha(installer), 'exeSha256': sha(binary), 'compiler': production_record['compiler'], 'sdk': production_record['sdk'], 'installerCompiler': str(msvc), 'installerSdk': sdkver, 'focusedTests': 'PASS' if args.tests else 'NOT RUN by this build; retain separately recorded unchanged-source results', 'lifecycle': 'NOT RUN by build', 'packageMode': 'exact verified production EXE' if args.package_only else 'compiled by build', 'productionUiVerification': ux_evidence, 'productionCompileProvenance': compile_provenance, 'installerAuthoring': installer_authoring, 'packagingInputsStable': True, 'sources': packaging_before}
    (out / 'build-manifest.json').write_text(json.dumps(metadata, indent=2) + '\n', 'utf-8')
    (out / 'SHA256SUMS.txt').write_text(sha(installer) + '  ' + installer.name + '\n', 'ascii')
    command([sys.executable, PRODUCT / 'build/verify-watcher.py', '--msi', installer, '--exe', binary, '--output', out / 'package-verification.json'], REPO, log=out / 'package-verification.log')
    print('Watcher MSI built and package verified: ' + str(installer))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ('msvc', 'sdk', 'wix', 'output-dir'):
        parser.add_argument('--' + name)
    parser.add_argument('--tests', action='store_true', help='Compile and run focused engine, watcher, initial-review, guidance, log, UX, tray and icon tests in artifact folders.')
    parser.add_argument('--test-only', choices=('engine', 'watcher', 'review', 'guidance', 'log', 'ux', 'tray', 'icon'), help='Run only one changed test area, without rebuilding the release payload.')
    parser.add_argument('--compile-only', action='store_true', help='Compile the production EXE and source/hash manifest without packaging.')
    parser.add_argument('--package-only', action='store_true', help='Package the exact production EXE after source/hash and UX-evidence checks, without rebuilding it.')
    parser.add_argument('--compile-recipe-snapshot', help='For package-only: preserve the original compile builder when only the current packaging recipe changed; snapshot SHA must match the immutable compile manifest.')
    for name in ('exe', 'production-manifest', 'ux-verification'):
        parser.add_argument('--' + name)
    parser.add_argument('--rollback-test', action='store_true', help='Build a separate, deliberately failing local MSI for one late rollback check.')
    build(parser.parse_args())
