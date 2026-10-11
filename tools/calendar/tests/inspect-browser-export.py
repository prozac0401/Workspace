"""Independently compare browser preview and downloaded XLSX, including every blank.

Usage: python inspect-browser-export.py [--base DIRECTORY] [--years 1983 2026 2027 2099]
The selected directory contains calendar_YEAR.xlsx and preview-cells-YEAR.json.
The original 2027 preview-cells.json name remains supported.
"""
from pathlib import Path
import argparse
import calendar
import datetime as dt
import json
import re
import zipfile
import xml.etree.ElementTree as ET
from openpyxl import load_workbook

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base', type=Path, default=Path(__file__).resolve().parents[3] / 'artifacts/calendar/browser')
parser.add_argument('--years', type=int, nargs='+', default=[1983, 2026, 2027, 2099])
args = parser.parse_args()
base = args.base.resolve()
run_path = base / 'results.json'
run = json.loads(run_path.read_text(encoding='utf-8')) if run_path.exists() else {}
reports = []
ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}

for year in args.years:
    preview_path = base / f'preview-cells-{year}.json'
    if year == 2027 and not preview_path.exists():
        preview_path = base / 'preview-cells.json'
    cells = json.loads(preview_path.read_text(encoding='utf-8'))
    preview = {item['cell']: item for item in cells}
    assert len(preview) == len(cells), f'{year}: duplicate preview coordinates'
    path = base / f'calendar_{year}.xlsx'
    assert zipfile.is_zipfile(path), f'{year}: real ZIP-based XLSX required'
    wb = load_workbook(path)
    assert wb.sheetnames == [f'{year}년 달력']
    ws = wb.active
    assert ws.max_column == 7 and not ws.protection.sheet
    metadata = ws['A2'].value
    mode = 'fixture' if '모의 테스트 자료' in metadata else 'manual' if '수동 자료만 사용' in metadata else 'official' if '한국천문연구원 getRestDeInfo' in metadata else None
    assert mode is not None, f'{year}: unknown workbook source label'
    assert not (run.get('fixture') is True and mode == 'official'), 'Fixture run must not claim official holiday data'
    expected_run = next((item for item in run.get('downloadedYears', []) if item['year'] == year), None)
    if expected_run:
        assert mode == expected_run['mode'], (year, mode, expected_run['mode'])
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        assert len(names) == len(set(names))
        assert len([name for name in names if re.fullmatch(r'xl/worksheets/sheet\d+\.xml', name)]) == 1
        assert all(not any(x in name.lower() for x in ['vba', 'externallink', 'connections']) for name in names)
        for name in names:
            if name.endswith(('.xml', '.rels')):
                tree = ET.fromstring(archive.read(name))
                assert not any(node.tag.split('}')[-1] in ['f', 'sheetProtection', 'externalReferences', 'connections'] for node in tree.iter())
                assert not any(node.attrib.get('TargetMode') == 'External' for node in tree.iter())
        sheet = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
        indexed = {c.attrib['r']: c for c in sheet.findall('.//s:c', ns)}
        expected_cells, seen_dates = set(), set()
        start, blank_count = 5, 0
        for month in range(1, 13):
            monday_offset, days = calendar.monthrange(year, month)
            offset = (monday_offset + 1) % 7
            weeks = (offset + days + 6) // 7
            assert ws.cell(start, 1).value == f'{year}년 {month}월'
            for slot in range(weeks * 7):
                number = slot - offset + 1
                real_date = 1 <= number <= days
                row, col = start + 2 + 4 * (slot // 7), slot % 7 + 1
                for band in range(4):
                    actual = ws.cell(row + band, col)
                    ref = actual.coordinate
                    expected_cells.add(ref)
                    item = preview[ref]
                    expected_date = dt.date(year, month, number).isoformat() if band == 0 and real_date else None
                    assert item['date'] == expected_date, (year, ref, item['date'], expected_date)
                    if expected_date:
                        assert expected_date not in seen_dates, f'{year}: duplicate date {expected_date}'
                        seen_dates.add(expected_date)
                        assert actual.data_type == 's'
                        # Decode SpreadsheetML's escaped literal sequences once, independently of the writer.
                        actual_text = re.sub(r'_x([0-9a-fA-F]{4})_', lambda match: chr(int(match[1], 16)), actual.value)
                        assert actual_text == item['text'], (year, ref, actual_text, item['text'])
                        assert item['text'].split('\n')[0] == str(number)
                    else:
                        assert actual.value is None and item['text'] == '', (year, ref)
                        assert ref not in ws.merged_cells
                        assert len(indexed[ref]) == 0 and 't' not in indexed[ref].attrib, (year, ref, 'blank contains XML value/formula/string')
                        if band and real_date:
                            blank_count += 1
            start += 3 + 4 * weeks
        assert set(preview) == expected_cells, f'{year}: preview omits or adds calendar cells'
        expected_dates = {dt.date(year, 1, 1) + dt.timedelta(days=index) for index in range(366 if calendar.isleap(year) else 365)}
        assert seen_dates == {day.isoformat() for day in expected_dates}
        assert blank_count == len(seen_dates) * 3
    reports.append({'year': year, 'result': 'PASS', 'sheet': ws.title, 'previewCells': len(cells),
                    'uniqueDates': len(seen_dates), 'emptyWritingCells': blank_count, 'mode': mode,
                    'fixtureContext': run.get('fixture'), 'engine': 'openpyxl + Python calendar + ZIP/XML; not native Excel'})

(base / 'browser-xlsx-inspection.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(reports, ensure_ascii=False))
