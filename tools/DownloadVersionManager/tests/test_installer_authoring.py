"""Focused provenance and summary-authoring tests; execute no installation."""
import copy
import pathlib
import sys
import unittest
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'build'))
from installer_authoring import compile_source_provenance, summary_word_count, author_elevated_per_user


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.original = {'source/app.cpp': 'a' * 64, 'assets/icon.ico': 'b' * 64,
                         'build/build-watcher.py': 'c' * 64}
        self.current = self.original | {'build/build-watcher.py': 'd' * 64}

    def test_unchanged_recipe_preserves_strict_existing_path(self):
        result = compile_source_provenance(self.original, self.original)
        self.assertFalse(result['recipeChanged'])
        self.assertFalse(result['snapshotVerified'])

    def test_explicit_exact_recipe_snapshot_preserves_both_fingerprints(self):
        before = copy.deepcopy(self.original)
        result = compile_source_provenance(self.original, self.current, 'c' * 64)
        self.assertTrue(result['recipeChanged'])
        self.assertTrue(result['snapshotVerified'])
        self.assertEqual('c' * 64, result['compileRecipeSha256'])
        self.assertEqual('d' * 64, result['packagingRecipeSha256'])
        self.assertEqual(before, self.original)

    def test_changed_recipe_without_snapshot_is_blocked(self):
        with self.assertRaises(RuntimeError):
            compile_source_provenance(self.original, self.current)

    def test_wrong_snapshot_is_blocked(self):
        with self.assertRaises(RuntimeError):
            compile_source_provenance(self.original, self.current, 'e' * 64)

    def test_app_or_asset_change_is_blocked_even_with_valid_snapshot(self):
        for key in ('source/app.cpp', 'assets/icon.ico'):
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                compile_source_provenance(self.original, self.current | {key: 'f' * 64}, 'c' * 64)

    def test_missing_extra_or_invalid_fingerprint_is_blocked(self):
        missing = self.current.copy(); missing.pop('source/app.cpp')
        for current in (missing, self.current | {'unknown': 'e' * 64}, self.current | {'source/app.cpp': 'invalid'}):
            with self.subTest(current=current), self.assertRaises(RuntimeError):
                compile_source_provenance(self.original, current, 'c' * 64)


class SummaryApi:
    def __init__(self, *, word_count=10, kind=3, persist_error=0, readback=None):
        self.value = word_count; self.kind = kind
        self.persist_error = persist_error; self.readback = readback
        self.calls = []; self.persisted = False

    def MsiGetSummaryInformationW(self, database, path, updates, handle):
        self.calls.append(('open', database, updates))
        handle._obj.value = 42
        return 0

    def MsiSummaryInfoGetPropertyW(self, handle, prop, kind, value, filetime, text, count):
        self.calls.append(('read', prop))
        kind._obj.value = self.kind
        value._obj.value = self.readback if self.persisted and self.readback is not None else self.value
        return 0

    def MsiSummaryInfoSetPropertyW(self, handle, prop, kind, value, filetime, text):
        self.calls.append(('set', prop, kind, value))
        self.value = value
        return 0

    def MsiSummaryInfoPersist(self, handle):
        self.calls.append(('persist',))
        self.persisted = self.persist_error == 0
        return self.persist_error

    def MsiCloseHandle(self, handle):
        self.calls.append(('close', handle))
        return 0


class SummaryAuthoringTests(unittest.TestCase):
    def test_read_only_open_never_sets_or_persists(self):
        api = SummaryApi(word_count=2)
        self.assertEqual(2, summary_word_count('artifact.msi', _api=api))
        self.assertEqual([('open', 0, 0), ('read', 15), ('close', 42)], api.calls)

    def test_authoring_changes_only_wordcount_and_reads_persisted_value(self):
        api = SummaryApi()
        result = author_elevated_per_user('artifact.msi', _api=api)
        self.assertTrue(result['readbackVerified'])
        self.assertEqual(10, result['wordCountBefore'])
        self.assertEqual(2, result['wordCountAfter'])
        self.assertEqual([('open', 0, 1), ('read', 15), ('set', 15, 3, 2), ('persist',), ('close', 42),
                          ('open', 0, 0), ('read', 15), ('close', 42)], api.calls)

    def test_unexpected_original_value_or_type_is_not_written(self):
        for api in (SummaryApi(word_count=2), SummaryApi(kind=30)):
            with self.subTest(api=api), self.assertRaises(RuntimeError):
                author_elevated_per_user('artifact.msi', _api=api)
            self.assertFalse(any(call[0] in ('set', 'persist') for call in api.calls))
            self.assertEqual(('close', 42), api.calls[-1])

    def test_failed_persist_and_bad_readback_do_not_report_success(self):
        for api in (SummaryApi(persist_error=5), SummaryApi(readback=10)):
            with self.subTest(api=api), self.assertRaises(RuntimeError):
                author_elevated_per_user('artifact.msi', _api=api)
            self.assertEqual(('close', 42), api.calls[-1])


if __name__ == '__main__':
    unittest.main()
