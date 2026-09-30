"""Explicitly launched loopback-only browser fixture; never part of the product.
Use --port 0 for a free port. Ctrl+C shuts down the test HTTP server."""
import argparse, http.server, io, json, pathlib, urllib.parse, zipfile
def document(content):
    output=io.BytesIO()
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml','<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
        z.writestr('_rels/.rels','<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        z.writestr('xl/workbook.xml','<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Fixture" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr('xl/_rels/workbook.xml.rels','<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
        z.writestr('xl/worksheets/sheet1.xml','<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>'+content+'</t></is></c></row></sheetData></worksheet>')
    return output.getvalue()
FIXTURES={k:document(k) for k in ['A','B']} # Cache bytes; repeated A must be identical.
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_GET(self):
        url=urllib.parse.urlsplit(self.path); q=urllib.parse.parse_qs(url.query)
        if url.path=='/download':
            version=q.get('version',['A'])[0]; name=q.get('name',['보고서.xlsx'])[0]
            if version not in FIXTURES or name not in ['보고서.xlsx','회의자료 (1).xlsx','회의자료 (2).xlsx']:
                self.send_error(400); return
            data=FIXTURES[version]; self.send_response(200)
            self.send_header('Content-Type','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
            self.send_header('Content-Disposition',"attachment; filename=report.xlsx; filename*=UTF-8''"+urllib.parse.quote(name))
        else:
            data=('<!doctype html><meta charset="utf-8"><title>DVM browser fixtures</title><h1>DownloadVersionManager 합성 다운로드</h1><p>업무 파일과 분리된 평가용 profile·저장 폴더에서 확인하세요.</p><ol><li><a href="/download?version=A">보고서.xlsx A — 첫 다운로드 / 동일 내용</a></li><li><a href="/download?version=B">보고서.xlsx B — 다른 내용</a></li><li><a href="/download?version=A&name='+urllib.parse.quote('회의자료 (1).xlsx')+'">원래 이름에 (1) 포함</a></li><li><a href="/download?version=A&name='+urllib.parse.quote('회의자료 (2).xlsx')+'">원래 이름에 (2) 포함</a></li></ol>').encode('utf-8')
            self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8')
        self.send_header('Content-Length',str(len(data))); self.send_header('Cache-Control','no-store'); self.end_headers(); self.wfile.write(data)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=0);a=p.parse_args()
    with http.server.ThreadingHTTPServer(('127.0.0.1',a.port),Handler) as server:
        print(json.dumps({'url':f'http://127.0.0.1:{server.server_port}/','scope':'explicit test process only'}),flush=True)
        try: server.serve_forever()
        except KeyboardInterrupt: pass
