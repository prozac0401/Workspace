"""Keep published FolderState links working after merging the three guides."""
import json
from pathlib import Path


REDIRECTS = {
    'installation': {
        '': 'installation', 'folderstate': 'installation',
        '_1': 'requirements', '_2': 'installation', '_3': 'repair',
        '_4': 'update', '_5': 'remove', '_6': 'locations', '_7': 'installer-cli',
    },
    'troubleshooting': {
        '': 'troubleshooting', '_1': 'troubleshooting', '_2': 'icon-refresh',
        '_3': 'buttons', '_4': 'error-codes', '_5': 'logs', '_6': 'cli',
    },
}


def on_post_build(config, **kwargs):
    site = Path(config['site_dir']).resolve()
    for route, sections in REDIRECTS.items():
        destination = '../#' + sections['']
        target = (site / 'tools' / 'folderstate' / route / 'index.html').resolve()
        target.relative_to(site)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(f'''<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <title>FolderState 통합 안내로 이동</title>
  <meta name="robots" content="noindex">
  <link rel="canonical" href="{destination}">
  <script>
    const sections = {json.dumps(sections)};
    const section = Object.prototype.hasOwnProperty.call(sections, location.hash.slice(1))
      ? sections[location.hash.slice(1)] : sections[""];
    location.replace("../#" + section);
  </script>
  <meta http-equiv="refresh" content="0; url={destination}">
</head>
<body><p><a href="{destination}">FolderState 설치·사용 안내로 이동합니다.</a></p></body>
</html>
''', encoding='utf-8')
