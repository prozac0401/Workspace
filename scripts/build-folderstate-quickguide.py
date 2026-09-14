"""Build an offline quick guide with the reviewed native application captures."""
from pathlib import Path
import base64
import markdown
import mimetypes
import re

root = Path(__file__).resolve().parents[1]
source = root / 'docs/tools/folderstate/quick-guide.md'
content = markdown.markdown(source.read_text(encoding='utf-8'), extensions=['tables', 'fenced_code'])
for relative in set(re.findall(r'<img[^>]+src="([^"]+)"', content)):
    path = (source.parent / relative).resolve()
    if not path.is_relative_to(root / 'docs/assets'):
        raise ValueError('Unexpected image path: ' + relative)
    picture = base64.b64encode(path.read_bytes()).decode('ascii')
    content = content.replace(relative, 'data:' + (mimetypes.guess_type(path)[0] or 'image/jpeg') + ';base64,' + picture)
for name, route in [('installation.md', 'installation/'), ('index.md', ''), ('troubleshooting.md', 'troubleshooting/')]:
    content = content.replace('href="' + name + '"', 'href="https://prozac0401.github.io/Workspace/tools/folderstate/' + route + '"')
page = '''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>FolderState 0.1.0 설치·사용 퀵가이드</title><style>
body{margin:0;background:#edf2f6;color:#172c42;font:17px/1.75 "Malgun Gothic",sans-serif}
main{max-width:940px;margin:36px auto;background:white;padding:40px 52px;border-radius:16px}
h1{font-size:32px;line-height:1.4;margin-top:0}h2{font-size:23px;margin-top:38px;border-top:1px solid #dbe4ec;padding-top:24px}
a{color:#075b92}code{background:#edf4f8;padding:2px 5px;border-radius:4px}img{max-width:100%;height:auto;border:1px solid #d8e2eb;border-radius:10px}
table{width:100%;border-collapse:collapse}td,th{border-bottom:1px solid #dbe4ec;text-align:left;padding:9px 13px}th{background:#edf4f8}
li{margin-bottom:7px}@media(max-width:650px){main{padding:24px;margin:0;border-radius:0}body{font-size:16px}h1{font-size:27px}}
@media print{body{background:white;font-size:11pt}main{margin:0;padding:0}img{max-height:150mm;object-fit:contain}h2{break-after:avoid}table,img{break-inside:avoid}}
</style><main>''' + content + '</main></html>'
output = root / 'artifacts/release/FolderState-0.1.0-QuickGuide.html'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(page, encoding='utf-8')
print(output.name)
