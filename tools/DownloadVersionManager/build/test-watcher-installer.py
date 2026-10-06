"""One isolated late rollback, install, GUI start, repair and remove trial.

Stop if any DVM installation exists. Preserve all fixtures and local diagnostics.
"""
from __future__ import annotations
import argparse
import ctypes as C
from datetime import datetime, timezone
from ctypes import wintypes as W
import json
import pathlib
import os
import subprocess
import sys
import time
import uuid
import winreg
from build import REPO, sha
from installer_evidence import require_environment, restoration_verdict, verify_package_pair, unknowns, TrialBlocked, TrialIncomplete, TransactionCancellation
from installer_app_exit import WINDOW_CLASS, request_installed_app_exit
from installer_windows_evidence import context, snapshot, stream_fingerprints
from verify import query

PRODUCT_KEY = r'Software\Workspace\DownloadVersionManager'
WATCHER_KEY = PRODUCT_KEY + r'\Watcher'
OLD_UPGRADE = '{79E6679C-B762-48DB-B27D-B10963DC1530}'
NEW_UPGRADE = '{CBC7F202-BD84-4D52-9438-F01164572918}'
MSI = C.WinDLL('msi')
MSI.MsiEnumRelatedProductsW.argtypes = [W.LPCWSTR, W.DWORD, W.DWORD, W.LPWSTR]
MSI.MsiSetInternalUI.argtypes = [W.UINT, C.POINTER(W.HANDLE)]
MSI.MsiEnableLogW.argtypes = [W.DWORD, W.LPCWSTR, W.DWORD]
MSI.MsiInstallProductW.argtypes = [W.LPCWSTR, W.LPCWSTR]
MSI.MsiConfigureProductExW.argtypes = [W.LPCWSTR, W.INT, W.INT, W.LPCWSTR]


def capture_window(window, destination):
    from PIL import Image
    user32 = C.WinDLL('user32', use_last_error=True)
    gdi32 = C.WinDLL('gdi32', use_last_error=True)
    user32.GetWindowRect.argtypes = [W.HWND, C.POINTER(W.RECT)]
    user32.GetWindowDC.argtypes = [W.HWND]
    user32.GetWindowDC.restype = W.HDC
    user32.ReleaseDC.argtypes = [W.HWND, W.HDC]
    user32.PrintWindow.argtypes = [W.HWND, W.HDC, W.UINT]
    for name in ('CreateCompatibleDC', 'CreateCompatibleBitmap', 'SelectObject'):
        getattr(gdi32, name).restype = W.HANDLE
    gdi32.CreateCompatibleDC.argtypes = [W.HDC]
    gdi32.CreateCompatibleBitmap.argtypes = [W.HDC, W.INT, W.INT]
    gdi32.SelectObject.argtypes = [W.HDC, W.HANDLE]
    gdi32.DeleteObject.argtypes = [W.HANDLE]
    gdi32.DeleteDC.argtypes = [W.HDC]
    gdi32.GetDIBits.argtypes = [W.HDC, W.HBITMAP, W.UINT, W.UINT, C.c_void_p, C.c_void_p, W.UINT]
    rectangle = W.RECT()
    assert user32.GetWindowRect(window, C.byref(rectangle))
    width, height = rectangle.right - rectangle.left, rectangle.bottom - rectangle.top
    dc = user32.GetWindowDC(window)
    memory = gdi32.CreateCompatibleDC(dc)
    bitmap = gdi32.CreateCompatibleBitmap(dc, width, height)
    previous = gdi32.SelectObject(memory, bitmap)
    try:
        assert user32.PrintWindow(window, memory, 2), 'PrintWindow failed'
        gdi32.SelectObject(memory, previous)
        header = C.create_string_buffer(40 + 1024)
        import struct
        struct.pack_into('<IiiHHIIiiII', header, 0, 40, width, -height, 1, 32, 0, width * height * 4, 0, 0, 0, 0)
        pixels = C.create_string_buffer(width * height * 4)
        assert gdi32.GetDIBits(dc, bitmap, 0, height, pixels, header, 0) == height, 'Window pixel capture failed'
        Image.frombytes('RGB', (width, height), pixels.raw, 'raw', 'BGRX').save(destination)
    finally:
        gdi32.SelectObject(memory, previous)
        gdi32.DeleteObject(bitmap)
        gdi32.DeleteDC(memory)
        user32.ReleaseDC(window, dc)


