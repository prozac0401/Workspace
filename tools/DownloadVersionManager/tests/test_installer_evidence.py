"""Focused evidence-decision tests; no Windows installation is executed."""
import copy
import json
import hashlib
import pathlib
import sys
import tempfile
import unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'build'))
from installer_evidence import TrialBlocked, require_environment, restoration_verdict, differences, TransactionCancellation

class RecoveryEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.before={'productState':-1,'related':[],'registry':{'Run':{'present':True,'values':{},'security':{'status':'KNOWN','ownerDacl':'unchanged'}}},'files':{'sentinel':'hash'}}
    def verdict(self,after=None,code=1603,reached=True,complete=True):
        return restoration_verdict(code,1603,reached,self.before,self.before if after is None else after,complete)
    def test_expected_exit_is_not_restoration(self):
        after=copy.deepcopy(self.before);after['related']=['retained-product']
        self.assertEqual('FAIL',self.verdict(after)['status'])
    def test_failure_before_injection_is_not_pass(self):
        self.assertEqual('FAIL',self.verdict(reached=False)['status'])
    def test_complete_restoration_passes(self):
        self.assertEqual('PASS',self.verdict()['status'])
    def test_timeout_is_not_pass(self):
        self.assertEqual('NOT RUN',self.verdict(complete=False)['status'])
    def test_unknown_acl_blocks_pass(self):
        self.before['registry']['Run']['security']={'status':'UNKNOWN','win32':5}
        self.assertEqual('BLOCKED',self.verdict()['status'])
    def test_absent_empty_value_and_registry_type_are_distinct(self):
        self.assertTrue(differences({'present':False},{'present':True,'values':{'Folder':{'data':'','kind':1}}}))
        self.assertTrue(differences({'data':1,'kind':4},{'data':'1','kind':1}))
    def test_changed_user_file_and_security_both_recorded(self):
        after=copy.deepcopy(self.before);after['files']['sentinel']='changed';after['registry']['Run']['security']['ownerDacl']='changed'
        verdict=self.verdict(after)
        self.assertEqual('FAIL',verdict['status']);self.assertEqual(2,len(verdict['stateDifferences']))
    def test_unapproved_or_shared_context_is_blocked(self):
        current={'machine':'vm','userSid':'synthetic','elevated':False,'integrity':'medium','appContainer':False}
        with self.assertRaises(TrialBlocked):require_environment(None,current)
        with tempfile.TemporaryDirectory() as root:
            p=pathlib.Path(root)/'approved.json'
            record={'approvalReference':'user approval','snapshotReference':'clean-1','environmentId':'vm-1','dedicated':True,'snapshotRestorable':True,'machine':'vm','userSid':'synthetic'}
            p.write_text(json.dumps(record),encoding='utf-8')
            self.assertEqual('vm-1',require_environment(p,current)['environmentId'])
            for update in ({'elevated':True},{'integrity':'high'},{'machine':'shared'},{'userSid':'different'},{'appContainer':True}):
                with self.subTest(update=update),self.assertRaises(TrialBlocked):require_environment(p,current|update)
            record['dedicated']=False;p.write_text(json.dumps(record),encoding='utf-8')
            with self.assertRaises(TrialBlocked):require_environment(p,current)


class ActualPcRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = pathlib.Path(self.temporary.name)
        self.current = {'machine':'vm','userSid':'synthetic','elevated':False,'integrity':'medium','appContainer':False}
        def saved(name, contents):
            path = self.root / name
            path.write_bytes(contents)
            return str(path), hashlib.sha256(contents).hexdigest()
        package, package_sha = saved('recovery.msi', b'synthetic package')
        settings, settings_sha = saved('settings.json', b'{}')
        baseline, baseline_sha = saved('baseline.json', b'{}')
        export, export_sha = saved('settings.reg', b'synthetic registry export')
        self.backup = {'approvalText':'explicit synthetic actual-PC approval',
                       'finalState':'restore original package and settings; stopped',
                       'files':[{'path':package,'size':len(b'synthetic package'),'sha256':package_sha,'verified':True}],
                       'recoveryPackage':package,'settingsJson':settings,'settingsJsonSha256':settings_sha,
                       'baseline':baseline,'baselineSha256':baseline_sha,
                       'registryExport':{'path':export,'sha256':export_sha}}
        self.manifest = self.root / 'backup-manifest.json'
        self.record = {'mode':'actual-pc','actualPcApproved':True,'dedicated':False,'snapshotRestorable':False,
                       'approvalReference':'direct human instruction','approvalText':self.backup['approvalText'],
                       'environmentId':'synthetic-actual-pc','machine':'vm','userSid':'synthetic',
                       'backupManifest':str(self.manifest)}
        self.approval = self.root / 'approved.json'
        self.save_manifest()
    def save_record(self):
        self.approval.write_text(json.dumps(self.record), encoding='utf-8')
    def save_manifest(self):
        self.manifest.write_text(json.dumps(self.backup), encoding='utf-8')
        self.record['backupManifestSha256'] = hashlib.sha256(self.manifest.read_bytes()).hexdigest()
        self.save_record()
    def approve(self):
        return require_environment(self.approval, self.current, actual_pc=True)
    def test_actual_pc_requires_explicit_mode_and_preserves_false_isolation_claims(self):
        with self.assertRaises(TrialBlocked):require_environment(self.approval,self.current)
        record = self.approve()
        self.assertIs(record['dedicated'],False)
        self.assertIs(record['snapshotRestorable'],False)
    def test_actual_pc_rejects_missing_approval_false_isolation_and_context_mismatch(self):
        original = copy.deepcopy(self.record)
        for update in ({'mode':'snapshot'},{'actualPcApproved':False},{'dedicated':True},{'snapshotRestorable':True},{'approvalText':''}):
            with self.subTest(update=update):
                self.record = original | update;self.save_record()
                with self.assertRaises(TrialBlocked):self.approve()
        self.record = original;self.save_record()
        for update in ({'machine':'other'},{'userSid':'other'},{'elevated':True},{'integrity':'high'},{'appContainer':True}):
            with self.subTest(update=update),self.assertRaises(TrialBlocked):
                require_environment(self.approval,self.current|update,actual_pc=True)
    def test_actual_pc_rejects_tampered_backup_manifest_package_settings_baseline_export(self):
        files = [self.manifest,pathlib.Path(self.backup['files'][0]['path']),pathlib.Path(self.backup['settingsJson']),
                 pathlib.Path(self.backup['baseline']),pathlib.Path(self.backup['registryExport']['path'])]
        for path in files:
            original = path.read_bytes()
            with self.subTest(path=path):
                path.write_bytes(original + b'tampered')
                with self.assertRaises(TrialBlocked):self.approve()
                path.write_bytes(original)
        self.approve()
    def test_actual_pc_rejects_unverified_recovery_or_mismatched_approval(self):
        self.backup['files'][0]['verified'] = False;self.save_manifest()
        with self.assertRaises(TrialBlocked):self.approve()
        self.backup['files'][0]['verified'] = True
        self.backup['approvalText'] = 'different approval';self.save_manifest()
        with self.assertRaises(TrialBlocked):self.approve()
    def test_cancel_requires_execution_registry_action_and_payload_and_is_once(self):
        cancel = TransactionCancellation()
        self.assertEqual(1,cancel.observe(0x08000000,['WriteRegistryValues'],False))
        self.assertEqual(1,cancel.observe(0x0A000000,['0','100','0','1'],True))
        self.assertEqual(1,cancel.observe(0x09000000,[],True))
        self.assertEqual(1,cancel.observe(0x0A000000,['0','100','0','0'],False))
        self.assertEqual(1,cancel.observe(0x08000000,['InstallFiles'],True))
        self.assertEqual(1,cancel.observe(0x09000000,[],True))
        cancel.observe(0x08000000,['WriteRegistryValues'],True)
        self.assertEqual(2,cancel.observe(0x09000000|0x40,[],True))
        self.assertEqual({'action':'WriteRegistryValues','messageType':0x09000000,
                          'executionPhase':0,'payloadExists':True,'returnValue':2},cancel.evidence)
        self.assertEqual(1,cancel.observe(0x0A000000,['2','1'],True))
        self.assertEqual(1,cancel.observe(0x09000000,[],True))
    def test_cancel_does_not_fall_back_when_selected_point_was_missed(self):
        cancel = TransactionCancellation()
        cancel.observe(0x0A000000,['0','100','0','0'],False)
        cancel.observe(0x08000000,['WriteRegistryValues'],False)
        self.assertEqual(1,cancel.observe(0x09000000,[],False))
        cancel.observe(0x08000000,['InstallFinalize'],True)
        self.assertEqual(1,cancel.observe(0x09000000,[],True))
        self.assertFalse(cancel.requested)
        self.assertIsNone(cancel.evidence)


