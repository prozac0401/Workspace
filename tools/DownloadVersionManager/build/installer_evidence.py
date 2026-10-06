"""Installer evidence decisions. No installation, ACL or registry mutation here."""
from __future__ import annotations
import hashlib
import json
import pathlib

class TrialBlocked(RuntimeError):
    pass

class TrialIncomplete(RuntimeError):
    pass

def require_environment(path, current, actual_pc=False):
    if not path:
        raise TrialBlocked('BLOCKED: prior environment approval is required')
    record = json.loads(pathlib.Path(path).read_text('utf-8-sig'))
    required = ('approvalReference', 'environmentId') + (() if actual_pc else ('snapshotReference',))
    for key in required:
        if not isinstance(record.get(key), str) or not record[key].strip():
            raise TrialBlocked('BLOCKED: missing environment approval/reference: ' + key)
    if record.get('machine') != current['machine'] or record.get('userSid') != current['userSid']:
        raise TrialBlocked('BLOCKED: approved environment/account does not match execution context')
    if current.get('elevated') is not False or current.get('integrity') != 'medium' or current.get('appContainer') is not False:
        raise TrialBlocked('BLOCKED: ordinary non-elevated medium-integrity user is required')
    if actual_pc:
        if (record.get('mode') != 'actual-pc' or record.get('actualPcApproved') is not True
                or record.get('dedicated') is not False or record.get('snapshotRestorable') is not False):
            raise TrialBlocked('BLOCKED: actual-PC approval must explicitly retain the absence of isolation/snapshot')
        if not isinstance(record.get('approvalText'), str) or not record['approvalText'].strip():
            raise TrialBlocked('BLOCKED: direct user approval text is required')
        def verified_file(filename, expected, size=None):
            target = pathlib.Path(filename)
            if not target.is_absolute() or not target.is_file():
                raise TrialBlocked('BLOCKED: approved backup file is absent/not absolute: ' + str(target))
            if not isinstance(expected, str) or hashlib.sha256(target.read_bytes()).hexdigest() != expected:
                raise TrialBlocked('BLOCKED: approved backup fingerprint differs: ' + str(target))
            if size is not None and target.stat().st_size != size:
                raise TrialBlocked('BLOCKED: approved backup size differs: ' + str(target))
        verified_file(record.get('backupManifest', ''), record.get('backupManifestSha256'))
        backup = json.loads(pathlib.Path(record['backupManifest']).read_text('utf-8-sig'))
        if backup.get('approvalText') != record['approvalText'] or not backup.get('finalState'):
            raise TrialBlocked('BLOCKED: backup approval/final-state evidence does not match')
        if not isinstance(backup.get('files'), list) or not backup['files']:
            raise TrialBlocked('BLOCKED: verified recovery files are required')
        for item in backup['files']:
            if item.get('verified') is not True:
                raise TrialBlocked('BLOCKED: recovery backup was not verified')
            verified_file(item.get('path', ''), item.get('sha256'), item.get('size'))
        if backup.get('recoveryPackage') not in [item['path'] for item in backup['files']]:
            raise TrialBlocked('BLOCKED: recovery MSI is not a verified backup')
        for field in ('settingsJson', 'baseline'):
            verified_file(backup.get(field, ''), backup.get(field + 'Sha256'))
        export = backup.get('registryExport', {})
        verified_file(export.get('path', ''), export.get('sha256'))
    elif record.get('dedicated') is not True or record.get('snapshotRestorable') is not True:
        raise TrialBlocked('BLOCKED: shared user profiles and synthetic-folders-only isolation are not allowed')
    return record


class TransactionCancellation:
    """One approved MSI cancellation point; message fields are provided by MSI."""
    def __init__(self):
        self.action = ''
        self.execution_phase = None
        self.requested = False
        self.evidence = None

    def observe(self, message_type, fields, payload_exists):
        message_type &= 0xFF000000
        if message_type == 0x08000000 and fields:  # ACTIONSTART field 1: action name.
            self.action = fields[0]
        if message_type == 0x0A000000 and len(fields) >= 4 and fields[0] == '0':
            self.execution_phase = int(fields[3])  # 0 executing, 1 generating script.
        if (not self.requested and message_type in (0x09000000, 0x0A000000)
                and self.action == 'WriteRegistryValues' and self.execution_phase == 0 and payload_exists):
            self.requested = True
            self.evidence = {'action': self.action, 'messageType': message_type,
                             'executionPhase': self.execution_phase, 'payloadExists': True,
                             'returnValue': 2}
            return 2  # IDCANCEL: never terminate an installer process.
        return 1  # IDOK.


