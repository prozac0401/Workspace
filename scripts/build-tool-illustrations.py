"""Render chapter diagrams and refresh their marked blocks in Markdown sources.

Run from any directory: python scripts/build-tool-illustrations.py
Definitions live in scripts/illustrations/*.json. Artwork is original SVG;
all sample data is fictional. This script never reads product/business files.
"""
from html import escape
from pathlib import Path
import json
import re
import unicodedata

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'docs/assets/tool-guides'
# Match docs/assets/extra.css: paper, ink and brass from the handbook.
INK, MUTED, BRASS, GOLD = '#2c2622', '#6e6258', '#8a622f', '#b7894e'
PAPER, SOFT, LINE = '#fffdf9', '#f2e9dd', '#ded2c4'
MOBILE_ROW = 144
MOBILE_WIDTH = 320


def units(value):
    return sum(1 if unicodedata.east_asian_width(c) in ('W', 'F') else .57 for c in value)


def wrap(value, limit=15.3):
    words, lines, current = value.split(), [], ''
    for word in words:
        candidate = f'{current} {word}'.strip()
        if current and units(candidate) > limit:
            lines.append(current)
            current = word
        else:
            current = candidate
    if current:
        lines.append(current)
    return lines


def text(x, y, value, size=18, fill=INK, weight=400, anchor='middle'):
    return (f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" '
            f'font-weight="{weight}" text-anchor="{anchor}">{escape(value)}</text>')


def box(x, y, w, h, fill=PAPER, stroke=LINE, radius=8):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>'


def path(d, color=BRASS, width=3, fill='none', dash=''):
    return f'<path d="{d}" fill="{fill}" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"{dash}/>'


def circle(x, y, r, fill=SOFT, stroke=BRASS):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>'


