"""Validate generated static routes and local assets without a browser."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import sys

site = Path(sys.argv[1] if len(sys.argv) > 1 else 'site').resolve()
class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.links = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        for key in ('href', 'src'):
            if attrs.get(key): self.links.append(attrs[key])

errors = []
pages = list(site.rglob('*.html'))
if not pages: raise SystemExit('No generated pages.')
for page in pages:
    parser = Links(); parser.feed(page.read_text(encoding='utf-8'))
    for link in parser.links:
        parsed = urlsplit(link)
        if parsed.scheme or parsed.netloc or not parsed.path: continue
        urlpath = unquote(parsed.path)
        if urlpath.startswith('/Workspace/'): target = site / urlpath[len('/Workspace/'):]
        elif urlpath.startswith('/'): target = site / urlpath.lstrip('/')
        else: target = page.parent / urlpath
        if target.is_dir(): target = target / 'index.html'
        if not target.exists(): errors.append(f'{page.relative_to(site)} -> {link}')
if errors: raise SystemExit('\n'.join(errors))
print(f'PASS {len(pages)} generated HTML pages; local routes and assets resolve.')