def differences(before, after, prefix=''):
    if type(before) is not type(after):
        return [prefix + ': type changed']
    if isinstance(before, dict):
        result = []
        for key in sorted(before.keys() | after.keys()):
            location = prefix + '/' + str(key)
            if key not in before or key not in after:
                result.append(location + ': existence changed')
            else:
                result += differences(before[key], after[key], location)
        return result
    if isinstance(before, list):
        if len(before) != len(after):
            return [prefix + ': count changed']
        return sum((differences(a, b, prefix + '/' + str(i)) for i, (a,b) in enumerate(zip(before,after))), [])
    return [] if before == after else [prefix + ': value changed']

def unknowns(value, prefix=''):
    if isinstance(value, dict):
        result = [prefix] if value.get('status') in ('UNKNOWN', 'BLOCKED') else []
        for key, item in value.items():
            result += unknowns(item, prefix + '/' + str(key))
        return result
    if isinstance(value, list):
        return sum((unknowns(item, prefix + '/' + str(i)) for i,item in enumerate(value)), [])
    return []

def restoration_verdict(exit_code, expected_code, reached, before, after, complete=True):
    delta = differences(before, after)
    missing = sorted(set(unknowns(before) + unknowns(after)))
    if not complete:
        verdict = 'NOT RUN'
    elif exit_code != expected_code or not reached or delta:
        verdict = 'FAIL'
    elif missing:
        verdict = 'BLOCKED'
    else:
        verdict = 'PASS'
    return {'status': verdict, 'exitCode': exit_code, 'expectedFailureReached': reached,
            'stateDifferences': delta, 'unknownState': missing,
            'retry': 'NOT RUN: only after complete restoration PASS'}

def verify_package_pair(production, failure, identity, production_sha, failure_sha, query, stream_fingerprints):
    """Bind both byte streams and permit only the specified test action/sequence delta."""
    digest = lambda p: hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
    if digest(production) != production_sha or digest(failure) != failure_sha:
        raise TrialBlocked('BLOCKED: independently approved package hash mismatch')
    quote = chr(96)
    def table(path, name):
        return sorted(query(path, 'SELECT * FROM ' + quote + name + quote))
    def props(path):
        return dict(query(path, 'SELECT ' + quote + 'Property' + quote + ',' + quote + 'Value' + quote + ' FROM ' + quote + 'Property' + quote))
    for package in (production, failure):
        properties = props(package)
        for key in ('ProductCode','UpgradeCode','ProductVersion'):
            if properties.get(key) != identity[key]:
                raise TrialBlocked('BLOCKED: MSI identity mismatch: ' + key)
        if properties.get('ALLUSERS','') or properties.get('DISABLEROLLBACK',''):
            raise TrialBlocked('BLOCKED: unexpected installation scope/rollback property')
    for name in ('Registry','Component','File','Shortcut','Directory','Upgrade','Media','InstallUISequence','ControlEvent'):
        if table(production,name) != table(failure,name):
            raise TrialBlocked('BLOCKED: production/test MSI tables differ beyond injection: ' + name)
    if stream_fingerprints(production) != stream_fingerprints(failure):
        raise TrialBlocked('BLOCKED: embedded payload/custom action DLL differ')
    actions = table(failure,'CustomAction')
    injected = [row for row in actions if row[0] == 'FailAfterExecution']
    if len(injected) != 1 or injected[0][1] != '19' or injected[0][3] != 'Local verification: deliberately fail after InstallExecute.':
        raise TrialBlocked('BLOCKED: expected type-19 injection is absent/changed')
    if [r for r in actions if r[0] != 'FailAfterExecution'] != table(production,'CustomAction'):
        raise TrialBlocked('BLOCKED: unexpected custom action delta')
    sequence = table(failure,'InstallExecuteSequence')
    failures = [row for row in sequence if row[0] == 'FailAfterExecution']
    executes = [row for row in sequence if row[0] == 'InstallExecute']
    initializes = [row for row in sequence if row[0] == 'InstallInitialize']
    finalizes = [row for row in sequence if row[0] == 'InstallFinalize']
    if not (len(failures)==len(executes)==len(initializes)==len(finalizes)==1
            and failures[0][1]=='NOT REMOVE'
            and int(initializes[0][2]) < int(executes[0][2]) < int(failures[0][2]) < int(finalizes[0][2])):
        raise TrialBlocked('BLOCKED: unexpected failure sequence')
    baseline_sequence = table(production,'InstallExecuteSequence')
    allowed = {'FailAfterExecution'} | ({'InstallExecute'} if not any(row[0]=='InstallExecute' for row in baseline_sequence) else set())
    if [row for row in sequence if row[0] not in allowed] != baseline_sequence:
        raise TrialBlocked('BLOCKED: unrelated execute sequence changed')
    return {'productionSha256': production_sha,'failureSha256': failure_sha,
            'injectionAction': injected[0], 'injectionSequence': failures[0],
            'sameInstallerLogic': 'allow-listed test-only type 19 and forced InstallExecute; build manifest must also bind both embedded streams'}