def registration(key, name='InstallFolder'):
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key, 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY) as opened:
            return winreg.QueryValueEx(opened, name)[0]
    except FileNotFoundError:
        return None


def related(upgrade):
    found = []
    for index in range(64):
        value = C.create_unicode_buffer(39)
        code = MSI.MsiEnumRelatedProductsW(upgrade, 0, index, value)
        if code == 259:
            return found
        if code:
            raise RuntimeError('Related-product preflight failed: ' + str(code))
        found.append(value.value)
    raise RuntimeError('Unexpected number of related products')


def preflight():
    assert not related(OLD_UPGRADE) and not related(NEW_UPGRADE), 'Existing DVM installation must not be changed.'
    assert registration(PRODUCT_KEY) is None and registration(WATCHER_KEY) is None, 'Existing DVM installation registry value must not be changed.'
    assert all(registration(WATCHER_KEY, name) is None for name in ('SettingsVersion', 'Folder', 'FollowDownloads', 'InitialReviewFolder')), 'Existing watcher runtime settings must be preserved; use a clean user for this trial.'
    assert registration(r'Software\Microsoft\Windows\CurrentVersion\Run', 'Workspace.DownloadVersionManagerWatcher') is None, 'Existing watcher startup value must be preserved.'
    for hive in (winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE):
        for view in (winreg.KEY_WOW64_32KEY, winreg.KEY_WOW64_64KEY):
            try:
                with winreg.OpenKey(hive, r'Software\Microsoft\Windows\CurrentVersion\Uninstall', 0, winreg.KEY_READ | view) as base:
                    index = 0
                    while True:
                        try:
                            name = winreg.EnumKey(base, index)
                        except OSError:
                            break
                        index += 1
                        try:
                            with winreg.OpenKey(base, name) as key:
                                display = str(winreg.QueryValueEx(key, 'DisplayName')[0])
                        except FileNotFoundError:
                            continue
                        assert not display.startswith('DownloadVersionManager'), 'Existing DVM installation: ' + display
            except FileNotFoundError:
                pass


def cancellation_fields(message_type, record, field_count, read_field):
    """Decode only the MSI record messages used by the cancellation predicate."""
    message_type &= 0xFF000000
    if not record or message_type not in (0x08000000, 0x09000000, 0x0A000000):
        return None
    count = field_count(record)
    if count == 0xFFFFFFFF:
        raise RuntimeError('MSI callback field count is invalid: ' + hex(message_type))
    return [read_field(record, i) for i in range(1, min(4, count) + 1)]


