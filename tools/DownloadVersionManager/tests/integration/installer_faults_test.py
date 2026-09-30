"""Portable control-flow tests; no Windows Installer or registry operations."""
import contextlib
import importlib.util
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import types
import unittest
import uuid
from unittest import mock


class FakeLifecycle:
    KEYS = ['chrome-fixture', 'edge-fixture']
    expected = '{' + str(uuid.uuid5(uuid.NAMESPACE_URL, 'dvm/evaluation/0.1.0')).upper() + '}'

    def __init__(self, faults=()):
        self.faults = list(faults)
        self.states = []
        self.calls = []
        self.registrations = []
        self.native = False
        self.fault = None

    def fixture(self, msi, output):
        self.fault = self.faults[len(self.states)] if len(self.states) < len(self.faults) else None
        if self.fault == 'preflight':
            raise AssertionError('An existing related installation must not be changed.')
        self.preflight()
        app = output.parent / ('app-' + str(len(self.states)))
        app.mkdir()
        state = {'state': str(output), 'install': str(app), 'tests': [], 'finished': False}
        self.states.append(state)
        self.save(state)
        return state

    def save(self, state):
        pathlib.Path(state['state']).write_text(json.dumps(state), 'utf8')

    def execute(self, state, msi, args, name, expected=0):
        self.calls.append(name)
        app = pathlib.Path(state['install'])
        if name.endswith('-failure'):
            if self.fault == 'timeout':
                state['tests'].append({'name': name, 'status': 'NOT RUN', 'reason': 'Synthetic timeout; inspect before retry'})
                self.save(state)
                raise subprocess.TimeoutExpired(['synthetic-installer'], 60)
            code = 1603
            if self.fault == 'host':
                (app / 'DownloadVersionHost.exe').write_bytes(b'synthetic residue')
            self.native = self.fault == 'native'
            if self.fault == 'registered':
                self.registrations = [self.expected]
            elif self.fault == 'unexpected-product':
                self.registrations = ['{UNEXPECTED-PRODUCT}']
            elif self.fault == 'execute':
                code = 1618
        elif name == 'reinstall-without-cleanup':
            code = 1638
        else:
            code = 0
            if args[0] == '/i':
                (app / 'DownloadVersionHost.exe').write_bytes(b'synthetic host')
                self.native = True
                self.registrations = [self.expected]
            else:
                (app / 'DownloadVersionHost.exe').unlink(missing_ok=True)
                self.native = False
                self.registrations = []
        accepted = code in expected if isinstance(expected, tuple) else code == expected
        state['tests'].append({'name': name, 'exitCode': code, 'status': 'PASS' if accepted else 'FAIL'})
        self.save(state)
        if not accepted:
            raise RuntimeError(f'{name}: unexpected fixture exit {code}; no forced cleanup')
        return code

    def check_files(self, state):
        if self.fault == 'preserve':
            raise AssertionError('Preserved fixture checksum changed')

    def related(self):
        return list(self.registrations)

    def value(self, key):
        return 'synthetic-native-host.json' if self.native else None

    def preflight(self):
        assert not self.registrations and not self.native

    def check_registered(self, state):
        assert (pathlib.Path(state['install']) / 'DownloadVersionHost.exe').is_file()
        assert self.native


class InstallerFaultEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = pathlib.Path(self.temp.name) / 'summary.json'
        self.args = types.SimpleNamespace(output=str(self.output), version='0.1.0',
                                          production='production.msi', late='late.msi', postexecute='postexecute.msi')

    def run_trial(self, life):
        source = pathlib.Path(__file__).with_name('installer_faults.py')
        spec = importlib.util.spec_from_file_location('installer_faults_under_test', source)
        module = importlib.util.module_from_spec(spec)
        with mock.patch.dict(sys.modules, {'installer': life}), contextlib.redirect_stdout(io.StringIO()):
            spec.loader.exec_module(module)
            return module.run(self.args)

    def summary(self):
        self.assertTrue(self.output.is_file(), 'Aborted trials must leave an aggregate result')
        return json.loads(self.output.read_text('utf8'))

    def test_clean_rollback_keeps_existing_success_counts(self):
        life = FakeLifecycle()
        self.assertEqual(self.run_trial(life), 0)
        result = self.summary()
        self.assertEqual((result['passed'], result['failed'], result['notRun']), (10, 0, 0))
        self.assertTrue(all(t['cleaned'] for t in result['trials']))

    def test_expected_registration_residue_stays_fail_after_official_cleanup(self):
        life = FakeLifecycle(['registered', 'registered'])
        self.assertEqual(self.run_trial(life), 1)
        result = self.summary()
        self.assertEqual((result['passed'], result['failed'], result['notRun']), (10, 4, 0))
        self.assertEqual(life.calls.count('official-removal-of-trial-registration'), 2)

    def assert_aborted(self, fault, exception=AssertionError):
        life = FakeLifecycle([fault])
        with self.assertRaises(exception):
            self.run_trial(life)
        result = self.summary()
        self.assertGreater(result['failed'], 0)
        self.assertEqual(result['notRun'], 1)
        self.assertFalse(result['trials'][0]['cleaned'])
        self.assertEqual(len(life.calls), 1, 'No reinstall or forced cleanup after an unexpected failure')
        state = json.loads(pathlib.Path(life.states[0]['state']).read_text('utf8'))
        self.assertTrue(any(t['status'] == 'FAIL' for t in state['tests']))
        self.assertFalse(state['cleaned'])
        self.assertFalse(state['finished'])
        return result

    def test_residual_host_is_recorded_before_stopping(self):
        self.assert_aborted('host')

    def test_residual_native_registration_is_recorded_before_stopping(self):
        self.assert_aborted('native')

    def test_preserved_fixture_mismatch_is_recorded_before_stopping(self):
        self.assert_aborted('preserve')

    def test_unexpected_product_identity_never_reaches_cleanup(self):
        result = self.assert_aborted('unexpected-product')
        self.assertIn('Unexpected product registration', result['trials'][0]['tests'][-1]['reason'])

    def test_unexpected_installer_exit_is_not_lost_or_counted_twice(self):
        result = self.assert_aborted('execute', RuntimeError)
        self.assertEqual(result['failed'], 1)

    def test_second_trial_failure_does_not_leave_first_trial_only_summary(self):
        life = FakeLifecycle([None, 'host'])
        with self.assertRaises(AssertionError):
            self.run_trial(life)
        result = self.summary()
        self.assertEqual(len(result['trials']), 2)
        self.assertTrue(result['trials'][0]['cleaned'])
        self.assertFalse(result['trials'][1]['cleaned'])
        self.assertGreater(result['failed'], 0)
        self.assertEqual(result['notRun'], 0)
        self.assertEqual(life.calls.count('trial-final-uninstall'), 1)

    def test_preflight_failure_is_reported_without_touching_installation(self):
        life = FakeLifecycle(['preflight'])
        with self.assertRaises(AssertionError):
            self.run_trial(life)
        result = self.summary()
        self.assertEqual((result['passed'], result['failed'], result['notRun']), (0, 1, 1))
        self.assertEqual(life.calls, [])
        self.assertEqual(life.states, [])

    def test_timeout_stays_not_run_and_never_reaches_cleanup(self):
        life = FakeLifecycle(['timeout'])
        with self.assertRaises(subprocess.TimeoutExpired):
            self.run_trial(life)
        result = self.summary()
        self.assertEqual((result['passed'], result['failed'], result['notRun']), (0, 0, 2))
        self.assertEqual(len(life.calls), 1)
        self.assertEqual(result['trials'][0]['status'], 'NOT RUN')
        self.assertFalse(result['trials'][0]['cleaned'])
        self.assertFalse(result['trials'][0]['finished'])
        self.assertEqual(len(result['trials'][0]['tests']), 1)
        self.assertEqual(result['trials'][0]['tests'][0]['status'], 'NOT RUN')


if __name__ == '__main__':
    unittest.main()
