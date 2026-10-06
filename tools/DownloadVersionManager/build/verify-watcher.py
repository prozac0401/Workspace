"""Verify watcher MSI tables and embedded executable without installing it."""
from __future__ import annotations
import argparse
import ctypes as C
from ctypes import wintypes as W
import os
import json
import pathlib
import subprocess
import uuid
from verify import query, digest, msi
from installer_authoring import summary_word_count


def extract_stream(file, name, destination):
    """Read a cabinet stream with MSIDBOPEN_READONLY; execute no MSI sequence."""
    msi.MsiRecordReadStream.argtypes = [W.UINT, W.UINT, C.c_void_p, C.POINTER(W.DWORD)]
    db = W.UINT(); view = W.UINT(); record = W.UINT()
    assert msi.MsiOpenDatabaseW(str(file), None, C.byref(db)) == 0, "MSI read-only open failed"
    try:
        escaped = name.replace("'", "''")
        sql = "SELECT `Data` FROM `_Streams` WHERE `Name`='" + escaped + "'"
        assert msi.MsiDatabaseOpenViewW(db, sql, C.byref(view)) == 0, "Cabinet stream query failed"
        assert msi.MsiViewExecute(view, 0) == 0 and msi.MsiViewFetch(view, C.byref(record)) == 0, "Cabinet stream missing"
        with destination.open("xb") as output:
            while True:
                count = W.DWORD(65536); buffer = C.create_string_buffer(count.value)
                assert msi.MsiRecordReadStream(record, 1, buffer, C.byref(count)) == 0, "Cabinet stream read failed"
                if not count.value:
                    break
                output.write(buffer.raw[:count.value])
    finally:
        if record.value: msi.MsiCloseHandle(record)
        if view.value: msi.MsiCloseHandle(view)
        msi.MsiCloseHandle(db)


def verify_installer_contract(props, word_count, actions, execute_sequence, authoring):
    assert 'ALLUSERS' not in props, 'MSI must keep a fixed per-user installation scope'
    assert 'MSIINSTALLPERUSER' not in props, 'Dual-purpose installation is outside this package contract'
    assert word_count == 2, 'MSI must allow required installer elevation without changing per-user scope'
    assert (authoring.get('wordCountBefore') == 10 and
            authoring.get('wordCountAfter') == word_count and
            authoring.get('elevationAllowed') is True and
            authoring.get('readbackVerified') is True), 'Installer authoring metadata mismatch'
    allowed_actions = {
        'SetARPINSTALLLOCATION': ('51', 'ARPINSTALLLOCATION', '[INSTALLFOLDER]'),
        'SetINSTALLFOLDER': ('51', 'INSTALLFOLDER', '[DVMEXISTINGROOT]'),
        'ResolveDownloads': ('1', 'WatcherConfig', 'DvmResolveDownloads'),
        'LaunchApplication': ('210', 'ApplicationExe', '--first-run'),
    }
    expected = [[name, *definition] for name, definition in allowed_actions.items()]
    assert sorted(actions) == sorted(expected), 'Unexpected custom action or privilege change'
    assert ['LaunchApplication'] not in execute_sequence, 'Silent installation must not launch UI'
    return {
        'installerWordCount': word_count,
        'installerElevationAllowed': True,
        'installationScope': 'fixed per-user, HKCU',
        'applicationExecutionRequirement': 'ordinary user',
        'applicationTokenVerification': 'NOT RUN by package verification',
    }


def verify(args):
    file = pathlib.Path(args.msi).resolve()
    executable = pathlib.Path(args.exe).resolve()
    metadata = json.loads((file.parent / 'build-manifest.json').read_text('utf-8'))
    assert digest(file) == metadata['sha256'], 'MSI differs from build metadata'
    assert digest(executable) == metadata['exeSha256'], 'EXE differs from build metadata'
    props = dict(query(file, 'SELECT `Property`, `Value` FROM `Property`'))
    assert props['ProductVersion'] == metadata['version'] and props['ProductCode'] == metadata['productCode']
    assert props['UpgradeCode'] == metadata['upgradeCode']
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
    execute_sequence = query(file, 'SELECT `Action` FROM `InstallExecuteSequence`')
    privilege_contract = verify_installer_contract(
        props, summary_word_count(file), actions, execute_sequence,
        metadata.get('installerAuthoring', {}))
    assert not query(file, 'SELECT * FROM `CreateFolder`'), 'The installer must not create or own the watch folder'
    files = query(file, 'SELECT `File`, `FileName`, `FileSize` FROM `File`')
    assert len(files) == 1 and files[0][0] == 'ApplicationExe' and files[0][1].split('|')[-1] == 'DownloadVersionManager.exe' and int(files[0][2]) == executable.stat().st_size, files
    media = query(file, 'SELECT `Cabinet` FROM `Media`')
    assert len(media) == 1 and media[0][0].startswith('#'), 'The single payload cabinet must be embedded'
    directories = query(file, 'SELECT `Directory`, `Directory_Parent`, `DefaultDir` FROM `Directory`')
    assert any(row[0] == 'INSTALLFOLDER' and row[1] == 'Programs' and row[2].split('|')[-1] == 'DownloadVersionManagerWatcher' for row in directories)
    assert any(row[0] == 'Programs' and row[1] == 'LocalAppDataFolder' for row in directories), 'Application directory must remain under LocalAppData'
    shortcuts = query(file, 'SELECT `Target` FROM `Shortcut`')
    assert shortcuts == [['[INSTALLFOLDER]DownloadVersionManager.exe']], shortcuts
    extract = file.parent / ('package-extraction-' + uuid.uuid4().hex)
    extract.mkdir()
    cabinet = extract / 'payload.cab'
    extract_stream(file, media[0][0][1:], cabinet)
    payload = extract / 'payload'; payload.mkdir()
    expand = pathlib.Path(os.environ['SystemRoot']) / 'System32/expand.exe'
    result = subprocess.run([str(expand), '-R', str(cabinet), '-F:ApplicationExe', str(payload)], capture_output=True, timeout=90)
    (extract / 'cab-expansion.log').write_bytes(result.stdout + result.stderr)
    assert result.returncode == 0, result.returncode
    embedded = payload / 'ApplicationExe'
    assert embedded.is_file() and list(payload.iterdir()) == [embedded] and digest(embedded) == digest(executable), 'Embedded executable mismatch'
    assert digest(file) == metadata['sha256'], 'Read-only verification changed the MSI'
    report = {'status': 'PASS', 'version': props['ProductVersion'], 'perUser': True, 'embeddedPayloadFiles': 1, 'browserExtension': False, 'nativeMessaging': False, 'services': 0, 'startupRegistration': 'HKCU Run, user-selected default on', 'installerActions': 'known-folder resolution, standard MSI directory chooser, UI-only optional launch', 'staticRuntime': True, 'sha256': digest(file), 'exeSha256': digest(embedded), 'payloadExtraction': 'read-only MSI stream and CAB expansion; no MSI execution', 'extractionDirectory': str(extract), 'lifecycle': 'NOT RUN by package verification'}
    report.update(privilege_contract)
    report['installerAuthoring'] = metadata['installerAuthoring']
    pathlib.Path(args.output).write_text(json.dumps(report, indent=2) + '\n', 'utf-8')
    print(json.dumps(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ('msi', 'exe', 'output'):
        parser.add_argument('--' + name, required=True)
    verify(parser.parse_args())
