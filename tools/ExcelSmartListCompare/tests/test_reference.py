"""Reference/specification tests, NOT execution or compilation of the VBA files.
Run: python -m unittest discover -s tests -p 'test_*.py' -v
"""
from collections import Counter
from decimal import Decimal, InvalidOperation
from pathlib import Path
import math
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
ERROR = object()
NUM = re.compile(r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]{1,4})?$')


def whitespace(s):
    for c in ('\u00a0', '\u3000', '\t', '\r', '\n'):
        s = s.replace(c, ' ')
    s = s.replace('\u200b', '').replace('\ufeff', '')
    while '  ' in s:
        s = s.replace('  ', ' ')
    return s.strip(' ')


def canonical(s):
    if not NUM.fullmatch(s):
        return None
    if 'e' in s.lower() and abs(int(s.lower().split('e')[1])) > 1000:
        return None
    try:
        d = Decimal(s)
    except InvalidOperation:
        return None
    if not d:
        return '0'
    out = format(d, 'f')
    if '.' in out:
        out = out.rstrip('0').rstrip('.')
    return out


def normalize(v):
    if v is None or v is ERROR:
        return ''
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        if isinstance(v, float) and not math.isfinite(v):
            raise ValueError('Excel Range.Value2 does not represent NaN/Inf as a number')
        return '#n:' + canonical(format(v, '.15g') if isinstance(v, float) else str(v))
    s = whitespace(str(v))
    s = ''.join(chr(ord(c) - 0xFEE0) if 0xFF01 <= ord(c) <= 0xFF5E else c for c in s)
    s = whitespace(s)
    if not s:
        return ''
    if s[:7].lower() == 'mailto:':
        s = whitespace(s[7:])
    p = s.find('@')
    if 0 < p < len(s)-1:
        s = whitespace(s[:p])
    s = s.lower()
    integer = re.split('[.e]', s.lstrip('+-'))[0]
    leading = len(integer) > 1 and integer[0] == '0'
    number = None if leading else canonical(s)
    return '#n:' + number if number is not None else '#t:' + s


def snapshot(cells, rects, hidden_rows=(), hidden_cols=(), metadata=()):
    seen, counts = set(), Counter()
    for r1, c1, r2, c2 in rects:
        for r in range(r1, r2 + 1):
            for c in range(c1, c2 + 1):
                if (r, c) in seen or r in hidden_rows or c in hidden_cols:
                    continue
                seen.add((r, c))
                if any(a <= r <= d and b <= c <= e for a, b, d, e in metadata):
                    continue
                key = normalize(cells.get((r,c)))
                if key:
                    counts[key] += 1
    return counts


def limits(scan, visible, areas, pending=0):
    if scan > 2_000_000 or visible > 100_000 or areas > 5_000:
        return 'stop'
    if scan >= 200_000 or visible + pending >= 20_000 or areas >= 500:
        return 'warn'
    return 'run'


class NormalizationTests(unittest.TestCase):
    def test_numeric_text(self): self.assertEqual(normalize(123), normalize('123'))
    def test_decimal_zero(self): self.assertEqual(normalize(123), normalize('123.0'))
    def test_leading_zero(self): self.assertNotEqual(normalize(123), normalize('00123'))
    def test_leading_signed_zero(self): self.assertNotEqual(normalize(-123), normalize('-00123'))
    def test_email_domain_ignored(self): self.assertEqual(normalize('USER@a.com'), normalize('user@b.com'))
    def test_email_plain(self): self.assertEqual(normalize(' user@a.com '), normalize('user'))
    def test_mailto(self): self.assertEqual(normalize('mailto: user@a.com'), normalize('user'))
    def test_email_leading_zero(self): self.assertEqual(normalize('00123@a.com'), normalize('00123'))
    def test_email_numeric(self): self.assertEqual(normalize('123@a.com'), normalize(123))
    def test_case(self): self.assertEqual(normalize('ABC'), normalize('abc'))
    def test_trim(self): self.assertEqual(normalize(' 홍길동 '), normalize('홍길동'))
    def test_internal_space(self): self.assertNotEqual(normalize('홍 길동'), normalize('홍길동'))
    def test_nbsp(self): self.assertEqual(normalize('\u00a0a\u00a0'), normalize('a'))
    def test_zero_width(self): self.assertEqual(normalize('\ufeffa\u200b'), normalize('a'))
    def test_fullwidth(self): self.assertEqual(normalize('ＡＢＣ１２３'), normalize('abc123'))
    def test_scientific(self): self.assertEqual(normalize('1.23e2'), normalize(123))
    def test_negative_zero(self): self.assertEqual(normalize('-0.0'), normalize(0))
    def test_comma_literal(self): self.assertNotEqual(normalize('1,234'), normalize(1234))
    def test_boolean(self): self.assertNotEqual(normalize(True), normalize(-1))
    def test_long_numeric_text(self): self.assertEqual(normalize('9007199254740993'), '#n:9007199254740993')
    def test_blank(self): self.assertEqual(normalize('\r\n\t\u00a0 '), '')
    def test_bad_numeric(self): self.assertEqual(normalize('1e'), '#t:1e')
    def test_big_exponent_literal(self): self.assertEqual(normalize('1e1001'), '#t:1e1001')
    def test_error(self): self.assertEqual(normalize(ERROR), '')