def icon(name, samples=None):
    """Small editorial scenes, in a 144 × 100 coordinate system."""
    art = f'<ellipse cx="72" cy="91" rx="55" ry="5" fill="{LINE}" opacity=".5"/>'
    if name.startswith('folder') or name == 'backup':
        art += path('M19 35V20Q19 15 25 15H53L65 27H119Q125 27 125 33V78Q125 85 118 85H26Q19 85 19 78Z', GOLD, 2, '#ead7b9')
        art += path('M19 37H125L116 85H27Z', GOLD, 2, '#f4e7d2')
        symbol = {'folder-check': 'check', 'folder-wait': 'clock', 'folder-alert': '!', 'folder-empty': 'empty', 'backup': 'copy'}.get(name)
        if symbol == 'check':
            art += circle(108, 72, 20) + path('M98 72L105 79L119 64')
        elif symbol == 'clock':
            art += circle(108, 72, 20, '#f0e9df', '#8a622f') + path('M108 60V73L116 77', '#8a622f')
        elif symbol == '!':
            art += circle(108, 72, 20, '#fbe9e1', '#b56142') + text(108, 81, '!', 26, '#9c4c32', 700)
        elif symbol == 'empty':
            art += circle(105, 72, 17, PAPER, MUTED)
        elif symbol == 'copy':
            art += box(68, 39, 34, 39, '#fffdf9', BRASS, 3) + box(77, 48, 34, 39, PAPER, BRASS, 3)
        else:
            art += path('M41 55H83M41 65H68', GOLD, 3)
    elif name in ('sheet', 'sheet-counts', 'sheet-filter', 'sheet-values'):
        art += box(22, 9, 100, 78, '#fffdf9', BRASS, 4)
        art += '<path d="M23 28H121M49 10V86M89 10V86M23 47H121M23 66H121" fill="none" stroke="#ded2c4" stroke-width="2"/>'
        art += '<rect x="24" y="11" width="96" height="15" rx="2" fill="#ece5d7"/>'
        if name == 'sheet-values':
            for row, value in enumerate(samples or []):
                y = 43+row*19
                art += text(36, y, str(row+1), 11, MUTED)
                if value:
                    art += box(51, y-13, 36, 17, '#ece5d7', '#ece5d7', 2) + text(69, y, value, 13, INK, 700)
        elif name == 'sheet-counts':
            art += path('M49 48H120V65H49Z', GOLD, 2, '#f6e7cd')
            for y, a, b in [(43, 'A', '3'), (62, 'B', '1'), (81, 'C', '2')]:
                art += text(69, y, a, 13) + text(104, y, b, 13)
        elif name == 'sheet-filter':
            art += '<rect x="24" y="48" width="96" height="17" fill="#e4ddd3"/>'
            art += path('M100 53L131 53L120 65V78L111 82V65Z', BRASS, 2, '#ece5d7')
            art += path('M56 37H80M56 75H79', BRASS, 3)
        else:
            art += box(50, 29, 38, 18, '#ece5d7', BRASS, 1) + text(68, 43, 'A1', 12, INK, 700)
            art += path('M56 56H80M56 75H76', MUTED, 2)
    elif name in ('window', 'pc', 'browser', 'install'):
        art += box(14, 10, 116, 71, '#fffdf9', BRASS, 6)
        art += path('M15 25H129', LINE, 2)
        for x in (23, 31, 39):
            art += f'<circle cx="{x}" cy="18" r="2" fill="{GOLD}"/>'
        if name == 'pc':
            art += path('M65 82V91M79 82V91M51 92H93', BRASS, 3) + box(37, 36, 69, 31, SOFT)
        elif name == 'browser':
            art += box(32, 35, 80, 17, SOFT, LINE, 4) + text(72, 48, 'https://', 12, BRASS, 600) + path('M33 63H99M33 71H79', MUTED, 2)
        elif name == 'install':
            art += path('M72 34V56M62 48L72 58L82 48') + path('M43 62V69H101V62')
        else:
            art += box(26, 34, 42, 35, SOFT) + path('M79 38H112M79 48H109M79 58H97', BRASS, 3)
    elif name == 'menu':
        art += box(28, 5, 96, 86, '#fffdf9', BRASS, 6)
        for y in (21, 40, 60, 79):
            if y == 60:
                art += box(34, 49, 84, 19, '#ece5d7', '#ece5d7', 3)
            art += path(f'M43 {y}H94', BRASS if y == 60 else MUTED, 3)
        art += path('M10 60L10 84L18 78L24 90L31 86L24 74L35 72Z', INK, 2, '#fffdf9')
    elif name in ('file', 'records', 'snapshot', 'note'):
        if name == 'snapshot':
            art += box(24, 7, 78, 70, SOFT, LINE, 5)
        art += box(36, 15, 76, 73, '#f7edda' if name == 'note' else '#fffdf9', GOLD if name == 'note' else BRASS, 5)
        for y, end in [(34, 94), (46, 94), (58, 82), (70, 91)]:
            art += path(f'M50 {y}H{end}', GOLD if name == 'note' else MUTED, 2)
        if name == 'snapshot':
            art += circle(109, 74, 17) + path('M109 64V75L117 79')
        elif name == 'records':
            art += box(42, 55, 64, 10, SOFT, SOFT, 2) + path('M50 60H93', BRASS, 3)
        elif name == 'note':
            art += path('M104 88L112 79H104Z', GOLD, 2, '#ead7b9')
    elif name in ('image', 'clipboard'):
        if name == 'clipboard':
            art += box(31, 9, 83, 80, '#fffdf9', BRASS, 7)
            art += box(55, 4, 36, 14, SOFT, BRASS, 4)
            art += box(40, 28, 65, 48, '#f0e9df', LINE, 3)
            art += circle(87, 40, 5, '#ead7b9', GOLD)
            art += path('M43 71L60 49L74 63L83 56L103 73Z', BRASS, 2, '#ece5d7')
        else:
            art += box(18, 15, 110, 70, '#f0e9df', BRASS, 6)
            art += circle(103, 33, 8, '#ead7b9', GOLD)
            art += path('M24 78L54 36L80 66L95 49L122 79Z', BRASS, 2, '#ece5d7')
    elif name == 'bookmark':
        art += box(26, 13, 91, 74, '#fffdf9', LINE, 6)
        art += path('M75 13H98V61L86 52L75 61Z', BRASS, 2, '#ece5d7')
        art += path('M40 40H62M40 52H60M40 69H98', MUTED, 2)
    elif name == 'keyboard':
        art += box(9, 24, 126, 57, '#fffdf9', BRASS, 7)
        for y in (33, 47):
            for x in range(18, 125, 15):
                art += box(x, y, 10, 9, SOFT, LINE, 2)
        art += box(36, 63, 70, 10, '#ece5d7', BRASS, 2)
    elif name == 'terminal':
        art += box(15, 12, 115, 72, INK, INK, 6) + path('M29 30L38 37L29 44', '#e3c799', 3)
        art += path('M50 37H90M29 57H104M29 69H73', '#e3c799', 3)
    elif name in ('shield', 'check'):
        art += path('M72 8L112 24V49Q112 75 72 91Q32 75 32 49V24Z', BRASS, 2, '#ece5d7')
        if name == 'check':
            art += path('M52 48L66 63L93 34', BRASS, 4)
        else:
            art += box(55, 43, 34, 26, '#fffdf9', BRASS, 4) + path('M62 43V33Q72 18 82 33V43')
    elif name in ('restore', 'clock', 'pause', 'trash', 'search', 'settings', 'link'):
        if name == 'search':
            art += circle(62, 42, 29, '#fffdf9') + path('M84 65L111 90', BRASS, 8) + path('M48 36H76M48 46H66', MUTED, 3)
        elif name == 'trash':
            art += path('M42 29L47 86H97L102 29M36 28H108M57 27V16H87V27M61 42V72M83 42V72', MUTED, 3, SOFT)
        elif name == 'link':
            art += '<g transform="rotate(-35 72 50)">' + box(23, 33, 64, 33, '#fffdf9', BRASS, 16) + box(61, 33, 64, 33, '#fffdf9', BRASS, 16) + path('M57 50H90') + '</g>'
        elif name == 'settings':
            for y, x in [(24, 53), (49, 93), (74, 65)]:
                art += path(f'M27 {y}H119', LINE, 4) + circle(x, y, 9, '#fffdf9')
        else:
            art += circle(72, 49, 38, '#fffdf9')
            if name == 'clock':
                art += path('M72 23V50L90 61')
            elif name == 'pause':
                art += path('M61 33V65M83 33V65', GOLD, 8)
            else:
                art += path('M94 51A23 23 0 1 1 65 28M65 28L55 27M65 28L60 39')
    else:
        raise ValueError(f'Unknown icon: {name}')
    return art