def child(args):
    environment = require_environment(args.approved_environment, context(), actual_pc=args.actual_pc)
    install = pathlib.Path(args.install_dir).resolve()
    if not install.is_relative_to((REPO / "artifacts/download-version-manager-watcher").resolve()):
        raise TrialBlocked("BLOCKED: child installation path must remain in synthetic trial output")
    if args.actual_pc:
        if args.action not in ('install', 'cancel'):
            raise TrialBlocked('BLOCKED: actual-PC child is restricted to recovery install/cancel trials')
        if not args.package_sha256 or sha(pathlib.Path(args.msi).resolve()) != args.package_sha256:
            raise TrialBlocked('BLOCKED: exact approved trial MSI fingerprint is required')
        preflight()
        if (install / 'DownloadVersionManager.exe').exists():
            raise TrialBlocked('BLOCKED: trial payload already exists before recovery trial')
    ui_level = 2 | (0x200 if args.allow_uac else 0)  # NONE | optional UACONLY; human approval only.
    MSI.MsiSetInternalUI(ui_level, None)
    if MSI.MsiEnableLogW(0xFFFF, str(pathlib.Path(args.log).resolve()), 0):
        raise RuntimeError('Windows Installer logging could not be enabled')
    properties = 'REBOOT=ReallySuppress'
    if args.action == 'remove':
        code = MSI.MsiConfigureProductExW(args.product_code, 0, 2, properties)
    else:
        properties += ' INSTALLFOLDER="' + str(install) + '"'
        properties += ' DVMWATCHFOLDER="' + str(install.parent / 'Watched Folder') + '" DVMFOLLOWDOWNLOADS=0'
        if args.actual_pc:
            properties += ' DVMSTARTATLOGIN=1 DVMLAUNCHAPP=0'
        if args.action == 'repair':
            properties += ' REINSTALL=ALL REINSTALLMODE=vamus'
        if args.action == 'cancel':
            if not args.actual_pc:
                raise TrialBlocked('BLOCKED: cancellation requires the explicit approved recovery child mode')
            cancellation = TransactionCancellation()
            result = {'status': 'RUNNING', 'environmentMode': environment['mode'],
                      'internalUiLevel': ui_level, 'allowUac': args.allow_uac,
                      'properties': properties, 'cancellation': None, 'callbackError': None}
            def save_cancel():
                pathlib.Path(args.output).write_text(json.dumps(result, indent=2) + '\n', 'utf-8')
            save_cancel()
            callback_type = C.WINFUNCTYPE(C.c_int, C.c_void_p, W.UINT, W.UINT)
            MSI.MsiSetExternalUIRecord.argtypes = [C.c_void_p, W.DWORD, C.c_void_p, C.POINTER(C.c_void_p)]
            MSI.MsiSetExternalUIRecord.restype = W.UINT
            MSI.MsiRecordGetFieldCount.argtypes = [W.UINT]
            MSI.MsiRecordGetFieldCount.restype = W.UINT
            MSI.MsiRecordGetStringW.argtypes = [W.UINT, W.UINT, W.LPWSTR, C.POINTER(W.DWORD)]
            MSI.MsiRecordGetStringW.restype = W.UINT
            def record_string(record, field):
                size = W.DWORD(0)
                text = C.create_unicode_buffer(1)
                rc = MSI.MsiRecordGetStringW(record, field, text, C.byref(size))
                if rc == 234:
                    size.value += 1
                    text = C.create_unicode_buffer(size.value)
                    rc = MSI.MsiRecordGetStringW(record, field, text, C.byref(size))
                if rc:
                    raise RuntimeError('MSI callback record read failed: ' + str(rc))
                return text.value
            def handler(_context, message_type, record):
                if cancellation.requested:
                    return 1  # IDOK: the one cancellation request is already recorded.
                try:
                    fields = cancellation_fields(message_type, record, MSI.MsiRecordGetFieldCount, record_string)
                    if fields is None:
                        return 1  # IDOK: null records and unused messages have no cancellation data.
                    answer = cancellation.observe(message_type, fields, (install / 'DownloadVersionManager.exe').is_file())
                    if answer == 2:
                        result['cancellation'] = dict(cancellation.evidence, capturedUtc=datetime.now(timezone.utc).isoformat())
                        save_cancel()  # Persist the actual reached point before returning IDCANCEL.
                    return answer
                except Exception as error:
                    result['callbackError'] = type(error).__name__ + ': ' + str(error)
                    result['callbackErrorMessageType'] = message_type
                    try:
                        save_cancel()
                    except Exception:
                        print(result['callbackError'], file=sys.stderr, flush=True)
                    return -1  # Callback error: fail the trial, never pretend cancellation was reached.
            callback = callback_type(handler)
            previous = C.c_void_p()
            if MSI.MsiSetExternalUIRecord(C.cast(callback, C.c_void_p), (1 << 8) | (1 << 9) | (1 << 10), None, C.byref(previous)):
                raise TrialBlocked('BLOCKED: MSI cancellation callback registration failed')
            try:
                code = MSI.MsiInstallProductW(str(pathlib.Path(args.msi).resolve()), properties)
            finally:
                MSI.MsiSetExternalUIRecord(previous, 0, None, None)
            result.update(status='FAIL' if result['callbackError'] else ('COMPLETED' if cancellation.requested else 'NOT RUN'),
                          exitCode=code, lastAction=cancellation.action,
                          executionPhase=cancellation.execution_phase, completionKnown=True)
            save_cancel()
            return
        code = MSI.MsiInstallProductW(str(pathlib.Path(args.msi).resolve()), properties)
    pathlib.Path(args.output).write_text(json.dumps({'exitCode': code, 'completionKnown': True,
                                                  'internalUiLevel': ui_level, 'allowUac': args.allow_uac}) + '\n', 'utf-8')


