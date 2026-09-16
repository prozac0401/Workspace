"""Extract user-facing text and compare it with a Git revision.

Uses existing documentation dependencies. Fixed source scope excludes business
folders and evaluation copies. Results go to artifacts/wording, not the site.
"""
import argparse
from collections import Counter
from difflib import SequenceMatcher
from html import escape
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

import markdown
import yaml

ROOT = Path(__file__).resolve().parent.parent


class VisibleText(HTMLParser):
    boundaries = set("h1 h2 h3 h4 h5 h6 p li dt dd th td pre figcaption summary blockquote div section nav figure ul ol dl".split())

    def __init__(self):
        super().__init__()
        self.items, self.parts = [], []
        self.kind, self.skip, self.pre = "본문", 0, False

    def flush(self):
        value = "".join(self.parts).strip()
        if not self.pre:
            value = re.sub(r"\s+", " ", value)
        if value:
            self.items.append((self.kind, value))
        self.parts = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in {"style", "script"}:
            self.skip += 1
        if self.skip:
            return
        if tag in self.boundaries:
            self.flush()
            self.kind = tag
        if tag == "pre":
            self.pre = True
        if tag == "br":
            self.parts.append("\n")
        for name in ("alt", "aria-label", "title"):
            if attrs.get(name):
                self.items.append((name, attrs[name]))

    def handle_endtag(self, tag):
        if tag in {"script", "style"}:
            self.skip -= 1
        elif not self.skip and tag in self.boundaries:
            self.flush()
            if tag == "pre":
                self.pre = False

    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)


def read(path, revision=None):
    if revision:
        return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT).decode("utf-8-sig")
    return (ROOT / path).read_text(encoding="utf-8-sig")


def doc_routes(nav):
    for item in nav:
        for value in item.values():
            if isinstance(value, list):
                yield from doc_routes(value)
            else:
                yield "docs/" + value


def sources(revision=None):
    config = yaml.safe_load(read("mkdocs.yml", revision))
    paths = ["README.md", *doc_routes(config["nav"]), "docs/forms/operation.md", "docs/assets/help.html", "mkdocs.yml", "scripts/build.ps1"]
    command = ["git", "ls-tree", "-r", "--name-only", revision, "src", "installer"] if revision else ["git", "ls-files", "src", "installer"]
    listed = subprocess.check_output(command, cwd=ROOT).decode().splitlines()
    paths += [p for p in listed if Path(p).suffix in {".cs", ".xaml", ".wxs"}]
    return sorted(set(paths))


def csharp_literals(source):
    """Keep interpolated templates whole, including quoted choices inside braces."""
    def string_end(start):
        cursor = start
        while source[cursor] in "$@":
            cursor += 1
        prefix = source[start:cursor]
        if source.startswith('"""', cursor):
            end = source.find('"""', cursor + 3)
            return len(source) if end < 0 else end + 3
        cursor += 1
        while cursor < len(source):
            char = source[cursor]
            if char == '"':
                if "@" in prefix and source.startswith('""', cursor):
                    cursor += 2
                    continue
                return cursor + 1
            if char == "\\" and "@" not in prefix:
                cursor += 2
                continue
            if char == "{" and "$" in prefix:
                if source.startswith("{{", cursor):
                    cursor += 2
                    continue
                cursor += 1
                depth = 1
                while cursor < len(source) and depth:
                    if source[cursor] == '"' or (source[cursor] in "$@" and re.match(r'[$@]+"', source[cursor:])):
                        cursor = string_end(cursor)
                        continue
                    if source[cursor] == "{":
                        depth += 1
                    elif source[cursor] == "}":
                        depth -= 1
                    cursor += 1
                continue
            cursor += 1
        return cursor

    cursor = 0
    while cursor < len(source):
        if source.startswith("//", cursor):
            end = source.find("\n", cursor)
            cursor = len(source) if end < 0 else end + 1
        elif source.startswith("/*", cursor):
            end = source.find("*/", cursor + 2)
            cursor = len(source) if end < 0 else end + 2
        elif source[cursor] == "'":
            cursor += 1
            while cursor < len(source) and source[cursor] != "'":
                cursor += 2 if source[cursor] == "\\" else 1
            cursor += 1
        elif source[cursor] == '"' or (source[cursor] in "$@" and re.match(r'[$@]+"', source[cursor:])):
            end = string_end(cursor)
            yield cursor, source[cursor:end]
            cursor = end
        else:
            cursor += 1