@unittest.skipUnless(sys.platform == 'win32', 'MSI harness imports Windows APIs; no installation is executed')
class CallbackRecordTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import importlib.util
        path = pathlib.Path(__file__).resolve().parents[1] / 'build' / 'test-watcher-installer.py'
        spec = importlib.util.spec_from_file_location('watcher_installer_harness', path)
        cls.harness = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.harness)
    def test_unused_callback_messages_never_read_a_record(self):
        def forbidden(*args):
            self.fail('unused callback message attempted to decode a record')
        for message in (0x0C000000,0x0D000000,0x02000000,0x17000000):
            with self.subTest(message=message):
                self.assertIsNone(self.harness.cancellation_fields(message|0x40,0,forbidden,forbidden))
    def test_null_callback_records_never_read_fields_or_request_cancellation(self):
        def forbidden(*args):
            self.fail('null record attempted to call a record API')
        for message in (0x08000000,0x09000000,0x0A000000,0x0C000000,0x0D000000):
            with self.subTest(message=message):
                self.assertIsNone(self.harness.cancellation_fields(message|0x40,0,forbidden,forbidden))
    def test_relevant_nonnull_invalid_count_remains_an_error_before_field_read(self):
        def forbidden(*args):
            self.fail('invalid relevant record attempted to read a field')
        for message in (0x08000000,0x09000000,0x0A000000):
            with self.subTest(message=message),self.assertRaisesRegex(RuntimeError,'field count is invalid'):
                self.harness.cancellation_fields(message,7,lambda record:0xFFFFFFFF,forbidden)
    def test_handler_after_requested_never_decodes_or_cancels_again(self):
        import ast
        path = pathlib.Path(self.harness.__file__)
        child = next(node for node in ast.parse(path.read_text('utf-8')).body if isinstance(node,ast.FunctionDef) and node.name == 'child')
        handler = next(node for node in ast.walk(child) if isinstance(node,ast.FunctionDef) and node.name == 'handler')
        def forbidden(*args):
            self.fail('handler decoded or requested another cancellation after its one request')
        cancellation = TransactionCancellation()
        cancellation.requested = True
        cancellation.observe = forbidden
        scope = {'cancellation':cancellation,'cancellation_fields':forbidden}
        exec(compile(ast.Module(body=[handler],type_ignores=[]),str(path),'exec'),scope)
        for message,record in ((0x0A000000,0),(0x0A000000,7),(0x09000000,7),(0x0D000000,0)):
            with self.subTest(message=message,record=record):
                self.assertEqual(1,scope['handler'](None,message,record))
    def test_relevant_record_reads_only_available_cancellation_fields(self):
        fields = ['0','100','0','0','unused fifth field']
        reads = []
        def read(record,field):
            reads.append((record,field))
            return fields[field-1]
        self.assertEqual(fields[:4],self.harness.cancellation_fields(0x0A000000|0x40,7,lambda record:5,read))
        self.assertEqual([(7,1),(7,2),(7,3),(7,4)],reads)
        self.assertEqual([],self.harness.cancellation_fields(0x09000000,7,lambda record:0,read))

if __name__=='__main__':unittest.main(verbosity=2)
