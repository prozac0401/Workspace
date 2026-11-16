"""Generate true BIFF8 XLS and OOXML XLSX with an embedded image (no Excel).
This does not exercise encryption, Excel COM, or object fidelity across SaveAs.
"""
from pathlib import Path
import json
import struct
from io import BytesIO
import hashlib
from PIL import Image
import xlwt
import olefile
import openpyxl
from openpyxl.drawing.image import Image as XLImage
from zipfile import ZipFile

base = Path(__file__).resolve().parent / 'fixtures'
base.mkdir(exist_ok=True)
image = Image.new('RGB', (40, 24), '#1677b8')
png = BytesIO(); image.save(png, format='PNG'); png.seek(0)
bmp = BytesIO(); image.save(bmp, format='BMP')
book = xlwt.Workbook(); sheet = book.add_sheet('한글_그림')
sheet.write(0, 0, 'Synthetic only'); sheet.write(1, 0, 42)
sheet.write(1, 1, xlwt.Formula('A2*2')); sheet.insert_bitmap_data(bmp.getvalue(), 4, 0)
xls = base / 'picture_biff8.xls'; book.save(str(xls))
book = openpyxl.Workbook(); sheet = book.active; sheet.title = '한글_그림'
sheet['A1'] = 'Synthetic only'; sheet['A2'] = 42; sheet['B2'] = '=A2*2'
sheet.add_image(XLImage(png), 'A5')
xlsx = base / 'picture_ooxml.xlsx'; book.save(xlsx)
with olefile.OleFileIO(xls) as ole:
    stream = ole.openstream('Workbook').read()
    record_ids = []; position = 0
    while position + 4 <= len(stream):
        ident, size = struct.unpack_from('<HH', stream, position)
        record_ids.append(ident); position += 4 + size
    assert 0x007F in record_ids, 'BIFF IMDATA image record missing'
with ZipFile(xlsx) as z:
    assert len([n for n in z.namelist() if n.startswith('xl/media/')]) == 1
reopened = openpyxl.load_workbook(xlsx)
assert reopened.active['B2'].value == '=A2*2'
assert len(reopened.active._images) == 1
report = {'scope': 'fixture creation and structure inspection ONLY, not Excel SaveAs',
          'fixtures': [{'name': p.name, 'bytes': p.stat().st_size,
                        'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                       for p in [xls, xlsx]],
          'checks': ['XLS OLE Workbook stream + BIFF IMDATA',
                     'XLSX embedded media + formula + image readback']}
(base / 'fixture-report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
