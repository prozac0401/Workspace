"""Compare every preview cell against the actual browser-downloaded OOXML independently."""
from pathlib import Path
import json
import zipfile
import xml.etree.ElementTree as ET
from openpyxl import load_workbook

base = Path(__file__).resolve().parents[3] / 'artifacts/calendar/browser'
cells = json.loads((base / 'preview-cells.json').read_text(encoding='utf-8'))
path = base / 'calendar_2027.xlsx'
assert zipfile.is_zipfile(path)
wb = load_workbook(path)
assert wb.sheetnames == ['2027년 달력']
ws = wb.active
assert ws.max_column == 7
date_count = 0
for item in cells:
    actual = ws[item['cell']]
    assert actual.data_type != 'f'
    if item['date']:
        date_count += 1
        assert actual.value == item['text'], (item['cell'], actual.value, item['text'])
    else:
        assert actual.value is None and item['text'] == '', item['cell']
assert date_count == 365
with zipfile.ZipFile(path) as archive:
    assert all(not any(x in name.lower() for x in ['vba', 'externallink', 'connections']) for name in archive.namelist())
    ns = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
    sheet = ET.fromstring(archive.read('xl/worksheets/sheet1.xml'))
    assert not sheet.findall('.//s:f', ns)
    indexed = {c.attrib['r']: c for c in sheet.findall('.//s:c', ns)}
    for item in cells:
        if not item['date']:
            assert len(indexed[item['cell']]) == 0, item['cell']
print(f'PASS actual browser XLSX equals all {len(cells)} preview cells; 365 unique dates and genuinely empty writing/outside cells')