class GeometryTests(unittest.TestCase):
    def setUp(self):
        self.horizontal = {(2, 2):'a', (2, 3):'b', (2, 4):'c'}
        self.vertical = {(3, 8):'c', (4, 8):'b', (5, 8):'a'}
    def test_horizontal_to_vertical(self):
        self.assertEqual(snapshot(self.horizontal, [(2,2,2,4)]), snapshot(self.vertical, [(3,8,5,8)]))
    def test_vertical_to_horizontal(self):
        self.assertEqual(snapshot(self.vertical, [(3,8,5,8)]), snapshot(self.horizontal, [(2,2,2,4)]))
    def test_rectangle(self):
        a = snapshot({(1,1):'a', (1,2):'b', (2,1):'c', (2,2):'a'}, [(1,1,2,2)])
        self.assertEqual(a, Counter({'#t:a':2, '#t:b':1, '#t:c':1}))
    def test_partial_selection_not_column(self):
        self.assertEqual(snapshot(self.vertical, [(4,8,4,8)]), Counter({'#t:b':1}))
    def test_single_cell_does_not_expand(self):
        self.assertEqual(snapshot(self.horizontal, [(2,2,2,2)]), Counter({'#t:a':1}))
    def test_hidden_row(self):
        self.assertNotIn('#t:b', snapshot(self.vertical, [(3,8,5,8)], hidden_rows={4}))
    def test_hidden_column(self):
        self.assertNotIn('#t:b', snapshot(self.horizontal, [(2,2,2,4)], hidden_cols={3}))
    def test_all_hidden(self):
        self.assertEqual(snapshot(self.vertical, [(3,8,5,8)], hidden_cols={8}), Counter())
    def test_multi_area_one_list(self):
        self.assertEqual(snapshot(self.horizontal, [(2,2,2,2), (2,3,2,4)]), Counter({'#t:a':1, '#t:b':1, '#t:c':1}))
    def test_overlapping_selection(self):
        self.assertEqual(snapshot(self.horizontal, [(2,2,2,3), (2,3,2,4)]), Counter({'#t:a':1, '#t:b':1, '#t:c':1}))
    def test_header_not_entire_row(self):
        out = snapshot({(1,1):'header', (1,2):'data'}, [(1,1,1,2)], metadata=[(1,1,1,1)])
        self.assertEqual(out, Counter({'#t:data':1}))
    def test_duplicate_counts_matter(self):
        a = snapshot({(1,1):'a', (2,1):'a'}, [(1,1,2,1)])
        b = snapshot({(1,1):'a'}, [(1,1,1,1)])
        self.assertNotEqual(a, b)
        self.assertEqual(a-b, Counter({'#t:a':1}))
    def test_snapshot_independent_of_source(self):
        a = snapshot(self.horizontal, [(2,2,2,4)])
        self.horizontal.clear()
        self.assertEqual(sum(a.values()), 3)


