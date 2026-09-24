"""Validate public-only output, search, sitemap and local links."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import json
import sys
import xml.etree.ElementTree as ET

# Keep this explicit: a new page requires a publication-scope review.
public_routes = {
    '', 'getting-started/', 'quick-reference/', 'principles/',
    'policies/workspace/', 'policies/kits/', 'policies/files-email/',
    'policies/archive-security/', 'policies/decisions/', 'policies/folder-workflow/',
    'policies/work-efficiency/',
    'tools/folderstate/', 'tools/folderstate/installation/',
    'tools/folderstate/troubleshooting/',
    'tools/excel-list-compare/',
    'tools/bookmark/',
    'tools/excel-selection-export/', 'tools/file-list-to-excel/',
}
public_assets = {
    'assets/extra.css', 'assets/folderstate.png',
    'assets/handbook/workspace-flow.webp',
    'assets/handbook/work-lifecycle.webp',
    'assets/handbook/quiet-workspace.webp',
    'assets/handbook/focused-folder.webp',
    'assets/handbook/decision-checklist.webp',
    'assets/handbook/work-safety.webp',
}

site = Path(sys.argv[1] if len(sys.argv) > 1 else 'site').resolve()
docs = Path(__file__).resolve().parent.parent / 'docs'
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
expected_pages = {route + 'index.html' for route in public_routes} | {'404.html'}
actual_pages = {page.relative_to(site).as_posix() for page in pages}
for unexpected in sorted(actual_pages - expected_pages):
    errors.append(f'Non-public HTML was generated: {unexpected}')
for missing in sorted(expected_pages - actual_pages):
    errors.append(f'Missing public page: {missing}')

# MkDocs also copies non-Markdown files. Navigation checks alone miss these.
for source in docs.rglob('*'):
    if not source.is_file(): continue
    relative = source.relative_to(docs).as_posix()
    if relative not in public_assets and (site / relative).is_file():
        errors.append(f'Non-public source asset was copied: {relative}')
for asset in sorted(public_assets):
    if not (site / asset).is_file(): errors.append(f'Missing public asset: {asset}')

def route_from_url(url):
    parsed = urlsplit(url)
    if parsed.netloc and parsed.netloc != 'prozac0401.github.io': return None
    route = unquote(parsed.path)
    if route.startswith('/Workspace/'): route = route[len('/Workspace/'):]
    elif route.startswith('/'): return None
    if route.endswith('index.html'): route = route[:-len('index.html')]
    return route

search_file = site / 'search/search_index.json'
if not search_file.is_file():
    errors.append('Missing search index')
else:
    search_routes = set()
    for entry in json.loads(search_file.read_text(encoding='utf-8'))['docs']:
        route = route_from_url(entry['location'])
        search_routes.add(route)
        if route not in public_routes:
            errors.append(f'Non-public search entry: {entry["location"]}')
    for route in sorted(public_routes - search_routes):
        errors.append(f'Public page absent from search: {route or "/"}')

sitemap_file = site / 'sitemap.xml'
if not sitemap_file.is_file():
    errors.append('Missing sitemap')
else:
    sitemap_routes = {
        route_from_url(element.text or '')
        for element in ET.parse(sitemap_file).iter('{http://www.sitemaps.org/schemas/sitemap/0.9}loc')
    }
    if sitemap_routes != public_routes:
        errors.append('Sitemap does not match the public page list')

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
print(f'PASS {len(public_routes)} public pages + 404; search and sitemap contain only public routes; '
      'non-public source assets excluded; local routes and assets resolve.')
