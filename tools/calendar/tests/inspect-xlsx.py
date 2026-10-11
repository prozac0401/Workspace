"""Read-only independent calendar + ZIP/OOXML/openpyxl verification. Never authors XLSX."""
from pathlib import Path
import calendar
import datetime as dt
import json
import re
import sys
import xml.etree.ElementTree as ET
import zipfile
from openpyxl import load_workbook

path = (Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[3] / 'artifacts/calendar/calendar_2027.xlsx').resolve()
model_path = Path(sys.argv[2]) if len(sys.argv) > 2 else path.with_name('model_' + path.stem.split('_')[-1] + '.json')
model = json.loads(model_path.read_text(encoding='utf-8'))
year = model['config']['year']
assert zipfile.is_zipfile(path), 'Real ZIP-based XLSX required; HTML/CSV is forbidden'
wb = load_workbook(path)
assert wb.sheetnames == [f'{year}년 달력'], wb.sheetnames
ws = wb.active
assert ws.max_column == 7
assert not ws.protection.sheet
assert ws.sheet_view.showGridLines is False
assert ws.print_options.gridLines is False
assert ws.page_setup.orientation == 'portrait'
assert str(ws.page_setup.paperSize) == '9'
assert ws.page_setup.fitToWidth == 1 and ws.page_setup.fitToHeight == 0
assert ws.sheet_properties.pageSetUpPr.fitToPage is True
assert ws.print_title_rows is None
assert ws.column_dimensions['A'].min == 1 and ws.column_dimensions['A'].max == 7
assert ws.column_dimensions['A'].width == 18
for row in range(1, 5):
    assert ws.row_dimensions[row].hidden, f'Leading row {row} must be hidden'
    assert all(ws.cell(row, col).value is None for col in range(1, 8)), 'Leading rows must be empty'
description = model['metadataText'] + '\n' + model['legendText']
assert wb.properties.description == description
assert wb.properties.title in (None, model['title'])
assert '모의 테스트' in description
assert '자동 갱신되지 않습니다' in description

ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
      'dc': 'http://purl.org/dc/elements/1.1/', 'dcterms': 'http://purl.org/dc/terms/',
      'rels': 'http://schemas.openxmlformats.org/package/2006/relationships',
      'ct': 'http://schemas.openxmlformats.org/package/2006/content-types'}
formatting = model['formatting']
argb = lambda value: 'FF' + value.removeprefix('#').upper()
colors = {token: argb(formatting[key]) for token, key in {
    'black': 'textColor', 'red': 'holidayColor', 'blue': 'saturdayColor',
    'purple': 'manualColor', 'outside': 'textColor'}.items()}


def check_font(cell, color, title=False):
    assert cell.font.name == formatting['fontFamily'], (cell.coordinate, cell.font.name)
    assert cell.font.sz == formatting['titleSize' if title else 'fontSize'], (cell.coordinate, cell.font.sz)
    assert cell.font.color.type == 'rgb' and cell.font.color.rgb == color, (cell.coordinate, cell.font.color)


def check_fill(cell, key):
    assert cell.fill.patternType == 'solid', (cell.coordinate, cell.fill.patternType)
    assert cell.fill.fgColor.type == 'rgb' and cell.fill.fgColor.rgb == argb(formatting[key]), (cell.coordinate, cell.fill.fgColor)



def check_display_runs(element, day):
    """Check the model's segments and their actual OOXML character styles."""
    runs = day['displayRuns']
    expected = [{'kind': 'solar', 'text': str(day['dayNumber']),
                 'fontSize': formatting['fontSize'], 'color': '#' + colors[day['styleToken']][2:]}]
    if model['config'].get('showLunar', False):
        expected.append({'kind': 'lunar', 'text': ' (' + day['lunar']['text'] + ')',
                         'fontSize': formatting['lunarFontSize'], 'color': formatting['lunarColor']})
    if '\n' in day['displayText']:
        expected.append({'kind': 'holidays', 'text': '\n' + day['displayText'].split('\n', 1)[1],
                         'fontSize': formatting['fontSize'], 'color': '#' + colors[day['styleToken']][2:]})
    assert runs == expected, (day['date'], runs, expected)
    assert ''.join(run['text'] for run in runs) == day['displayText']
    actual = element.findall('s:is/s:r', ns)
    if not model['config'].get('showLunar', False):
        assert actual == [], (day['date'], 'Lunar-off cell must remain a plain string')
        assert element.find('s:is/s:t', ns) is not None
        return
    assert element.find('s:is/s:t', ns) is None
    assert len(actual) == len(runs), (day['date'], len(actual), len(runs))
    for node, expected in zip(actual, runs):
        text = node.find('s:t', ns)
        assert text is not None and text.attrib.get('{http://www.w3.org/XML/1998/namespace}space') == 'preserve'
        decoded = re.sub(r'_x([0-9a-fA-F]{4})_', lambda match: chr(int(match[1], 16)), text.text or '')
        assert decoded == expected['text'], (day['date'], expected['kind'], decoded, expected['text'])
        properties = node.find('s:rPr', ns)
        assert properties is not None
        assert properties.find('s:rFont', ns).attrib['val'] == formatting['fontFamily']
        assert float(properties.find('s:sz', ns).attrib['val']) == expected['fontSize']
        assert properties.find('s:color', ns).attrib == {'rgb': argb(expected['color'])}

