"""Loopback fixture contract only; this never counts as Chrome/Edge E2E."""
import importlib.util, pathlib, threading, unittest, urllib.parse, urllib.request
source=pathlib.Path(__file__).with_name('fixture-server.py')
spec=importlib.util.spec_from_file_location('fixture_server',source); fixture=importlib.util.module_from_spec(spec); spec.loader.exec_module(fixture)

class FixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=fixture.http.server.ThreadingHTTPServer(('127.0.0.1',0),fixture.Handler)
        cls.thread=threading.Thread(target=cls.server.serve_forever); cls.thread.start()
        cls.base='http://127.0.0.1:'+str(cls.server.server_port)
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
    def download(self,query):
        with urllib.request.urlopen(self.base+'/download?'+urllib.parse.urlencode(query),timeout=5) as response:
            return response.read(),response.headers
    def test_same_content_is_repeatable_and_changed_fixture_differs(self):
        a,_=self.download({'version':'A'}); repeated,_=self.download({'version':'A'}); b,_=self.download({'version':'B'})
        self.assertEqual(a,repeated); self.assertNotEqual(a,b)
        self.assertTrue(fixture.zipfile.is_zipfile(fixture.io.BytesIO(a)))
    def test_original_parenthesized_names_are_explicit_headers(self):
        for name in ['보고서.xlsx','회의자료 (1).xlsx','회의자료 (2).xlsx']:
            _,headers=self.download({'name':name})
            self.assertTrue(headers['Content-Disposition'].endswith(urllib.parse.quote(name)))
    def test_unknown_fixture_is_rejected(self):
        with self.assertRaises(urllib.error.HTTPError) as error: self.download({'version':'unknown'})
        self.assertEqual(error.exception.code,400)
if __name__=='__main__': unittest.main()
