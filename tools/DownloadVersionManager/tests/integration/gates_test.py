import importlib.util, pathlib, unittest
p=pathlib.Path(__file__).resolve().parents[2]/'build/release-gate.py'
spec=importlib.util.spec_from_file_location('release_gate',p); gate=importlib.util.module_from_spec(spec); spec.loader.exec_module(gate)
class ReleaseGateTests(unittest.TestCase):
    def evidence(self): return {'channel':'stable','gates':dict.fromkeys(gate.GATES,'PASS')}
    def test_complete_gate_set(self): self.assertEqual(gate.evaluate(self.evidence()),{})
    def test_each_missing_gate_blocks(self):
        for key in gate.GATES:
            with self.subTest(gate=key):
                evidence=self.evidence(); del evidence['gates'][key]; self.assertIn(key,gate.evaluate(evidence))
    def test_not_run_fail_and_blocked_are_not_pass(self):
        for status in ['NOT RUN','FAIL','BLOCKED','pass',True,None]:
            evidence=self.evidence();evidence['gates']['singleDistribution']=status;self.assertIn('singleDistribution',gate.evaluate(evidence))
    def test_evaluation_does_not_publish_stable(self):
        evidence=self.evidence();evidence['channel']='evaluation';self.assertIn('channel',gate.evaluate(evidence))
if __name__=='__main__':unittest.main()
