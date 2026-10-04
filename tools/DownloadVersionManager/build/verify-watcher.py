"""Verify watcher MSI tables and embedded executable without installing it."""
from __future__ import annotations
import argparse
import json
import pathlib
import subprocess
import uuid
from verify import query, digest


def verify(args):
    file = pathlib.Path(args.msi).resolve()
    executable = pathlib.Path(args.exe).resolve()
    metadata = json.loads((file.parent / 'build-manifest.json').read_text('utf-8'))
    assert digest(file) == metadata['sha256'], 'MSI differs from build metadata'
    assert digest(executable) == metadata['exeSha256'], 'EXE differs from build metadata'
    props = dict(query(file, 'SELECT `Property`, `Value` FROM `Property`'))
    assert props['ProductVersion'] == '0.2.0' and props['ProductCode'] == metadata['productCode']
    assert props['UpgradeCode'] == metadata['upgradeCode']
    assert props.get('ALLUSERS', '') == '', 'MSI must install per user'
    assert props.get('MSIRESTARTMANAGERCONTROL', '') == '', 'Use standard Restart Manager behavior'
    assert props['REBOOT'] == 'ReallySuppress'
    registry = query(file, 'SELECT `Root`, `Key`, `Name`, `Value` FROM `Registry`')
    allowed_keys = {r'Software\Workspace\DownloadVersionManager\Watcher', r'Software\Workspace\DownloadVersionManager\Watcher\InstallDefaults', r'Software\Microsoft\Windows\CurrentVersion\Run'}
    assert len(registry) == 6 and all(row[0] == '1' and row[1] in allowed_keys for row in registry), registry
    startup = [row for row in registry if row[1] == r'Software\Microsoft\Windows\CurrentVersion\Run']
    assert startup == [['1', r'Software\Microsoft\Windows\CurrentVersion\Run', 'Workspace.DownloadVersionManagerWatcher', '"[INSTALLFOLDER]DownloadVersionManager.exe" --autostart']], startup
    assert not query(file, 'SELECT * FROM `ServiceInstall`')
    assert not query(file, 'SELECT * FROM `ServiceControl`')
    assert not query(file, 'SELECT * FROM `RemoveFile` WHERE `FileName` IS NOT NULL')
    actions = query(file, 'SELECT `Action`, `Type`, `Source`, `Target` FROM `CustomAction`')
    allowed_actions = {'SetARPINSTALLLOCATION': ('51', None, None), 'SetINSTALLFOLDER': ('51', None, None), 'ResolveDownloads': ('1', 'WatcherConfig', 'DvmResolveDownloads'), 'LaunchApplication': ('210', 'ApplicationExe', '--first-run')}
    assert len(actions) == len(allowed_actions), actions
    for row in actions:
        assert row[0] in allowed_actions, row
        kind, source, target = allowed_actions[row[0]]
        assert row[1] == kind and (source is None or row[2] == source) and (target is None or row[3] == target), row
    execute_sequence = query(file, 'SELECT `Action` FROM `InstallExecuteSequence`')
    assert ['LaunchApplication'] not in execute_sequence, 'Silent installation must not launch UI'
    assert not query(file, 'SELECT * FROM `CreateFolder`'), 'The installer must not create or own the watch folder'
    files = query(file, 'SELECT `FileName`, `FileSize` FROM `File`')
    assert len(files) == 1 and files[0][0].split('|')[-1] == 'DownloadVersionManager.exe' and int(files[0][1]) == executable.stat().st_size, files
    media = query(file, 'SELECT `Cabinet` FROM `Media`')
    assert media and all(row[0].startswith('#') for row in media), 'All cabinets must be embedded'
    directories = query(file, 'SELECT `Directory`, `Directory_Parent`, `DefaultDir` FROM `Directory`')
    assert any(row[0] == 'INSTALLFOLDER' and row[2].split('|')[-1] == 'DownloadVersionManagerWatcher' for row in directories)
    shortcuts = query(file, 'SELECT `Target` FROM `Shortcut`')
    assert shortcuts == [['[INSTALLFOLDER]DownloadVersionManager.exe']], shortcuts
    extract = file.parent / ('package-extraction-' + uuid.uuid4().hex)
    extract.mkdir(exist_ok=True)
    result = subprocess.run(['msiexec.exe', '/a', str(file), '/qn', 'TARGETDIR=' + str(extract), 'REBOOT=ReallySuppress', '/L*v', str(file.parent / 'package-extraction.log')], capture_output=True, timeout=90)
    assert result.returncode == 0, result.returncode
    found = list(extract.rglob('DownloadVersionManager.exe'))
    assert len(found) == 1 and digest(found[0]) == digest(executable), 'Embedded executable mismatch'
    report = {'status': 'PASS', 'version': props['ProductVersion'], 'perUser': True, 'embeddedPayloadFiles': 1, 'browserExtension': False, 'nativeMessaging': False, 'services': 0, 'startupRegistration': 'HKCU Run, user-selected default on', 'installerActions': 'known-folder resolution, standard MSI directory chooser, UI-only optional launch', 'staticRuntime': True, 'sha256': digest(file), 'lifecycle': 'NOT RUN by package verification'}
    pathlib.Path(args.output).write_text(json.dumps(report, indent=2) + '\n', 'utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ('msi', 'exe', 'output'):
        parser.add_argument('--' + name, required=True)
    verify(parser.parse_args())