def render(entry, mobile=False):
    panels = entry['panels']
    width, height = (MOBILE_WIDTH, MOBILE_ROW * len(panels)) if mobile else (720, 244)
    title = re.sub(r'\s*\{#.*?\}', '', entry['heading'])
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
           f'<title id="title">{escape(title)}</title><desc id="desc">{escape(entry["caption"])}</desc>',
           '<g font-family="Noto Sans CJK KR, Noto Sans KR, Malgun Gothic, Segoe UI, sans-serif">',
           f'<rect width="{width}" height="{height}" rx="4" fill="{PAPER}"/>']
    step = width / len(panels)
    for i, panel in enumerate(panels):
        title = panel['title']
        lines = panel['lines']
        if mobile:
            base = i * MOBILE_ROW
            if entry['mode'] == 'flow':
                svg.append(text(27, base+18, f'{i+1:02d}', 10, BRASS, 700))
            if i:
                svg.append(path(f'M18 {base}H302', LINE, 1))
            svg.append(f'<g transform="translate(9 {base+19}) scale(.72)">{icon(panel["icon"], panel.get("samples"))}</g>')
            svg.append(text(120, base+35, title, min(16, round(182 / units(title), 1)), weight=700, anchor='start'))
            wrapped = [line for original in lines for line in wrap(original, 12.8)]
            if len(wrapped) > 4:
                raise ValueError(f'Too much mobile text: {entry["id"]}')
            for j, line in enumerate(wrapped):
                svg.append(text(120, base+60+j*20, line, 14, MUTED, anchor='start'))
            if panel.get('badge'):
                svg.append(text(62, base+117, panel['badge'], min(12, round(104 / units(panel['badge']), 1)), BRASS, 700))
            if entry['mode'] == 'flow' and i < len(panels)-1:
                svg.append(path(f'M300 {base+123}V{base+137}M295 {base+132}L300 {base+137}L305 {base+132}', BRASS, 2))
        else:
            center = step*(i+.5)
            if entry['mode'] == 'flow':
                svg.append(text(center, 18, f'{i+1:02d}', 11, BRASS, 700))
            else:
                svg.append(path(f'M{center-12:g} 16H{center+12:g}', GOLD, 2))
            svg.append(f'<g transform="translate({center-72:g} 25)">{icon(panel["icon"], panel.get("samples"))}</g>')
            svg.append(text(center, 155, title, min(18, round((step-24) / units(title), 1)), weight=700))
            for j, line in enumerate(lines):
                svg.append(text(center, 182+j*23, line, min(15, round((step-20) / units(line), 1)), MUTED))
            if panel.get('badge'):
                badge_width = max(70, units(panel['badge'])*12+20)
                svg.append(box(center-badge_width/2, 109, badge_width, 23, SOFT, SOFT, 3))
                svg.append(text(center, 125, panel['badge'], 12, BRASS, 700))
            if i < len(panels)-1:
                x = step*(i+1)
                if entry['mode'] == 'flow':
                    svg.append(path(f'M{x-13:g} 71H{x+13:g}M{x+6:g} 64L{x+13:g} 71L{x+6:g} 78', BRASS, 2))
                else:
                    svg.append(path(f'M{x:g} 29V212', LINE, 1))
    svg.append('</g></svg>')
    return '\n'.join(svg)+'\n'