class LimitTests(unittest.TestCase):
    def test_small_fast_path(self): self.assertEqual(limits(42,42,1), 'run')
    def test_before_visible_warning(self): self.assertEqual(limits(19999,19999,1), 'run')
    def test_visible_warning_boundary(self): self.assertEqual(limits(20000,20000,1), 'warn')
    def test_combined_warning(self): self.assertEqual(limits(10000,10000,1,10000), 'warn')
    def test_visible_limit_boundary(self): self.assertEqual(limits(100000,100000,1), 'warn')
    def test_visible_limit_exceeded(self): self.assertEqual(limits(100001,100001,1), 'stop')
    def test_fragment_warning(self): self.assertEqual(limits(1000,1000,500), 'warn')
    def test_fragment_hard_cap(self): self.assertEqual(limits(10000,10000,5001), 'stop')
    def test_large_hidden_scan_warning(self): self.assertEqual(limits(200000,42,1), 'warn')
    def test_large_scan_hard_cap(self): self.assertEqual(limits(2000001,42,1), 'stop')


class StaticSafetyTests(unittest.TestCase):
    def test_ascii_exports_in_sync(self):
        from export_ascii import export_line
        for src in (ROOT/'src').glob('*_utf8.*'):
            target = src.with_name(src.name.replace('_utf8', ''))
            expected = '\n'.join(export_line(line) for line in src.read_text(encoding='utf-8').splitlines()) + '\n'
            self.assertEqual(target.read_text(encoding='ascii'), expected)
    def test_unique_vba_procedures_and_matching_ends(self):
        for src in (ROOT/'src').glob('*_utf8.*'):
            stack, names = [], set()
            for line in src.read_text(encoding='utf-8').splitlines():
                start = re.match(r'^(?:Public|Private|Friend)?\s*(Sub|Function)\s+(\w+)', line, re.I)
                end = re.match(r'^End (Sub|Function)\s*$', line, re.I)
                if start:
                    self.assertNotIn(start[2].lower(), names, str(src))
                    names.add(start[2].lower())
                    stack.append(start[1].lower())
                if end:
                    self.assertTrue(stack, str(src))
                    self.assertEqual(stack.pop(), end[1].lower())
            self.assertEqual(stack, [], str(src))
    def test_no_global_hotkey_or_find_or_clipboard(self):
        code = '\n'.join(l for l in (ROOT/'src/modSLCMain_utf8.bas').read_text(encoding='utf-8').splitlines() if not l.lstrip().startswith("'"))
        for forbidden in [r'Application\.OnKey', r'CommandBars\.Reset', r'\.Find\(', r'SendKeys', r'CutCopyMode\s*=', r'Application\.Calculation\s*=']:
            self.assertIsNone(re.search(forbidden, code, re.I), forbidden)
    def test_safe_security_and_setup(self):
        ps = (ROOT/'Setup.ps1').read_text(encoding='utf-8-sig')
        executable = '\n'.join(l for l in ps.splitlines() if not l.lstrip().startswith('#'))
        for forbidden in ['Stop-Process', 'taskkill', 'ExecutionPolicy Bypass', 'Unblock-File', 'Set-ExecutionPolicy', 'AccessVBOM', 'RunAs', 'Trusted Locations']:
            self.assertNotIn(forbidden, executable)
        self.assertIn('AutomationSecurity = 2', executable)
        self.assertNotIn('-Recurse', executable)
        self.assertIn('$data.productId -ne $ProductId', executable)
    def test_preflight_before_values(self):
        code = (ROOT/'src/modSLCMain_utf8.bas').read_text(encoding='utf-8')
        prepare = code[code.index('Private Function PrepareParts'):code.index('Private Function EntirelyHidden')]
        self.assertNotIn('.Value2', prepare)
        self.assertIn('vbDefaultButton2', prepare)
        self.assertIn('MAX_VISIBLE', prepare)
    def test_snapshot_has_no_com_range_references(self):
        code = (ROOT/'src/CSLCList_utf8.cls').read_text(encoding='utf-8')
        self.assertIsNone(re.search(r'As (Workbook|Worksheet|Range)\b', code))


if __name__ == '__main__':
    unittest.main(verbosity=2)
