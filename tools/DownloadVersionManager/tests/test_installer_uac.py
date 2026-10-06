"""Focused CLI/UI routing tests with mocked MSI calls; no installation is executed."""
import ast
import contextlib
import importlib.util
import json
import pathlib
import sys
import tempfile
import types
import unittest
from unittest import mock

BUILD = pathlib.Path(__file__).resolve().parents[1] / 'build'
HARNESS_PATH = BUILD / 'test-watcher-installer.py'
sys.path.insert(0, str(BUILD))


@unittest.skipUnless(sys.platform == 'win32', 'MSI harness imports Windows APIs; calls are mocked')
class InstallerUacTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec = importlib.util.spec_from_file_location('watcher_uac_harness', HARNESS_PATH)
        cls.harness = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.harness)

    def test_cli_uac_is_opt_in_for_both_routes(self):
        for mode in ('run', 'child'):
            with self.subTest(mode=mode):
                self.assertFalse(self.harness.parse_arguments([mode]).allow_uac)
                self.assertTrue(self.harness.parse_arguments([mode, '--allow-uac']).allow_uac)

    def invoke_child(self, allow_uac, actual_pc=False, action="install"):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            package = root / 'synthetic.msi'
            package.write_bytes(b'synthetic package; never installed')
            output = root / 'child-result.json'
            install = root / 'artifacts/download-version-manager-watcher/fixture/Installed Program'
            argv = ['child', '--action', action, '--msi', str(package),
                    '--install-dir', str(install), '--output', str(output),
                    '--log', str(root / 'mock-only.log'), '--approved-environment', 'synthetic-approval',
                    '--product-code', '{SYNTHETIC}', '--package-sha256', 'incorrect-fingerprint']
            if allow_uac:
                argv.append('--allow-uac')
            if actual_pc:
                argv.append('--actual-pc')
            args = self.harness.parse_arguments(argv)
            msi = types.SimpleNamespace(
                MsiSetInternalUI=mock.Mock(return_value=2),
                MsiEnableLogW=mock.Mock(return_value=0),
                MsiInstallProductW=mock.Mock(return_value=0),
                MsiConfigureProductExW=mock.Mock(return_value=0))
            with contextlib.ExitStack() as patches:
                patches.enter_context(mock.patch.object(self.harness, 'REPO', root))
                patches.enter_context(mock.patch.object(self.harness, 'MSI', msi))
                patches.enter_context(mock.patch.object(self.harness, 'context', return_value={}))
                patches.enter_context(mock.patch.object(self.harness, 'require_environment', return_value={'mode': 'mocked'}))
                try:
                    self.harness.child(args)
                except self.harness.TrialBlocked as error:
                    return msi, None, error
            return msi, json.loads(output.read_text('utf-8')), None

    def test_child_default_suppresses_uac_and_records_ui_level(self):
        msi, result, error = self.invoke_child(False)
        self.assertIsNone(error)
        msi.MsiSetInternalUI.assert_called_once_with(2, None)
        msi.MsiInstallProductW.assert_called_once()
        self.assertEqual(2, result['internalUiLevel'])
        self.assertIs(result['allowUac'], False)
        self.assertIs(result['completionKnown'], True)

    def test_child_opt_in_requests_uac_only_and_records_ui_level(self):
        msi, result, error = self.invoke_child(True)
        self.assertIsNone(error)
        msi.MsiSetInternalUI.assert_called_once_with(0x202, None)
        msi.MsiInstallProductW.assert_called_once()
        self.assertEqual(514, result['internalUiLevel'])
        self.assertIs(result['allowUac'], True)
        self.assertIs(result['completionKnown'], True)

    def test_actual_pc_action_guard_precedes_uac_configuration(self):
        msi, result, error = self.invoke_child(True, actual_pc=True, action='remove')
        self.assertIn('restricted to recovery install/cancel', str(error))
        self.assertIsNone(result)
        msi.MsiSetInternalUI.assert_not_called()
        msi.MsiInstallProductW.assert_not_called()
        msi.MsiConfigureProductExW.assert_not_called()

    def test_actual_pc_package_guard_precedes_uac_configuration(self):
        msi, result, error = self.invoke_child(True, actual_pc=True)
        self.assertIn('exact approved trial MSI fingerprint', str(error))
        self.assertIsNone(result)
        msi.MsiSetInternalUI.assert_not_called()
        msi.MsiInstallProductW.assert_not_called()

    def parent_child_command(self, allow_uac):
        tree = ast.parse(HARNESS_PATH.read_text('utf-8'))
        run = next(node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == 'run')
        execute = next(node for node in run.body if isinstance(node, ast.FunctionDef) and node.name == 'execute')
        with tempfile.TemporaryDirectory() as temporary:
            work = pathlib.Path(temporary)
            commands = []
            def mocked_run(command, capture_output, timeout):
                self.assertTrue(capture_output)
                self.assertEqual(60, timeout)
                commands.append(command)
                result = pathlib.Path(command[command.index('--output') + 1])
                result.write_text(json.dumps({'exitCode': 0}), encoding='utf-8')
                return types.SimpleNamespace(returncode=0)
            scope = {'sys': sys, '__file__': str(HARNESS_PATH), 'json': json,
                     'work': work, 'install': work / 'Installed Program',
                     'metadata': {'productCode': '{SYNTHETIC}'}, 'state': {'tests': []},
                     'args': types.SimpleNamespace(allow_uac=allow_uac, approved_environment='synthetic-approval'),
                     'subprocess': types.SimpleNamespace(run=mocked_run), 'save': mock.Mock()}
            exec(compile(ast.Module(body=[execute], type_ignores=[]), str(HARNESS_PATH), 'exec'), scope)
            self.assertEqual(0, scope['execute'](work / 'synthetic.msi', 'install', 'mock-trial'))
            self.assertEqual(1, len(commands))
            self.assertEqual('child', commands[0][2])
            return commands[0]

    def test_parent_default_keeps_child_uac_silent(self):
        self.assertNotIn('--allow-uac', self.parent_child_command(False))

    def test_parent_forwards_explicit_uac_option_once(self):
        self.assertEqual(1, self.parent_child_command(True).count('--allow-uac'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
