"""Export locale-independent ASCII VBA imports from reviewable UTF-8 sources.

Only Unicode string literals are replaced with SLC_U("UTF16 hex code units").
Unicode comments are transliterated by ASCII replacement. No executable logic
is changed, and the exporter rejects non-ASCII syntax outside strings/comments.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LITERAL = re.compile(r'"(?:[^"\r\n]|"")*"')


def export_line(line: str) -> str:
    i, pieces = 0, []
    while i < len(line):
        ch = line[i]
        if ch == "'":
            pieces.append(line[i:].encode('ascii', 'replace').decode('ascii'))
            break
        if ch == '"':
            match = LITERAL.match(line, i)
            if match is None:
                raise ValueError(f'Unterminated VBA string: {line}')
            literal = match.group(0)
            if literal.isascii():
                pieces.append(literal)
            else:
                value = literal[1:-1].replace('""', '"')
                raw = value.encode('utf-16-le')
                units = [int.from_bytes(raw[n:n+2], 'little') for n in range(0, len(raw), 2)]
                pieces.append('SLC_U("' + ' '.join(f'{u:04X}' for u in units) + '")')
            i = match.end()
        else:
            if not ch.isascii():
                raise ValueError(f'Non-ASCII VBA identifier: {line}')
            pieces.append(ch)
            i += 1
    result = ''.join(pieces)
    if len(result) > 1023:
        raise ValueError(f'VBA physical line exceeds 1023 characters ({len(result)})')
    return result


def main() -> None:
    for source in sorted((ROOT / 'src').glob('*_utf8.*')):
        target = source.with_name(source.name.replace('_utf8', ''))
        lines = [export_line(line) for line in source.read_text(encoding='utf-8').splitlines()]
        target.write_bytes(('\r\n'.join(lines) + '\r\n').encode('ascii'))
        print(f'{target.name}: {len(lines)} lines; ASCII; max line {max(map(len,lines))}')


if __name__ == '__main__':
    main()