dates = {}
for month in model['months']:
    for day in month['slots']:
        if day['date']:
            assert day['date'] not in dates, 'Model repeated a date'
            dates[day['date']] = day

with zipfile.ZipFile(path) as z:
    assert z.testzip() is None, 'ZIP CRC failure'
    names = z.namelist()
    assert len(names) == len(set(names)) == 7
    assert set(names) == {'[Content_Types].xml', '_rels/.rels', 'docProps/core.xml', 'xl/workbook.xml',
                          'xl/_rels/workbook.xml.rels', 'xl/worksheets/sheet1.xml', 'xl/styles.xml'}
    assert names.count('xl/worksheets/sheet1.xml') == 1
    assert not any(term in name.lower() for name in names for term in ['vba', 'externallink', 'connection'])
    for name in names:
        xml = ET.fromstring(z.read(name))
        assert not any(node.tag.split('}')[-1] in ['f', 'sheetProtection', 'externalReferences', 'connections'] for node in xml.iter())
        assert not any(node.attrib.get('TargetMode') == 'External' for node in xml.iter())
    sheet = ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
    cells = {c.attrib['r']: c for c in sheet.findall('.//s:c', ns)}
    for row in sheet.findall('s:sheetData/s:row', ns):
        if int(row.attrib['r']) <= 4:
            assert row.attrib.get('hidden') == '1'
            assert all(len(cell) == 0 and 't' not in cell.attrib for cell in row), 'Leading rows contain XML content'
    core = ET.fromstring(z.read('docProps/core.xml'))
    assert core.findtext('dc:description', namespaces=ns) == description
    created = core.findtext('dcterms:created', namespaces=ns)
    assert created and created.endswith('Z'), 'Generation time must be UTC ISO 8601'
    assert dt.datetime.fromisoformat(created.replace('Z', '+00:00')) == dt.datetime.fromisoformat(model['generatedAt'].replace('Z', '+00:00'))
    relationships = ET.fromstring(z.read('_rels/.rels'))
    assert any(item.attrib.get('Target') == 'docProps/core.xml' and item.attrib.get('Type') ==
               'http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties'
               for item in relationships.findall('rels:Relationship', ns))
    content_types = ET.fromstring(z.read('[Content_Types].xml'))
    assert any(item.attrib.get('PartName') == '/docProps/core.xml' and item.attrib.get('ContentType') ==
               'application/vnd.openxmlformats-package.core-properties+xml'
               for item in content_types.findall('ct:Override', ns))
    merges = []
    start = 5
    blanks = 0
    date_count = 0
    expected_breaks = []
    for month in range(1, 13):
        offset_mon, days = calendar.monthrange(year, month)
        offset = (offset_mon + 1) % 7
        weeks = (offset + days + 6) // 7
        assert model['months'][month - 1]['weeks'] == weeks
        assert model['months'][month - 1]['startRow'] == start
        assert ws.cell(start, 1).value == f'{year}년 {month}월'
        assert [ws.cell(start + 1, c).value for c in range(1, 8)] == list('일월화수목금토')
        check_font(ws.cell(start, 1), argb(formatting['titleColor']), title=True)
        check_fill(ws.cell(start, 1), 'titleBackground')
        for c in range(1, 8):
            check_font(ws.cell(start + 1, c), colors['red' if c == 1 else 'blue' if c == 7 else 'black'])
            check_fill(ws.cell(start + 1, c), 'weekdayBackground')
        merges.append(f'A{start}:G{start}')
        if month > 1:
            expected_breaks.append(start - 1)
        for k in range(weeks * 7):
            number = k - offset + 1
            row, col = start + 2 + 4 * (k // 7), k % 7 + 1
            cell = ws.cell(row, col)
            if 1 <= number <= days:
                iso = dt.date(year, month, number).isoformat()
                day = dates[iso]
                assert day['excelRow'] == row and day['excelColumn'] == col
                # openpyxl preserves the escaped underscore used by Excel's _xNNNN_ syntax.
                expected = re.sub(r'(_x[0-9a-fA-F]{4}_)', lambda m: '_x005F_' + m[0][1:], day['displayText'])
                assert cell.value == expected, (iso, cell.coordinate, cell.value, expected)
                if model['config'].get('showLunar', False):
                    lunar = day['lunar']
                    assert 1983 <= year <= 2050 and type(lunar['isLeapMonth']) is bool
                    assert 1 <= lunar['month'] <= 12 and 1 <= lunar['day'] <= 30
                    assert lunar['text'] == f"{lunar['month']:02}.{lunar['day']:02}"
                    assert day['displayText'].split('\n')[0] == f"{number} ({lunar['text']})"
                else:
                    assert day.get('lunar') is None
                    assert day['displayText'].split('\n')[0] == str(number)
                check_display_runs(cells[cell.coordinate], day)
                assert cell.data_type == 's', (iso, cell.data_type)
                check_font(cell, colors[day['styleToken']])
                assert cell.alignment.wrapText and cell.alignment.vertical == 'top'
                assert 34 <= ws.row_dimensions[row].height <= 409
                date_count += 1
            else:
                assert cell.value is None, 'Adjacent-month date must stay empty'
                assert len(cells[cell.coordinate]) == 0
                check_font(cell, colors['outside'])
            check_fill(cell, 'background' if 1 <= number <= days else 'outsideBackground')
            for delta in range(1, 4):
                blank = ws.cell(row + delta, col)
                assert blank.value is None and blank.data_type != 'f'
                assert blank.coordinate not in ws.merged_cells
                assert ws.row_dimensions[blank.row].height == formatting['writingRowHeight']
                check_font(blank, colors['black'])
                check_fill(blank, 'background' if 1 <= number <= days else 'outsideBackground')
                for side in (blank.border.left, blank.border.right, blank.border.top, blank.border.bottom):
                    assert side.color.type == 'rgb' and side.color.rgb == argb(formatting['borderColor'])
                element = cells[blank.coordinate]
                assert len(element) == 0 and 't' not in element.attrib, 'Writing cell contains value/formula/string/space'
                assert element.attrib.get('s') is not None, 'Styled editable blank expected'
                if 1 <= number <= days:
                    blanks += 1
        end = start + 1 + 4 * weeks
        start += 3 + 4 * weeks
    assert sorted(str(x) for x in ws.merged_cells.ranges) == sorted(merges)
    assert len(merges) == 12
    assert [b.id for b in ws.row_breaks.brk] == expected_breaks
    assert len(expected_breaks) == 11
    assert ws.max_row == end
    assert str(ws.print_area) == f"'{year}년 달력'!$A$5:$G${end}"
    assert date_count == len(dates) == (366 if calendar.isleap(year) else 365)
    assert blanks == date_count * 3
    for row in ws:
        for cell in row:
            assert cell.data_type != 'f'
    for prefix in ['=SUM(A1:A2)', '+1', '-1', '@test']:
        assert any(prefix in str(c.value) and c.data_type == 's' for row in ws for c in row)

report = {'status': 'PASS', 'engine': 'openpyxl 3.1.5 + independent Python calendar + ZIP/XML (not Excel)',
          'year': year, 'dates': date_count, 'independentBlankCells': blanks, 'sheets': 1, 'months': 12,
          'columns': 7, 'titleMerges': 12, 'hiddenEmptyLeadingRows': 4, 'metadataLocation': 'docProps/core.xml',
          'showLunar': model['config'].get('showLunar', False), 'richTextDateCells': date_count if model['config'].get('showLunar', False) else 0, 'formatting': formatting, 'manualPageBreaks': 11, 'formulas': 0, 'datasetKind': 'fixture'}
path.with_name(f'inspection_{year}.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