def run(args):
    environment = require_environment(args.approved_environment, context())
    msi = pathlib.Path(args.msi).resolve()
    metadata = json.loads((msi.parent / 'build-manifest.json').read_text('utf-8'))
    assert sha(msi) == metadata['sha256'], 'Package differs from build metadata'
    preflight()
    package_pair = None
    if args.rollback_msi:
        if not args.rollback_sha256:
            raise TrialBlocked('BLOCKED: explicit failure-injection MSI fingerprint is required')
        package_pair = verify_package_pair(msi, pathlib.Path(args.rollback_msi).resolve(),
            {'ProductCode': metadata['productCode'], 'UpgradeCode': metadata['upgradeCode'], 'ProductVersion': metadata['version']},
            metadata['sha256'], args.rollback_sha256, query, stream_fingerprints)
    output_root = (REPO / 'artifacts/download-version-manager-watcher').resolve()
    output = pathlib.Path(args.output).resolve() if args.output else msi.parent / 'installer-results.json'
    assert output.is_relative_to(output_root), 'Evidence must stay under the watcher artifacts directory'
    work = output.parent / ('installer-fixture-' + uuid.uuid4().hex)
    install = work / 'Installed Program'
    install.mkdir(parents=True)
    (work / 'Watched Folder').mkdir()
    history = work / 'Watched Folder' / '_history'
    history.mkdir()
    (install / 'user-preserved.txt').write_text('unrelated user fixture\n', 'utf-8')
    (history / 'prior-version.txt').write_text('user history fixture\n', 'utf-8')
    preserve = {str(path): sha(path) for path in (install / 'user-preserved.txt', history / 'prior-version.txt')}
    state = {'status': 'RUNNING', 'environment': environment, 'packagePair': package_pair, 'work': str(work), 'install': str(install), 'productCode': metadata['productCode'], 'msiSha256': sha(msi), 'tests': [], 'preserve': preserve, 'cleaned': False}

    def save():
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(state, indent=2) + '\n', 'utf-8')

    shortcut_dir = pathlib.Path(os.environ['APPDATA']) / 'Microsoft/Windows/Start Menu/Programs/DownloadVersionManager Watcher'

    def take_snapshot():
        return snapshot(metadata['productCode'], NEW_UPGRADE, OLD_UPGRADE, work, shortcut_dir)

    def preserved():
        assert all(pathlib.Path(path).is_file() and sha(pathlib.Path(path)) == expected for path, expected in preserve.items()), 'A business/history fixture changed'

    def execute(package, action, name, expected=0):
        result = work / (name + '-exit.json')
        command = [sys.executable, __file__, 'child', '--msi', str(package), '--action', action, '--product-code', metadata['productCode'], '--install-dir', str(install), '--log', str(work / (name + '.log')), '--output', str(result), '--approved-environment', args.approved_environment]
        if args.allow_uac:
            command.append('--allow-uac')
        process = subprocess.run(command, capture_output=True, timeout=60)
        if not result.is_file():
            raise TrialIncomplete('Child result missing; MSI completion is unknown; preserve snapshot and stop')
        code = json.loads(result.read_text('utf-8'))['exitCode']
        state['tests'].append({'name': name, 'exitCode': code, 'status': ('EXPECTED_FAILURE' if expected else 'COMMAND_SUCCESS') if code == expected else 'FAIL'})
        save()
        if code != expected:
            state['failureSnapshot'] = take_snapshot()
            save()
            raise RuntimeError(f'{name}: expected {expected}, actual {code}; inspect {work}')
        return code

    def registered():
        assert related(NEW_UPGRADE) == [metadata['productCode']], 'Unexpected watcher product registration'
        assert registration(WATCHER_KEY).rstrip('\\') == str(install).rstrip('\\')
        assert (install / 'DownloadVersionManager.exe').is_file() and sha(install / 'DownloadVersionManager.exe') == metadata['exeSha256']
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r'Software\Microsoft\Windows\CurrentVersion\Run') as key:
            assert winreg.QueryValueEx(key, 'Workspace.DownloadVersionManagerWatcher')[0] == '"' + str(install / 'DownloadVersionManager.exe') + '" --autostart'
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, WATCHER_KEY + r'\InstallDefaults') as key:
            assert winreg.QueryValueEx(key, 'Folder')[0].rstrip('\\') == str(work / 'Watched Folder') and winreg.QueryValueEx(key, 'FollowDownloads')[0] == 0
        if state.get('runtimeSettings'):
            assert all(registration(WATCHER_KEY, name) == value for name, value in state['runtimeSettings'].items()), 'Repair reset app settings'
        preserved()

    save()
    try:
        if args.rollback_msi:
            before = take_snapshot()
            state['rollbackBefore'] = before
            save()
            if unknowns(before):
                raise TrialBlocked('BLOCKED: incomplete before-state/security snapshot; nothing installed')
            code = execute(pathlib.Path(args.rollback_msi).resolve(), 'install', 'late-rollback', 1603)
            after = take_snapshot()
            state['rollbackAfter'] = after
            save()  # Preserve complete immediate state before assertions/retry/cleanup.
            log = work / 'late-rollback.log'
            if not log.is_file():
                raise TrialIncomplete('Rollback log missing; failure reachability/recovery is unknown')
            text = log.read_text('utf-16') if log.read_bytes().startswith(bytes([255,254])) else log.read_text('utf-8', errors='replace')
            reached = 'Local verification: deliberately fail after InstallExecute.' in text and 'ScriptType=2' in text
            verdict = restoration_verdict(code, 1603, reached, before, after)
            verdict['name'] = 'late rollback complete state restoration'
            state['tests'].append(verdict)
            save()
            if verdict['status'] != 'PASS':
                error_type = TrialBlocked if verdict['status'] == 'BLOCKED' else RuntimeError
                raise error_type('Restoration '+verdict['status']+': preserve snapshot; no retry or automatic removal')
        execute(msi, 'install', 'install-after-failure' if args.rollback_msi else 'fresh-install')
        registered()
        executable = install / 'DownloadVersionManager.exe'
        process = subprocess.Popen([str(executable), '--first-run'])
        user32 = C.WinDLL('user32', use_last_error=True)
        callback_type = C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
        user32.EnumWindows.argtypes = [callback_type, W.LPARAM]
        user32.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
        user32.GetClassNameW.argtypes = [W.HWND, W.LPWSTR, W.INT]
        user32.GetClassNameW.restype = W.INT
        user32.PostMessageW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
        user32.PostMessageW.restype = W.BOOL
        windows = []

        @callback_type
        def collect(window, _):
            pid = W.DWORD()
            user32.GetWindowThreadProcessId(window, C.byref(pid))
            class_name = C.create_unicode_buffer(256)
            if (pid.value == process.pid and
                    user32.GetClassNameW(window, class_name, len(class_name)) and
                    class_name.value == WINDOW_CLASS):
                windows.append(window)
            return True

        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and process.poll() is None:
            user32.EnumWindows(collect, 0)
            if windows:
                break
            time.sleep(0.1)
        assert windows and process.poll() is None, 'Installed application did not create a window'
        user32.GetDlgItem.argtypes = [W.HWND, W.INT]
        user32.GetDlgItem.restype = W.HWND
        user32.IsWindowEnabled.argtypes = [W.HWND]
        user32.IsWindowEnabled.restype = W.BOOL
        stop_button = user32.GetDlgItem(windows[0], 103)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and process.poll() is None and not user32.IsWindowEnabled(stop_button):
            time.sleep(0.1)
        assert stop_button and user32.IsWindowEnabled(stop_button), 'Installed application did not start its watcher for the artifact folder'
        capture_window(windows[0], work / 'installed-gui.png')
        state['screenshot'] = str(work / 'installed-gui.png')
        request_installed_app_exit(user32, windows[0], process.pid)
        assert process.wait(timeout=10) == 0, 'Installed application did not exit normally'
        state['runtimeSettings'] = {name: registration(WATCHER_KEY, name) for name in ('SettingsVersion', 'Folder', 'FollowDownloads', 'InitialReviewFolder')}
        assert state['runtimeSettings']['Folder'] == str(work / 'Watched Folder') and state['runtimeSettings']['SettingsVersion'] == 1, 'Installed application did not save fixture settings'
        state['tests'].append({'name': 'installed GUI starts watcher for the artifact folder and exits normally', 'status': 'PASS'})
        save()
        if args.smoke_exe:
            smoke = subprocess.run([str(pathlib.Path(args.smoke_exe).resolve()), str(work / 'watcher')], capture_output=True, timeout=60)
            (work / 'watcher-smoke.log').write_bytes(smoke.stdout + smoke.stderr)
            assert smoke.returncode == 0, 'Watcher smoke failed; inspect local watcher-smoke.log'
            state['tests'].append({'name': 'watcher smoke in isolated folder', 'status': 'PASS'})
            save()
        if not args.skip_repair:
            execute(msi, 'repair', 'same-version-repair')
            registered()
        execute(msi, 'remove', 'remove')
        assert not related(NEW_UPGRADE) and registration(WATCHER_KEY) is None
        assert not executable.exists()
        assert registration(r'Software\Microsoft\Windows\CurrentVersion\Run', 'Workspace.DownloadVersionManagerWatcher') is None
        preserved()
        assert all(registration(WATCHER_KEY, name) == value for name, value in state['runtimeSettings'].items()), 'Uninstall removed app settings'
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, WATCHER_KEY, 0, winreg.KEY_SET_VALUE | winreg.KEY_WOW64_64KEY) as key:
            for name in ('SettingsVersion', 'Folder', 'FollowDownloads', 'InitialReviewFolder'):
                try:
                    winreg.DeleteValue(key, name)
                except FileNotFoundError:
                    pass
        state['tests'].append({'name': 'remove preserves user file and _history', 'status': 'PASS'})
        state['cleaned'] = True
        state['status'] = 'PASS'
        save()
        print(json.dumps(state, indent=2))
    except Exception as error:
        state['status'] = 'NOT RUN' if isinstance(error, (subprocess.TimeoutExpired, TrialIncomplete)) else ('BLOCKED' if isinstance(error, TrialBlocked) else 'FAIL')
        try:
            state['failureSnapshot'] = take_snapshot()
        except Exception as snapshot_error:
            state['failureSnapshot'] = {'status': 'UNKNOWN', 'reason': str(snapshot_error)}
        state['reason'] = type(error).__name__ + ': ' + str(error)
        save()
        raise