def extract(path, source):
    suffix = Path(path).suffix
    if suffix in {".md", ".html"}:
        metadata = []
        if suffix == ".md":
            front = re.match(r"\A---\s*\n(.*?)\n---\s*\n", source, re.S)
            if front:
                fields = yaml.safe_load(front[1])
                metadata = [(key, fields[key]) for key in ("title", "description") if key in fields]
                source = source[front.end():]
            source = markdown.markdown(source, extensions=["tables", "admonition", "attr_list", "md_in_html", "pymdownx.details", "pymdownx.superfences"])
        parser = VisibleText()
        parser.feed(source)
        parser.flush()
        return metadata + parser.items
    if suffix in {".xaml", ".wxs"}:
        items = []
        for node in ET.fromstring(source).iter():
            for key, value in node.attrib.items():
                if key in {"Text", "Content", "Header", "Title", "ToolTip", "AutomationProperties.Name", "AutomationProperties.HelpText", "Message", "DowngradeErrorMessage", "Description"} or (key == "Value" and node.get("Name") == "MUIVerb"):
                    items.append((key, value))
        return items
    if suffix == ".cs":
        items = []
        # Literal templates: runtime paths, dates and external errors are not materialized.
        for start, value in csharp_literals(source):
            if re.search(r"[가-힣]", value) or (path.endswith("Commands.cs") and start < source.index("public static Command Parse")):
                line = source.count("\n", 0, start) + 1
                if value.startswith('"""'):
                    items.extend((f"문구 L{line + offset}", part.strip()) for offset, part in enumerate(value[3:-3].splitlines()) if part.strip())
                else:
                    items.append((f"문구 L{line}", value))
        return items
    if path == "scripts/build.ps1":
        return [("탐색기 메뉴", match[1]) for match in re.finditer(r"@\('[^']+','([^']+)','(?:set [^']+|reset|repair)'", source)]
    if suffix == ".yml":
        data = yaml.safe_load(source)
        items = [(key, data[key]) for key in ("site_name", "site_description")]

        def labels(nav):
            for entry in nav:
                for key, value in entry.items():
                    items.append(("메뉴", key))
                    if isinstance(value, list):
                        labels(value)
        labels(data["nav"])
        for palette in data["theme"]["palette"]:
            items.append(("화면 전환", palette["toggle"]["name"]))
        return items
    return []


def inventory(revision=None):
    rows = []
    for path in sources(revision):
        for index, (kind, value) in enumerate(extract(path, read(path, revision)), 1):
            units = [value] if kind == "pre" or kind.startswith("문구 L") else re.split(r"(?<=[.!?])\s+(?=[가-힣A-Z‘“\"(])", value)
            for part, unit in enumerate(units, 1):
                rows.append({"id": f"{path}#{index}.{part}", "source": path, "kind": kind, "text": unit})
    return rows


def cell(value):
    return escape(value).replace("|", "&#124;").replace("\n", "<br>")


def write_inventory(output, name, rows):
    text = [f"# {name}", "", "제목·문장·표의 각 칸·버튼·오류 문구를 분리했습니다. 번호는 이 추출본 안의 위치이며 개정 전후의 같은 문장을 뜻하지 않습니다.", "", "실행 중 만들어지는 경로·날짜·외부 오류 내용, 이미지 안의 글자, 원본 명세·과거 기록·별도 Excel 프로젝트는 제외합니다. 코드의 문구는 변수 자리를 남긴 원문입니다.", ""]
    current = None
    for row in rows:
        if row["source"] != current:
            current = row["source"]
            text += ["", f"## {current}", "", "| 번호 | 종류 | 문구 |", "|---|---|---|"]
        text.append(f'| {row["id"].rsplit("#", 1)[1]} | {cell(row["kind"])} | {cell(row["text"])} |')
    output.write_text("\n".join(text) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="HEAD", help="Git revision to compare")
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "rev-parse", "--verify", args.base + "^{commit}"], cwd=ROOT).decode().strip()
    before, after = inventory(revision), inventory()
    output = ROOT / "artifacts" / "wording"
    output.mkdir(parents=True, exist_ok=True)
    write_inventory(output / "before.md", "고치기 전 문구", before)
    write_inventory(output / "after.md", "고친 뒤 문구", after)
    report = ["# 문구 변경 비교", "", f"비교 기준: `{revision}`", "", "[고치기 전 전체 문구](before.md) · [고친 뒤 전체 문구](after.md)", "", "문장 순서나 구성이 달라진 곳은 변경 묶음으로 보여줍니다. 앞뒤 문장을 억지로 일대일 대응시키지 않습니다.", ""]
    paths = sorted({row["source"] for row in before + after})
    changed = 0
    for path in paths:
        old = [r["text"] for r in before if r["source"] == path]
        new = [r["text"] for r in after if r["source"] == path]
        if old == new:
            continue
        changed += 1
        report += [f"## {path}", "", "| 고치기 전 | 고친 뒤 |", "|---|---|"]
        for tag, i, j, k, end in SequenceMatcher(None, old, new, autojunk=False).get_opcodes():
            if tag != "equal":
                report.append(f'| {cell(chr(10).join(old[i:j])) or "(추가)"} | {cell(chr(10).join(new[k:end])) or "(삭제 또는 통합)"} |')
        report.append("")
    (output / "changes.md").write_text("\n".join(report), encoding="utf-8")
    payload = {"base_commit": revision, "before_count": len(before), "after_count": len(after), "changed_sources": changed, "source_counts": dict(Counter(r["source"] for r in after)), "before": before, "after": after}
    (output / "items.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: {len(before)} before / {len(after)} after text units; {changed} changed sources; {output}")


if __name__ == "__main__":
    main()
