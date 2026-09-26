"""Read-only oracle for test-filelist-synthetic.ps1's fixed synthetic fixture."""
import argparse
import hashlib
import json
import ntpath
import posixpath
import stat
import uuid
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def cell_text(cell):
    if cell is None:
        return ""
    return "".join(cell.itertext())


def normalized(path):
    return ntpath.normcase(ntpath.normpath(str(path)))


def verify(root, verify_copy=False):
    checks = []

    def check(name, passed):
        checks.append({"name": name, "passed": bool(passed)})
        if not passed:
            raise AssertionError(name)

    root = root.resolve()
    allowed = Path(__file__).resolve().parents[1] / "artifacts"
    check("evidence directory is inside repository artifacts", root.is_relative_to(allowed.resolve()))
    check("owned test marker exists", (root / "owned-install.json").is_file())
    manifest = json.loads((root / "source-manifest.json").read_text(encoding="utf-8-sig"))
    entries = {normalized(item["path"]): item for item in manifest}
    all_paths = set(entries)
    direct = {path for path, item in entries.items() if "\\" not in item["relative"]}
    selected = {normalized(root / "input" / name) for name in ("보고서 한글.txt", "=1+1.txt")}
    original = normalized(root / "input" / "같은내용 원본.txt")
    duplicate = normalized(root / "input" / "A 폴더" / "이름 다른 복제.bin")
    expected = {"direct": direct, "recursive": all_paths, "selected": selected, "empty": set(),
                "duplicates": {original, duplicate}, "matches": {duplicate}}
    check("fixture has ten files and three folders", len(entries) == 13 and sum(not x["directory"] for x in manifest) == 10)
    try:
        for case, expected_paths in expected.items():
            with zipfile.ZipFile(root / "output" / (case + ".xlsx")) as package:
                check(case + " is macro-free", not any("vbaproject" in name.lower() for name in package.namelist()))
                workbook = ET.fromstring(package.read("xl/workbook.xml"))
                sheets = [x.attrib["name"] for x in workbook.findall("m:sheets/m:sheet", NS)]
                expected_sheets = ["Files"] if case in ("direct", "recursive", "selected", "empty") else ["Duplicates" if case == "duplicates" else "Matches", "Summary", "Errors", "Skipped"]
                check(case + " worksheet names", sheets == expected_sheets)
                sheet = ET.fromstring(package.read("xl/worksheets/sheet1.xml"))
                rows = [{"".join(filter(str.isalpha, c.attrib["r"])): c for c in r} for r in sheet.findall("m:sheetData/m:row", NS)]
                header_index = next(i for i, row in enumerate(rows) if "__FLT_SourceRecord" in [cell_text(c) for c in row.values()])
                headers = {cell_text(c): col for col, c in rows[header_index].items()}
                data = rows[header_index + 1:]
                paths = [normalized(cell_text(row.get(headers["전체경로"]))) for row in data]
                check(case + " exact expected rows with no duplicates", len(paths) == len(expected_paths) and set(paths) == expected_paths)
                check(case + " no formula cells", not sheet.findall(".//m:f", NS))
                pane = sheet.find("m:sheetViews/m:sheetView/m:pane", NS)
                check(case + " frozen header", pane is not None and pane.attrib.get("state") == "frozen")
                ids = []
                for path, row in zip(paths, data):
                    expected_entry = entries[path]
                    item_id = cell_text(row[headers["__FLT_ItemId"]])
                    uuid.UUID(item_id)
                    ids.append(item_id)
                    source = json.loads(cell_text(row[headers["__FLT_SourceRecord"]]))
                    check(case + " source path and identity: " + expected_entry["relative"], normalized(source["absolutePath"]) == path and source["itemId"] == item_id)
                    check(case + " source kind: " + expected_entry["relative"], source["kind"] == ("directory" if expected_entry["directory"] else "file"))
                    if not expected_entry["directory"]:
                        size = row[headers["크기"]]
                        date = row[headers["수정일"]]
                        check(case + " numeric size: " + expected_entry["relative"], size.attrib.get("t", "n") == "n" and int(cell_text(size)) == expected_entry["bytes"])
                        check(case + " numeric date: " + expected_entry["relative"], date.attrib.get("t", "n") == "n" and float(cell_text(date)) > 0)
                        check(case + " exact metadata: " + expected_entry["relative"], source["sizeBytes"] == str(expected_entry["bytes"]) and source["modifiedUtcTicks"] == expected_entry["modifiedUtcTicks"])
                check(case + " unique row IDs", len(ids) == len(set(ids)))
                relationships = ET.fromstring(package.read("xl/worksheets/_rels/sheet1.xml.rels"))
                targets = {rel.attrib["Id"]: rel.attrib["Target"] for rel in relationships}
                tables = [ET.fromstring(package.read(posixpath.normpath(posixpath.join("xl/worksheets", targets[part.attrib["{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"]])))) for part in sheet.findall("m:tableParts/m:tablePart", NS)]
                check(case + " table and filter", len(tables) == 1 and tables[0].find("m:autoFilter", NS) is not None)
                if expected_paths:
                    check(case + " row hyperlinks", len(sheet.findall("m:hyperlinks/m:hyperlink", NS)) == len(expected_paths))
                if case in ("direct", "recursive", "selected"):
                    formula_row = next(row for row in data if cell_text(row.get(headers["이름"])) == "=1+1.txt")
                    check(case + " formula-shaped name is literal text", formula_row[headers["이름"]].attrib.get("t") == "inlineStr")
                if case == "duplicates":
                    check("duplicate group has only the identical-content pair", all(cell_text(row[headers["그룹 파일수"]]) == "2" and cell_text(row[headers["SHA-256"]]).upper() == entries[original]["sha256"].upper() for row in data))
                if case == "matches":
                    check("matches identifies the original and excludes it from results", normalized(cell_text(rows[0].get("B"))) == original and original not in paths)
        actual = {normalized(path) for path in (root / "input").rglob("*")}
        check("source file and folder inventory unchanged", actual == all_paths)
        for entry in manifest:
            file_stat = Path(entry["path"]).stat()
            expected_attributes = sum(getattr(stat, "FILE_ATTRIBUTE_" + flag.strip().upper()) for flag in entry["attributes"].split(","))
            check("source attributes preserved: " + entry["relative"], file_stat.st_file_attributes == expected_attributes)
            if not entry["directory"]:
                check("source file modified time preserved: " + entry["relative"], file_stat.st_mtime_ns // 100 + 621355968000000000 == int(entry["modifiedUtcTicks"]))
                check("source hash preserved: " + entry["relative"], hashlib.sha256(Path(entry["path"]).read_bytes()).hexdigest().upper() == entry["sha256"].upper())
        for output in json.loads((root / "generation.json").read_text(encoding="utf-8-sig")):
            check("generated workbook bytes preserved: " + output["case"], hashlib.sha256(Path(output["output"]).read_bytes()).hexdigest().upper() == output["sha256"].upper())
        if verify_copy:
            copied_roots = list((root / "copied").iterdir())
            check("exactly one collected output folder", len(copied_roots) == 1 and copied_roots[0].is_dir())
            copied_root = copied_roots[0]
            destinations = {}
            for entry in manifest:
                if entry["directory"]:
                    continue
                name = ntpath.basename(entry["relative"])
                if entry["relative"] == "A 폴더\\중복 이름.txt":
                    name = "중복 이름 (2).txt"
                destinations[name] = entry
            check("destination contains only the ten expected files", {p.name for p in copied_root.iterdir()} == set(destinations))
            for name, entry in destinations.items():
                check("copied file bytes preserved: " + name, hashlib.sha256((copied_root / name).read_bytes()).hexdigest().upper() == entry["sha256"].upper())
            check("copied size is exactly 195 bytes", sum(p.stat().st_size for p in copied_root.iterdir()) == 195)
            report = json.loads((root / "copy-report.json").read_text(encoding="utf-8-sig"))
            check("task report points only to this collected folder", normalized(report["outputDirectory"]) == normalized(copied_root) and report["cancelled"] is False)
            outcomes = report["outcomes"]
            check("report accounts for all thirteen rows", len(outcomes) == 13 and {normalized(o["SourcePath"]) for o in outcomes} == all_paths)
            check("report records ten copied and three excluded, no failures", sum(o["Status"] == "Copied" for o in outcomes) == 10 and sum(o["Status"] == "Excluded" and o["Code"] == "NotFile" for o in outcomes) == 3)
            for outcome in outcomes:
                source = entries[normalized(outcome["SourcePath"])]
                if source["directory"]:
                    check("folder excluded: " + source["relative"], outcome["Status"] == "Excluded" and outcome["DestinationPath"] is None)
                else:
                    expected_name = next(name for name, entry in destinations.items() if entry is source)
                    check("report destination mapping: " + source["relative"], normalized(outcome["DestinationPath"]) == normalized(copied_root / expected_name))
        result = {"status": "passed", "checks": checks, "scope": "Synthetic input/output only; actual UI and installation results are recorded separately.", "copyVerified": verify_copy}
    except Exception as error:
        result = {"status": "failed", "error": str(error), "checks": checks}
        raise
    finally:
        (root / "workbook-checks.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"PASS {len(checks)} synthetic workbook/source checks")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--verify-copy", action="store_true", help="Verify the completed UI copy and its copied task report.")
    args = parser.parse_args()
    verify(args.evidence, args.verify_copy)
