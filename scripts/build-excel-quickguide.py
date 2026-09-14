"""Build offline Excel guide/report from Markdown and reviewed native captures."""
from pathlib import Path
import base64
import mimetypes
import re
import markdown

root = Path(__file__).resolve().parents[1]
tool = root / 'tools/ExcelSmartListCompare'
css = '''body{margin:0;background:#edf2f6;color:#172c42;font:17px/1.75 "Malgun Gothic",sans-serif}
main{max-width:1040px;margin:36px auto;background:white;padding:40px 48px;border-radius:16px}
h1{font-size:32px;line-height:1.4;margin-top:0}h2{font-size:23px;margin-top:38px;border-top:1px solid #dbe4ec;padding-top:24px}
a{color:#075b92}code{background:#edf4f8;padding:2px 5px;border-radius:4px;overflow-wrap:anywhere}
img{max-width:100%;height:auto;border:1px solid #d8e2eb;border-radius:8px}
table{width:100%;border-collapse:collapse;font-size:15px}td,th{border-bottom:1px solid #dbe4ec;text-align:left;padding:9px 11px;overflow-wrap:anywhere}th{background:#edf4f8}
li{margin-bottom:7px}pre{overflow:auto}blockquote{border-left:4px solid #087c96;margin-left:0;padding-left:18px}
@media(max-width:650px){main{padding:20px;margin:0;border-radius:0}body{font-size:16px}h1{font-size:26px}}
@media print{body{background:white;font-size:10pt}main{margin:0;padding:0}img{max-height:150mm;object-fit:contain}h2{break-after:avoid}tr,img{break-inside:avoid}}'''
for filename, target, title in [
    ('QUICK_GUIDE.md', 'QuickGuide.html', 'Excel 명단 비교 설치·사용 퀵가이드'),
    ('WINDOWS_E2E_REPORT.md', 'Windows-E2E-Report.html', 'Excel 실제 Windows 테스트 보고서'),
    ('WINDOWS_TRUST_LOCATION_REPORT.md', 'Trust-Location-Report.html', 'Excel RC2 신뢰 위치 실제 검증 보고서'),
]:
    source = tool / 'docs' / filename
    content = markdown.markdown(source.read_text(encoding='utf-8-sig'), extensions=['tables', 'fenced_code'])
    for relative in set(re.findall(r'<img[^>]+src="([^"]+)"', content)):
        path = (source.parent / relative).resolve()
        if not path.is_relative_to(tool / 'docs/images'):
            raise ValueError('Unexpected image path: ' + relative)
        encoded = base64.b64encode(path.read_bytes()).decode('ascii')
        content = content.replace(relative, 'data:' + (mimetypes.guess_type(path)[0] or 'image/jpeg') + ';base64,' + encoded)
    content = content.replace('href="WINDOWS_E2E_REPORT.md"', 'href="Windows-E2E-Report.html"')
    content = content.replace('href="QUICK_GUIDE.md"', 'href="QuickGuide.html"')
    content = content.replace('href="WINDOWS_TRUST_LOCATION_REPORT.md"', 'href="Trust-Location-Report.html"')
    # Source-only references remain precise public source links in offline output.
    def link(match):
        href = match.group(1)
        if href.endswith('.md') and not href.startswith(('https:', 'http:')):
            path = (source.parent / href).resolve().relative_to(root).as_posix()
            return 'href="https://github.com/prozac0401/Workspace/blob/main/' + path + '"'
        return match.group(0)
    content = re.sub(r'href="([^"]+)"', link, content)
    html = '<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' + title + '</title><style>' + css + '</style><main>' + content + '</main></html>'
    output = tool / 'Release' / target
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(html, encoding='utf-8')
    print(output.name)
