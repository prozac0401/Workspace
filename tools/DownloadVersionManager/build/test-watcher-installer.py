"""One isolated late rollback, install, GUI start, repair and remove trial.

Stop if any DVM installation exists. Preserve all fixtures and local diagnostics.
"""
from __future__ import annotations
import argparse
import ctypes as C
from ctypes import wintypes as W
import json
import pathlib
import subprocess
import sys
import time
import uuid
import winreg
from build import REPO, sha

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


def child(args):
    MSI.MsiSetInternalUI(2, None)
    if MSI.MsiEnableLogW(0xFFFF, str(pathlib.Path(args.log).resolve()), 0):
        raise RuntimeError('Windows Installer logging could not be enabled')
    properties = 'REBOOT=ReallySuppress'
    if args.action == 'remove':
        code = MSI.MsiConfigureProductExW(args.product_code, 0, 2, properties)
    else:
        properties += ' INSTALLFOLDER="' + str(pathlib.Path(args.install_dir).resolve()) + '"'
        properties += ' DVMWATCHFOLDER="' + str(pathlib.Path(args.install_dir).resolve().parent / 'Watched Folder') + '" DVMFOLLOWDOWNLOADS=0'
        if args.action == 'repair':
            properties += ' REINSTALL=ALL REINSTALLMODE=vamus'
        code = MSI.MsiInstallProductW(str(pathlib.Path(args.msi).resolve()), properties)
    pathlib.Path(args.output).write_text(json.dumps({'exitCode': code}) + '\n', 'utf-8')


def run(args):
    msi = pathlib.Path(args.msi).resolve()
    metadata = json.loads((msi.parent / 'build-manifest.json').read_text('utf-8'))
    assert sha(msi) == metadata['sha256'], 'Package differs from build metadata'
    preflight()
    output_root = (REPO / 'artifacts/download-version-manager-watcher').resolve()
    output = pathlib.Path(args.output).resolve() if args.output else msi.parent / 'installer-results.json'
    assert output.is_relative_to(output_root), 'Evidence must stay under the watcher artifacts directory'
    work = output.parent / ('installer-fixture-' + uuid.uuid4().hex)
    install = work / 'Installed Program'
    install.mkdir(parents=True)
    (work / 'Watched Folder').mkdir()
    history = install / '_history'
    history.mkdir()
    (install / 'user-preserved.txt').write_text('unrelated user fixture\n', 'utf-8')
    (history / 'prior-version.txt').write_text('user history fixture\n', 'utf-8')
    preserve = {str(path): sha(path) for path in (install / 'user-preserved.txt', history / 'prior-version.txt')}
    state = {'status': 'RUNNING', 'environment': 'current Windows user, isolated artifact fixture', 'work': str(work), 'install': str(install), 'productCode': metadata['productCode'], 'msiSha256': sha(msi), 'tests': [], 'preserve': preserve, 'cleaned': False}

    def save():
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(state, indent=2) + '\n', 'utf-8')

    def preserved():
        assert all(pathlib.Path(path).is_file() and sha(pathlib.Path(path)) == expected for path, expected in preserve.items()), 'A business/history fixture changed'

    def execute(package, action, name, expected=0):
        result = work / (name + '-exit.json')
        command = [sys.executable, __file__, 'child', '--msi', str(package), '--action', action, '--product-code', metadata['productCode'], '--install-dir', str(install), '--log', str(work / (name + '.log')), '--output', str(result)]
        process = subprocess.run(command, capture_output=True, timeout=60)
        code = json.loads(result.read_text('utf-8'))['exitCode'] if result.is_file() else process.returncode
        state['tests'].append({'name': name, 'exitCode': code, 'status': 'PASS' if code == expected else 'FAIL'})
        save()
        assert code == expected, f'{name}: expected {expected}, actual {code}; inspect {work}'

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
            execute(pathlib.Path(args.rollback_msi).resolve(), 'install', 'late-rollback', 1603)
            assert not related(NEW_UPGRADE) and registration(WATCHER_KEY) is None, 'Late rollback retained MSI registration; stop without forced cleanup'
            assert not (install / 'DownloadVersionManager.exe').exists(), 'Late rollback retained executable'
            assert registration(r'Software\Microsoft\Windows\CurrentVersion\Run', 'Workspace.DownloadVersionManagerWatcher') is None, 'Late rollback retained startup value'
            preserved()
            state['tests'].append({'name': 'late rollback removes product, registry and executable; preserves fixtures', 'status': 'PASS'})
            save()
        execute(msi, 'install', 'install-after-failure' if args.rollback_msi else 'fresh-install')
        registered()
        executable = install / 'DownloadVersionManager.exe'
        process = subprocess.Popen([str(executable), '--first-run'])
        user32 = C.WinDLL('user32', use_last_error=True)
        callback_type = C.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
        user32.EnumWindows.argtypes = [callback_type, W.LPARAM]
        user32.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]
        user32.PostMessageW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
        windows = []

        @callback_type
        def collect(window, _):
            pid = W.DWORD()
            user32.GetWindowThreadProcessId(window, C.byref(pid))
            if pid.value == process.pid:
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
        for window in windows:
            user32.PostMessageW(window, 0x0010, 0, 0)  # WM_CLOSE, ordinary application exit.
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
        state['status'] = 'NOT RUN' if isinstance(error, subprocess.TimeoutExpired) else 'FAIL'
        state['reason'] = type(error).__name__ + ': ' + str(error)
        save()
        raise


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=('run', 'child'))
    for name in ('msi', 'output', 'rollback-msi', 'smoke-exe', 'log', 'action', 'product-code', 'install-dir'):
        parser.add_argument('--' + name)
    parser.add_argument('--skip-repair', action='store_true', help='Reuse unchanged MSI repair evidence when only the application changed.')
    arguments = parser.parse_args()
    child(arguments) if arguments.mode == 'child' else run(arguments)
