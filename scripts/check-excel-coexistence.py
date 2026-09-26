"""Read-only evidence checks for the sequential synthetic Excel coexistence test."""
import argparse
import hashlib
import json
import ntpath
import re
import stat
from pathlib import Path


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def norm(path):
    return ntpath.normcase(ntpath.normpath(str(path)))


def verify(root, source):
    boundary = (Path(__file__).resolve().parents[1] / "artifacts").resolve()
    root, source = root.resolve(), source.resolve()
    if not root.is_relative_to(boundary) or not source.is_relative_to(boundary):
        raise ValueError("Only repository artifact fixtures are allowed")
    checks = []

    def check(name, ok):
        checks.append({"name": name, "passed": bool(ok)})
        if not ok:
            raise AssertionError(name)

    result = {"status": "failed", "checks": checks}
    try:
        check("owned installations all removed", read(root / "owned.json") == {"Selection": False, "Paste": False, "FileList": False})
        baseline = read(root / "baseline.json")
        for action in ("ResumeFileList", "RemoveSelection", "RemovePaste", "RemoveFileList", "Verify"):
            check(action + " passed", read(root / (action + "-result.json"))["status"] == "passed")
            check(action + " unrelated state preserved", read(root / (action + "-safety.json")) == baseline)
        probes = ["all-Probe-" + phase for phase in ("initial", "before", "pasted", "undone", "export", "roster")]
        probes += [stage + "-Probe-before" for stage in ("noexport", "fileonly", "none")]
        probe_checks = 0
        for name in probes:
            report = read(root / (name + ".json"))
            check(name + " exited normally", report["exitCode"] == 0)
            observed = json.loads(report["output"])
            check(name + " passed", observed["status"] == "passed")
            probe_checks += len(observed["checks"])
        for stage in ("noexport", "fileonly", "none"):
            tree = (root / (stage + "-menu.txt")).read_text(encoding="utf-8")
            for label, expected in (("명단 비교", True), ("파일목록", stage != "none"), ("보이는 칸에 붙여넣기", stage == "noexport"), ("마지막 붙여넣기 되돌리기", stage == "noexport"), ("선택범위 내보내기", False)):
                ids = set(re.findall(r"^\s*(\d+) 메뉴 항목 " + re.escape(label) + r"\s*$", tree, re.MULTILINE))
                check(stage + " exact menu count: " + label, len(ids) == int(expected))
        check("coexistence workbook disk bytes preserved", digest(root / "coexist.xlsx") == (root / "fixture-sha256.txt").read_text(encoding="utf-8").strip().upper())
        check("source fixture ownership marker exists", (source / "owned-install.json").is_file())
        manifest = read(source / "source-manifest.json")
        entries = {norm(item["path"]): item for item in manifest}
        check("source fixture has ten files and three folders", len(entries) == 13 and sum(not x["directory"] for x in manifest) == 10)
        for item in manifest:
            check("manifest stays in synthetic input: " + item["relative"], Path(item["path"]).resolve().is_relative_to(source / "input"))
        check("source inventory preserved", {norm(p) for p in (source / "input").rglob("*")} == set(entries))
        for item in manifest:
            path = Path(item["path"])
            info = path.stat()
            attributes = sum(getattr(stat, "FILE_ATTRIBUTE_" + flag.strip().upper()) for flag in item["attributes"].split(","))
            check("source attributes preserved: " + item["relative"], info.st_file_attributes == attributes)
            if not item["directory"]:
                check("source file time preserved: " + item["relative"], info.st_mtime_ns // 100 + 621355968000000000 == int(item["modifiedUtcTicks"]))
                check("source bytes preserved: " + item["relative"], digest(path) == item["sha256"].upper())
        for item in read(source / "generation.json"):
            path = Path(item["output"]).resolve()
            check("source workbook stays in fixture: " + item["case"], path.is_relative_to(source / "output"))
            check("source workbook bytes preserved: " + item["case"], digest(path) == item["sha256"].upper())
        folders = list((root / "copied").iterdir())
        check("one collected output folder", len(folders) == 1 and folders[0].is_dir())
        copied = folders[0]
        expected = {}
        for item in manifest:
            if not item["directory"]:
                name = "중복 이름 (2).txt" if item["relative"] == "A 폴더\\중복 이름.txt" else ntpath.basename(item["relative"])
                expected[name] = item
        check("only ten expected copied files", {p.name for p in copied.iterdir()} == set(expected))
        for name, item in expected.items():
            check("copy bytes preserved: " + name, digest(copied / name) == item["sha256"].upper())
        check("exactly 195 copied bytes", sum(p.stat().st_size for p in copied.iterdir()) == 195)
        report = read(root / "copy-report.json")
        check("copy report belongs to this test", norm(report["outputDirectory"]) == norm(copied) and report["cancelled"] is False)
        outcomes = report["outcomes"]
        check("report accounts for thirteen source rows", len(outcomes) == 13 and {norm(o["SourcePath"]) for o in outcomes} == set(entries))
        check("ten copied and three excluded without failures", sum(o["Status"] == "Copied" for o in outcomes) == 10 and sum(o["Status"] == "Excluded" and o["Code"] == "NotFile" for o in outcomes) == 3)
        for outcome in outcomes:
            item = entries[norm(outcome["SourcePath"])]
            if item["directory"]:
                check("folder excluded: " + item["relative"], outcome["DestinationPath"] is None)
            else:
                name = next(name for name, entry in expected.items() if entry is item)
                check("exact copy mapping: " + item["relative"], norm(outcome["DestinationPath"]) == norm(copied / name))
        result.update(status="passed", probeChecks=probe_checks)
    except Exception as error:
        result["error"] = str(error)
        raise
    finally:
        (root / "evidence-checks.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"PASS {len(checks)} evidence checks; {probe_checks} recorded read-only Excel checks")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence", type=Path)
    parser.add_argument("filelist_fixture", type=Path)
    args = parser.parse_args()
    verify(args.evidence, args.filelist_fixture)