def parse_arguments(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('run', 'child'))
    for name in ('msi', 'output', 'rollback-msi', 'smoke-exe', 'log', 'action', 'product-code', 'install-dir'):
        parser.add_argument('--' + name)
    parser.add_argument('--approved-environment', help='Prior approved environment record; actual-PC recovery requires explicit approval and verified backups.')
    parser.add_argument('--actual-pc', action='store_true', help='Explicit approved actual-PC recovery child only; does not claim snapshot isolation.')
    parser.add_argument('--package-sha256', help='Exact approved trial MSI fingerprint; required for actual-PC recovery child.')
    parser.add_argument('--rollback-sha256', help='Independently recorded exact test MSI fingerprint; never inferred from an arbitrary argument.')
    parser.add_argument('--skip-repair', action='store_true', help='Reuse unchanged MSI repair evidence when only the application changed.')
    parser.add_argument('--allow-uac', action='store_true', help='Allow only the human-approved Windows elevation prompt; other installer UI stays silent.')
    return parser.parse_args(argv)


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    arguments = parse_arguments()
    try:
        if arguments.actual_pc and arguments.mode != 'child':
            raise TrialBlocked('BLOCKED: actual-PC mode is restricted to root-orchestrated recovery child trials')
        child(arguments) if arguments.mode == 'child' else run(arguments)
    except (TrialBlocked, TrialIncomplete) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(2)
