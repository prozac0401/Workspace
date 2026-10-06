"""Validate public-only output, search, sitemap and local links."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import json
import re
import sys
import xml.etree.ElementTree as ET

# Keep this explicit: a new page requires a publication-scope review.
public_routes = {
    '', 'getting-started/', 'quick-reference/', 'principles/', 'education-operations/',
    'policies/workspace/', 'policies/kits/', 'policies/files-email/',
    'policies/archive-security/', 'policies/decisions/', 'policies/folder-workflow/',
    'policies/work-efficiency/',
    'tools/folderstate/',
    'tools/excel-list-compare/',
    'tools/bookmark/',
    'tools/excel-selection-export/', 'tools/file-list-to-excel/',
    'tools/visible-cells-paste/',
    'tools/image-copy-save/guide/',
    'tools/download-version-manager/',
    'tools/office-automation/',
}
public_redirects = {
    'tools/folderstate/installation/': '../#installation',
    'tools/folderstate/troubleshooting/': '../#troubleshooting',
}
public_assets = {
    'assets/extra.css', 'assets/folderstate.png',
    'assets/tool-guides/bookmark-guide-apps-mobile.svg',
    'assets/tool-guides/bookmark-guide-apps.svg',
    'assets/tool-guides/bookmark-guide-backup-mobile.svg',
    'assets/tool-guides/bookmark-guide-backup.svg',
    'assets/tool-guides/bookmark-guide-custom-path-mobile.svg',
    'assets/tool-guides/bookmark-guide-custom-path.svg',
    'assets/tool-guides/bookmark-guide-download-mobile.svg',
    'assets/tool-guides/bookmark-guide-download.svg',
    'assets/tool-guides/bookmark-guide-maintenance-mobile.svg',
    'assets/tool-guides/bookmark-guide-maintenance.svg',
    'assets/tool-guides/bookmark-guide-manage-mobile.svg',
    'assets/tool-guides/bookmark-guide-manage.svg',
    'assets/tool-guides/bookmark-guide-notepad-mobile.svg',
    'assets/tool-guides/bookmark-guide-notepad.svg',
    'assets/tool-guides/bookmark-guide-office-site-mobile.svg',
    'assets/tool-guides/bookmark-guide-office-site.svg',
    'assets/tool-guides/bookmark-guide-settings-mobile.svg',
    'assets/tool-guides/bookmark-guide-settings.svg',
    'assets/tool-guides/bookmark-guide-start-mobile.svg',
    'assets/tool-guides/bookmark-guide-start.svg',
    'assets/tool-guides/bookmark-guide-stickers-mobile.svg',
    'assets/tool-guides/bookmark-guide-stickers.svg',
    'assets/tool-guides/bookmark-guide-sticker-arrangement-mobile.svg',
    'assets/tool-guides/bookmark-guide-sticker-arrangement.svg',
    'assets/tool-guides/bookmark-guide-sticker-visibility-mobile.svg',
    'assets/tool-guides/bookmark-guide-sticker-visibility.svg',
    'assets/tool-guides/bookmark-guide-troubleshooting-mobile.svg',
    'assets/tool-guides/bookmark-guide-troubleshooting.svg',
    'assets/tool-guides/bookmark-guide-url-mobile.svg',
    'assets/tool-guides/bookmark-guide-url.svg',
    'assets/tool-guides/download-manager-first-review-mobile.svg',
    'assets/tool-guides/download-manager-first-review.svg',
    'assets/tool-guides/download-manager-new-file-mobile.svg',
    'assets/tool-guides/download-manager-new-file.svg',
    'assets/tool-guides/download-manager-preserve-mobile.svg',
    'assets/tool-guides/download-manager-preserve.svg',
    'assets/tool-guides/download-manager-start-mobile.svg',
    'assets/tool-guides/download-manager-start.svg',
    'assets/tool-guides/download-manager-support-mobile.svg',
    'assets/tool-guides/download-manager-support.svg',
    'assets/tool-guides/download-manager-tray-mobile.svg',
    'assets/tool-guides/download-manager-tray.svg',
    'assets/tool-guides/download-manager-versions-mobile.svg',
    'assets/tool-guides/download-manager-versions.svg',
    'assets/tool-guides/excel-compare-mobile.svg',
    'assets/tool-guides/excel-compare.svg',
    'assets/tool-guides/excel-download-mobile.svg',
    'assets/tool-guides/excel-download.svg',
    'assets/tool-guides/excel-install-mobile.svg',
    'assets/tool-guides/excel-install.svg',
    'assets/tool-guides/excel-limits-mobile.svg',
    'assets/tool-guides/excel-limits.svg',
    'assets/tool-guides/excel-maintenance-mobile.svg',
    'assets/tool-guides/excel-maintenance.svg',
    'assets/tool-guides/excel-results-mobile.svg',
    'assets/tool-guides/excel-results.svg',
    'assets/tool-guides/excel-settings-mobile.svg',
    'assets/tool-guides/excel-settings.svg',
    'assets/tool-guides/excel-snapshot-mobile.svg',
    'assets/tool-guides/excel-snapshot.svg',
    'assets/tool-guides/filelist-ai-batch-mobile.svg',
    'assets/tool-guides/filelist-ai-batch.svg',
    'assets/tool-guides/filelist-ai-dialogue-mobile.svg',
    'assets/tool-guides/filelist-ai-dialogue.svg',
    'assets/tool-guides/filelist-ai-inventory-mobile.svg',
    'assets/tool-guides/filelist-ai-inventory.svg',
    'assets/tool-guides/filelist-ai-organization-mobile.svg',
    'assets/tool-guides/filelist-ai-organization.svg',
    'assets/tool-guides/filelist-ai-review-mobile.svg',
    'assets/tool-guides/filelist-ai-review.svg',
    'assets/tool-guides/filelist-ai-simple-copy-mobile.svg',
    'assets/tool-guides/filelist-ai-simple-copy.svg',
    'assets/tool-guides/filelist-ai-structure-mobile.svg',
    'assets/tool-guides/filelist-ai-structure.svg',
    'assets/tool-guides/filelist-collect-mobile.svg',
    'assets/tool-guides/filelist-collect.svg',
    'assets/tool-guides/filelist-download-mobile.svg',
    'assets/tool-guides/filelist-download.svg',
    'assets/tool-guides/filelist-duplicates-mobile.svg',
    'assets/tool-guides/filelist-duplicates.svg',
    'assets/tool-guides/filelist-list-mobile.svg',
    'assets/tool-guides/filelist-list.svg',
    'assets/tool-guides/filelist-results-mobile.svg',
    'assets/tool-guides/filelist-results.svg',
    'assets/tool-guides/folderstate-guide-advanced-mobile.svg',
    'assets/tool-guides/folderstate-guide-advanced.svg',
    'assets/tool-guides/folderstate-guide-buttons-mobile.svg',
    'assets/tool-guides/folderstate-guide-buttons.svg',
    'assets/tool-guides/folderstate-guide-download-mobile.svg',
    'assets/tool-guides/folderstate-guide-download.svg',
    'assets/tool-guides/folderstate-guide-error-codes-mobile.svg',
    'assets/tool-guides/folderstate-guide-error-codes.svg',
    'assets/tool-guides/folderstate-guide-explorer-mobile.svg',
    'assets/tool-guides/folderstate-guide-explorer.svg',
    'assets/tool-guides/folderstate-guide-files-mobile.svg',
    'assets/tool-guides/folderstate-guide-files.svg',
    'assets/tool-guides/folderstate-guide-icon-refresh-mobile.svg',
    'assets/tool-guides/folderstate-guide-icon-refresh.svg',
    'assets/tool-guides/folderstate-guide-installation-mobile.svg',
    'assets/tool-guides/folderstate-guide-installation.svg',
    'assets/tool-guides/folderstate-guide-logs-mobile.svg',
    'assets/tool-guides/folderstate-guide-logs.svg',
    'assets/tool-guides/folderstate-guide-maintenance-mobile.svg',
    'assets/tool-guides/folderstate-guide-maintenance.svg',
    'assets/tool-guides/folderstate-guide-master-mobile.svg',
    'assets/tool-guides/folderstate-guide-master.svg',
    'assets/tool-guides/folderstate-guide-next-ui-mobile.svg',
    'assets/tool-guides/folderstate-guide-next-ui.svg',
    'assets/tool-guides/folderstate-guide-portable-mobile.svg',
    'assets/tool-guides/folderstate-guide-portable.svg',
    'assets/tool-guides/folderstate-guide-remove-mobile.svg',
    'assets/tool-guides/folderstate-guide-remove.svg',
    'assets/tool-guides/folderstate-guide-repair-mobile.svg',
    'assets/tool-guides/folderstate-guide-repair.svg',
    'assets/tool-guides/folderstate-guide-requirements-mobile.svg',
    'assets/tool-guides/folderstate-guide-requirements.svg',
    'assets/tool-guides/folderstate-guide-reset-mobile.svg',
    'assets/tool-guides/folderstate-guide-reset.svg',
    'assets/tool-guides/folderstate-guide-start-mobile.svg',
    'assets/tool-guides/folderstate-guide-start.svg',
    'assets/tool-guides/folderstate-guide-state-choice-mobile.svg',
    'assets/tool-guides/folderstate-guide-state-choice.svg',
    'assets/tool-guides/folderstate-guide-states-mobile.svg',
    'assets/tool-guides/folderstate-guide-states.svg',
    'assets/tool-guides/folderstate-guide-troubleshooting-mobile.svg',
    'assets/tool-guides/folderstate-guide-troubleshooting.svg',
    'assets/tool-guides/folderstate-guide-update-mobile.svg',
    'assets/tool-guides/folderstate-guide-update.svg',
    'assets/tool-guides/folderstate-guide-use-mobile.svg',
    'assets/tool-guides/folderstate-guide-use.svg',
    'assets/tool-guides/image-copy-save-before-install-mobile.svg',
    'assets/tool-guides/image-copy-save-before-install.svg',
    'assets/tool-guides/image-copy-save-copy-mobile.svg',
    'assets/tool-guides/image-copy-save-copy.svg',
    'assets/tool-guides/image-copy-save-install-mobile.svg',
    'assets/tool-guides/image-copy-save-install.svg',
    'assets/tool-guides/image-copy-save-maintenance-mobile.svg',
    'assets/tool-guides/image-copy-save-maintenance.svg',
    'assets/tool-guides/image-copy-save-save-mobile.svg',
    'assets/tool-guides/image-copy-save-save.svg',
    'assets/tool-guides/image-copy-save-scope-mobile.svg',
    'assets/tool-guides/image-copy-save-scope.svg',
    'assets/tool-guides/image-copy-save-troubleshooting-mobile.svg',
    'assets/tool-guides/image-copy-save-troubleshooting.svg',
    'assets/tool-guides/office-common-mobile.svg',
    'assets/tool-guides/office-common.svg',
    'assets/tool-guides/office-download-mobile.svg',
    'assets/tool-guides/office-download.svg',
    'assets/tool-guides/office-formats-mobile.svg',
    'assets/tool-guides/office-formats.svg',
    'assets/tool-guides/office-maintenance-mobile.svg',
    'assets/tool-guides/office-maintenance.svg',
    'assets/tool-guides/office-merge-mobile.svg',
    'assets/tool-guides/office-merge.svg',
    'assets/tool-guides/office-outputs-mobile.svg',
    'assets/tool-guides/office-outputs.svg',
    'assets/tool-guides/office-prepare-mobile.svg',
    'assets/tool-guides/office-prepare.svg',
    'assets/tool-guides/office-protection-mobile.svg',
    'assets/tool-guides/office-protection.svg',
    'assets/tool-guides/office-resume-mobile.svg',
    'assets/tool-guides/office-resume.svg',
    'assets/tool-guides/office-settings-mobile.svg',
    'assets/tool-guides/office-settings.svg',
    'assets/tool-guides/office-split-mobile.svg',
    'assets/tool-guides/office-split.svg',
    'assets/tool-guides/office-start-mobile.svg',
    'assets/tool-guides/office-start.svg',
    'assets/tool-guides/office-template-mobile.svg',
    'assets/tool-guides/office-template.svg',
    'assets/tool-guides/office-trial-mobile.svg',
    'assets/tool-guides/office-trial.svg',
    'assets/tool-guides/office-troubleshooting-mobile.svg',
    'assets/tool-guides/office-troubleshooting.svg',
    'assets/tool-guides/selection-export-before-download-mobile.svg',
    'assets/tool-guides/selection-export-before-download.svg',
    'assets/tool-guides/selection-export-download-mobile.svg',
    'assets/tool-guides/selection-export-download.svg',
    'assets/tool-guides/selection-export-export-mobile.svg',
    'assets/tool-guides/selection-export-export.svg',
    'assets/tool-guides/selection-export-faq-excel-copy-mobile.svg',
    'assets/tool-guides/selection-export-faq-excel-copy.svg',
    'assets/tool-guides/selection-export-faq-format-mobile.svg',
    'assets/tool-guides/selection-export-faq-format.svg',
    'assets/tool-guides/selection-export-faq-layout-mobile.svg',
    'assets/tool-guides/selection-export-faq-layout.svg',
    'assets/tool-guides/selection-export-faq-limits-mobile.svg',
    'assets/tool-guides/selection-export-faq-limits.svg',
    'assets/tool-guides/selection-export-faq-mobile.svg',
    'assets/tool-guides/selection-export-faq-original-mobile.svg',
    'assets/tool-guides/selection-export-faq-original.svg',
    'assets/tool-guides/selection-export-faq-save-mobile.svg',
    'assets/tool-guides/selection-export-faq-save.svg',
    'assets/tool-guides/selection-export-faq-scroll-mobile.svg',
    'assets/tool-guides/selection-export-faq-scroll.svg',
    'assets/tool-guides/selection-export-faq-selection-mobile.svg',
    'assets/tool-guides/selection-export-faq-selection.svg',
    'assets/tool-guides/selection-export-faq-startup-mobile.svg',
    'assets/tool-guides/selection-export-faq-startup.svg',
    'assets/tool-guides/selection-export-faq-tabs-mobile.svg',
    'assets/tool-guides/selection-export-faq-tabs.svg',
    'assets/tool-guides/selection-export-faq-values-mobile.svg',
    'assets/tool-guides/selection-export-faq-values.svg',
    'assets/tool-guides/selection-export-faq-visible-mobile.svg',
    'assets/tool-guides/selection-export-faq-visible.svg',
    'assets/tool-guides/selection-export-faq.svg',
    'assets/tool-guides/selection-export-install-mobile.svg',
    'assets/tool-guides/selection-export-install.svg',
    'assets/tool-guides/selection-export-maintenance-mobile.svg',
    'assets/tool-guides/selection-export-maintenance.svg',
    'assets/tool-guides/selection-export-supported-range-mobile.svg',
    'assets/tool-guides/selection-export-supported-range.svg',
    'assets/tool-guides/selection-export-troubleshooting-mobile.svg',
    'assets/tool-guides/selection-export-troubleshooting.svg',
    'assets/tool-guides/visible-paste-download-mobile.svg',
    'assets/tool-guides/visible-paste-download.svg',
    'assets/tool-guides/visible-paste-install-mobile.svg',
    'assets/tool-guides/visible-paste-install.svg',
    'assets/tool-guides/visible-paste-limits-mobile.svg',
    'assets/tool-guides/visible-paste-limits.svg',
    'assets/tool-guides/visible-paste-maintenance-mobile.svg',
    'assets/tool-guides/visible-paste-maintenance.svg',
    'assets/tool-guides/visible-paste-troubleshooting-mobile.svg',
    'assets/tool-guides/visible-paste-troubleshooting.svg',
    'assets/tool-guides/visible-paste-undo-mobile.svg',
    'assets/tool-guides/visible-paste-undo.svg',
    'assets/tool-guides/visible-paste-use-mobile.svg',
    'assets/tool-guides/visible-paste-use.svg',
    'assets/tool-guides/visible-paste-values-mobile.svg',
    'assets/tool-guides/visible-paste-values.svg',

    'assets/handbook/workspace-flow.webp',
    'assets/handbook/work-lifecycle.webp',
    'assets/handbook/quiet-workspace.webp',
    'assets/handbook/focused-folder.webp',
    'assets/handbook/decision-checklist.webp',
    'assets/handbook/work-safety.webp',
    'assets/education-examples/compare.png',
    'assets/education-examples/paste.png',
    'assets/education-examples/export.png',
    'assets/education-examples/collect.png',
    'assets/education-examples/image.png',
    'assets/education-examples/bookmark.png',
    'assets/education-examples/state.png',
}

site = Path(sys.argv[1] if len(sys.argv) > 1 else 'site').resolve()
docs = Path(__file__).resolve().parent.parent / 'docs'
class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.links = []; self.ids = set()
        self.canonical = None; self.refresh = None; self.noindex = False
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if attrs.get('id'): self.ids.add(attrs['id'])
        if tag == 'link' and attrs.get('rel') == 'canonical':
            self.canonical = attrs.get('href')
        if tag == 'meta' and attrs.get('http-equiv', '').lower() == 'refresh':
            self.refresh = attrs.get('content')
        if tag == 'meta' and attrs.get('name') == 'robots':
            self.noindex = attrs.get('content') == 'noindex'
        for key in ('href', 'src'):
            if attrs.get(key): self.links.append(attrs[key])
        if attrs.get('srcset'):
            self.links.extend(candidate.strip().split()[0]
                              for candidate in attrs['srcset'].split(',') if candidate.strip())

errors = []
pages = list(site.rglob('*.html'))
if not pages: raise SystemExit('No generated pages.')
expected_pages = {route + 'index.html' for route in public_routes | public_redirects.keys()} | {'404.html'}
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

for route, destination in public_redirects.items():
    redirect = site / route / 'index.html'
    if not redirect.is_file(): continue
    parser = Links(); parser.feed(redirect.read_text(encoding='utf-8'))
    if (parser.canonical != destination or parser.refresh != f'0; url={destination}'
            or not parser.noindex or destination not in parser.links):
        errors.append(f'Invalid legacy redirect: {route}')
    target = urlsplit(destination)
    target_file = redirect.parent / target.path / 'index.html'
    if not target_file.is_file():
        errors.append(f'Missing redirect destination: {route} -> {destination}')
    else:
        target_parser = Links(); target_parser.feed(target_file.read_text(encoding='utf-8'))
        if target.fragment not in target_parser.ids:
            errors.append(f'Missing redirect section: {route} -> {destination}')

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
        if route == 'tools/visible-cells-paste/':
            text = entry.get('title', '') + ' ' + entry.get('text', '')
            if re.search(r'평가판|시험|테스트|미검증|검증\s*(?:상태|결과)|\b(?:PASS|FAIL|BLOCKED)\b|NOT RUN', text, re.IGNORECASE):
                errors.append('VisibleCellsPaste public guide contains development status or test results')
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
print(f'PASS {len(public_routes)} public pages + {len(public_redirects)} legacy redirects + 404; '
      'search and sitemap contain only public routes; '
      'non-public source assets excluded; local routes and assets resolve.')