def figure(entry):
    name = entry['id']
    joiner = ' → ' if entry['mode'] == 'flow' else ' / '
    alt = joiner.join(p['title'] + (f" ({p['badge']})" if p.get('badge') else '') + ': ' + ' '.join(p['lines']) for p in entry['panels'])
    # Raw HTML URLs are not rewritten by MkDocs. Non-index pages gain a folder.
    prefix = '../../' if Path(entry['page']).name == 'index.md' else '../../../'
    return f'''<!-- tool-figure:{name}:start -->
<figure class="tool-figure">
  <picture>
    <source media="(max-width: 760px)" srcset="{prefix}assets/tool-guides/{name}-mobile.svg" width="{MOBILE_WIDTH}" height="{MOBILE_ROW*len(entry['panels'])}">
    <img src="{prefix}assets/tool-guides/{name}.svg" width="720" height="244" alt="{escape(alt, quote=True)}" loading="lazy" decoding="async">
  </picture>
  <figcaption>{escape(entry['caption'])}</figcaption>
</figure>
<!-- tool-figure:{name}:end -->'''


def main():
    entries = []
    for source in sorted((ROOT / 'scripts/illustrations').glob('*.json')):
        entries.extend(json.loads(source.read_text(encoding='utf-8')))
    if len({e['id'] for e in entries}) != len(entries):
        raise ValueError('Figure IDs must be unique')
    OUT.mkdir(parents=True, exist_ok=True)
    for entry in entries:
        if len(entry['panels']) not in (2, 3) or entry['mode'] not in ('flow', 'compare'):
            raise ValueError(entry['id'])
        for suffix, mobile in [('', False), ('-mobile', True)]:
            (OUT / f"{entry['id']}{suffix}.svg").write_text(render(entry, mobile), encoding='utf-8', newline='\n')
        source = ROOT / 'docs' / entry['page']
        content = source.read_text(encoding='utf-8')
        block = figure(entry)
        pattern = rf"<!-- tool-figure:{entry['id']}:start -->.*?<!-- tool-figure:{entry['id']}:end -->"
        if re.search(pattern, content, re.S):
            content = re.sub(pattern, lambda _: block, content, flags=re.S)
        else:
            heading = re.search(r'^#{2,3} '+re.escape(entry['heading'])+r'\s*$', content, re.M)
            if not heading:
                raise ValueError(f"Missing heading: {entry['page']} / {entry['heading']}")
            content = content[:heading.end()].rstrip()+'\n\n'+block+'\n\n'+content[heading.end():].lstrip('\n')
        source.write_text(content, encoding='utf-8', newline='\n')
    print(f'Rendered {len(entries)} chapter diagrams ({len(entries)*2} SVGs) and refreshed Markdown.')


if __name__ == '__main__':
    main()
