"""Independently compare browser preview and downloaded XLSX, including every blank.

Usage: python inspect-browser-export.py [--base DIRECTORY] [--years 1983 2026 2027 2099]
Pass --years with no following years to check only a captured custom export.
The selected directory contains calendar_YEAR.xlsx and preview-cells-YEAR.json.
The original 2027 preview-cells.json name remains supported.
When present, custom-formatting.json and the matching 2027 custom export/preview
are additionally checked against the actual font, fill, border and row settings.
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
parser.add_argument('--years', type=int, nargs='*', default=[1983, 2026, 2027, 2099])
args = parser.parse_args()
base = args.base.resolve()
run_path = base / 'results.json'
run = json.loads(run_path.read_text(encoding='utf-8')) if run_path.exists() else {}
reports = []
ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
      'dc': 'http://purl.org/dc/elements/1.1/', 'dcterms': 'http://purl.org/dc/terms/',
      'rels': 'http://schemas.openxmlformats.org/package/2006/relationships',
      'ct': 'http://schemas.openxmlformats.org/package/2006/content-types'}

targets = [(year, '') for year in args.years]
custom_path = base / 'custom-formatting.json'
custom_preview_path = base / 'preview-cells-2027-custom.json'
if custom_path.exists() and custom_preview_path.exists():
    targets.append((2027, 'custom'))

for year, variant in targets:
    preview_path = base / f'preview-cells-{year}{"-" + variant if variant else ""}.json'
    if year == 2027 and not preview_path.exists():
        assert not variant, 'Custom export requires its own matching preview'
        preview_path = base / 'preview-cells.json'
    cells = json.loads(preview_path.read_text(encoding='utf-8'))
    preview = {item['cell']: item for item in cells}
    assert len(preview) == len(cells), f'{year}: duplicate preview coordinates'
    path = base / f'calendar_{year}{"_" + variant if variant else ""}.xlsx'
    assert zipfile.is_zipfile(path), f'{year}: real ZIP-based XLSX required'
    wb = load_workbook(path)
    assert wb.sheetnames == [f'{year}년 달력']
    ws = wb.active
    assert ws.max_column == 7 and not ws.protection.sheet
    custom = json.loads(custom_path.read_text(encoding='utf-8')) if variant else None
    formatting = custom['formatting'] if custom else None
    if formatting:
        for key in ('fontSize', 'titleSize', 'writingRowHeight'):
            formatting[key] = int(formatting[key])
        argb = lambda color: 'FF' + color.removeprefix('#').upper()
        colors = {token: argb(formatting[key]) for token, key in {
            'black': 'textColor', 'red': 'holidayColor', 'blue': 'saturdayColor',
            'purple': 'manualColor', 'outside': 'textColor'}.items()}
        def check_style(cell, color, background, title=False):
            assert cell.font.name == formatting['fontFamily'], cell.coordinate
            assert cell.font.sz == formatting['titleSize' if title else 'fontSize'], cell.coordinate
            assert cell.font.color.type == 'rgb' and cell.font.color.rgb == color, cell.coordinate
            assert cell.fill.patternType == 'solid', cell.coordinate
            assert cell.fill.fgColor.type == 'rgb' and cell.fill.fgColor.rgb == argb(formatting[background]), cell.coordinate
    for row in range(1, 5):
        assert ws.row_dimensions[row].hidden, f'{year}: leading row {row} must be hidden'
        assert all(ws.cell(row, col).value is None for col in range(1, 8)), f'{year}: leading rows must be empty'
    metadata = wb.properties.description
    assert isinstance(metadata, str) and '자동 갱신되지 않습니다' in metadata, f'{year}: workbook metadata missing'
    show_lunar = '음력: 한국 음력 변환표' in metadata
    if custom and 'showLunar' in custom:
        assert type(custom['showLunar']) is bool and show_lunar == custom['showLunar']
    mode = 'fixture' if '모의 테스트 자료' in metadata else 'manual' if '수동 자료만 사용' in metadata else 'official' if '한국천문연구원 getRestDeInfo' in metadata else None
    assert mode is not None, f'{year}: unknown workbook source label'
    assert not (run.get('fixture') is True and mode == 'official'), 'Fixture run must not claim official holiday data'
    expected_run = next((item for item in run.get('downloadedYears', []) if item['year'] == year), None)
    if expected_run:
        assert mode == expected_run['mode'], (year, mode, expected_run['mode'])
        if 'showLunar' in expected_run:
            assert show_lunar == expected_run['showLunar'], (year, 'lunar option mismatch')
    if show_lunar:
        assert 1983 <= year <= 2050, 'Lunar display exceeds supported conversion range'
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        assert len(names) == len(set(names)) == 7
        assert set(names) == {'[Content_Types].xml', '_rels/.rels', 'docProps/core.xml', 'xl/workbook.xml',
                              'xl/_rels/workbook.xml.rels', 'xl/worksheets/sheet1.xml', 'xl/styles.xml'}
        assert len([name for name in names if re.fullmatch(r'xl/worksheets/sheet\d+\.xml', name)]) == 1
        assert all(not any(x in name.lower() for x in ['vba', 'externallink', 'connections']) for name in names)
        for name in names:
            if name.endswith(('.xml', '.rels')):
                tree = ET.fromstring(archive.read(name))
                assert not any(node.tag.split('}')[-1] in ['f', 'sheetProtection', 'externalReferences', 'connections'] for node in tree.iter())
                assert not any(node.attrib.get('TargetMode') == 'External' for node in tree.iter())
        sheet = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
        indexed = {c.attrib['r']: c for c in sheet.findall('.//s:c', ns)}
        for row in sheet.findall('s:sheetData/s:row', ns):
            if int(row.attrib['r']) <= 4:
                assert row.attrib.get('hidden') == '1'
                assert all(len(cell) == 0 and 't' not in cell.attrib for cell in row), f'{year}: leading rows contain XML content'
        core = ET.fromstring(archive.read('docProps/core.xml'))
        assert core.findtext('dc:description', namespaces=ns) == metadata
        assert core.findtext('dc:title', namespaces=ns) in (None, f'{year}년 달력')
        created = core.findtext('dcterms:created', namespaces=ns)
        assert created and created.endswith('Z'), f'{year}: generation time must be UTC ISO 8601'
        assert dt.datetime.fromisoformat(created.replace('Z', '+00:00')).utcoffset() == dt.timedelta(0)
        relationships = ET.fromstring(archive.read('_rels/.rels'))
        assert any(item.attrib.get('Target') == 'docProps/core.xml' and item.attrib.get('Type') ==
                   'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties'
                   for item in relationships.findall('rels:Relationship', ns))
        content_types = ET.fromstring(archive.read('[Content_Types].xml'))
        assert any(item.attrib.get('PartName') == '/docProps/core.xml' and item.attrib.get('ContentType') ==
                   'application/vnd.openxmlformats-package.core-properties+xml'
                   for item in content_types.findall('ct:Override', ns))
        expected_cells, seen_dates = set(), set()
        expected_merges, expected_breaks = [], []
        start, blank_count = 5, 0
        for month in range(1, 13):
            monday_offset, days = calendar.monthrange(year, month)
            offset = (monday_offset + 1) % 7
            weeks = (offset + days + 6) // 7
            assert ws.cell(start, 1).value == f'{year}년 {month}월'
            assert [ws.cell(start + 1, c).value for c in range(1, 8)] == list('일월화수목금토')
            if formatting:
                check_style(ws.cell(start, 1), argb(formatting['titleColor']), 'titleBackground', title=True)
                for col in range(1, 8):
                    check_style(ws.cell(start + 1, col), colors['red' if col == 1 else 'blue' if col == 7 else 'black'], 'weekdayBackground')
                assert ws.row_dimensions[start].height == max(30, formatting['titleSize'] * 1.5 + 6)
                assert ws.row_dimensions[start + 1].height == max(24, formatting['fontSize'] * 1.6 + 6)
            expected_merges.append(f'A{start}:G{start}')
            if month > 1:
                expected_breaks.append(start - 1)
            for slot in range(weeks * 7):
                number = slot - offset + 1
                real_date = 1 <= number <= days
                row, col = start + 2 + 4 * (slot // 7), slot % 7 + 1
                for band in range(4):
                    actual = ws.cell(row + band, col)
                    ref = actual.coordinate
                    expected_cells.add(ref)
                    item = preview[ref]
                    if formatting:
                        token = item['style'] if band == 0 and real_date else 'black'
                        check_style(actual, colors[token], 'background' if real_date else 'outsideBackground')
                        for side in (actual.border.left, actual.border.right, actual.border.top, actual.border.bottom):
                            assert side.color.type == 'rgb' and side.color.rgb == argb(formatting['borderColor']), ref
                        if band:
                            assert ws.row_dimensions[row + band].height == formatting['writingRowHeight'], ref
                    expected_date = dt.date(year, month, number).isoformat() if band == 0 and real_date else None
                    assert item['date'] == expected_date, (year, ref, item['date'], expected_date)
                    if expected_date:
                        assert expected_date not in seen_dates, f'{year}: duplicate date {expected_date}'
                        seen_dates.add(expected_date)
                        assert actual.data_type == 's'
                        # Decode SpreadsheetML's escaped literal sequences once, independently of the writer.
                        actual_text = re.sub(r'_x([0-9a-fA-F]{4})_', lambda match: chr(int(match[1], 16)), actual.value)
                        assert actual_text == item['text'], (year, ref, actual_text, item['text'])
                        first_line = item['text'].split('\n')[0]
                        if show_lunar:
                            assert re.fullmatch(str(number) + r' \((0[1-9]|1[0-2])\.(0[1-9]|[12]\d|30)\)', first_line), (year, ref, first_line)
                        else:
                            assert first_line == str(number)
                    else:
                        assert actual.value is None and item['text'] == '', (year, ref)
                        assert ref not in ws.merged_cells
                        assert len(indexed[ref]) == 0 and 't' not in indexed[ref].attrib, (year, ref, 'blank contains XML value/formula/string')
                        if band and real_date:
                            blank_count += 1
            end = start + 1 + 4 * weeks
            start += 3 + 4 * weeks
        assert sorted(str(x) for x in ws.merged_cells.ranges) == sorted(expected_merges)
        assert len(expected_merges) == 12
        assert [b.id for b in ws.row_breaks.brk] == expected_breaks and len(expected_breaks) == 11
        assert ws.max_row == end
        assert str(ws.print_area) == f"'{year}년 달력'!$A$5:$G${end}"
        assert set(preview) == expected_cells, f'{year}: preview omits or adds calendar cells'
        expected_dates = {dt.date(year, 1, 1) + dt.timedelta(days=index) for index in range(366 if calendar.isleap(year) else 365)}
        assert seen_dates == {day.isoformat() for day in expected_dates}
        assert blank_count == len(seen_dates) * 3
    reports.append({'year': year, 'variant': variant or 'default', 'filename': path.name, 'result': 'PASS', 'sheet': ws.title, 'previewCells': len(cells),
                    'uniqueDates': len(seen_dates), 'emptyWritingCells': blank_count, 'mode': mode,
                    'titleMerges': 12, 'hiddenEmptyLeadingRows': 4, 'metadataLocation': 'docProps/core.xml',
                    'showLunar': show_lunar, 'formatting': formatting, 'fixtureContext': run.get('fixture'), 'engine': 'openpyxl + Python calendar + ZIP/XML; not native Excel'})

if custom_path.exists() and not custom_preview_path.exists():
    reports.append({'year': 2027, 'variant': 'custom', 'result': 'NOT RUN',
                    'reason': 'Custom preview cells were not captured by this browser run; complete preview/export comparison requires a matching capture.'})
assert reports, 'No calendar exports were selected for inspection'

(base / 'browser-xlsx-inspection.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(reports, ensure_ascii=False))
