"""Fast R11 pre-release checks. Long Windows lifecycle/supervisor runs are deferred.

This runner never starts Excel or installs the add-in. Exact-file Excel checks
and payload verification are separate required steps recorded in the release.
"""
import argparse
import json
from pathlib import Path
import time
import unittest

MODULES = (
    "test_reference", "test_usability", "test_r11_settings",
    "test_candidate_source_audit", "test_release_gate", "test_rc10_publication", "test_r11_publication",
    "test_onefile_packaging",
    "test_local_candidate_package", "test_release_document_links",
)
DEFERRED = {
    "test_bounded_runner": "unchanged supervisor, intentional waiting/timeout scenarios",
    "test_candidate_build_guards": "unchanged developer helper, repeated subprocess preflights",
    "test_launchers": "unchanged launchers, repeated Windows process lifecycle scenarios",
    "test_uninstall_self_removal": "unchanged removal engine, separate post-release lifecycle validation",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("choose a new evidence output file")
    started = time.perf_counter()
    suite = unittest.defaultTestLoader.loadTestsFromNames(MODULES)
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    summary = {
        "profile": "r11-essential", "status": "PASS" if result.wasSuccessful() else "FAIL",
        "testsRun": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
        "seconds": round(time.perf_counter() - started, 3), "modules": MODULES,
        "deferred": DEFERRED, "excelExecution": "separate required check",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    raise SystemExit(0 if result.wasSuccessful() else 1)


if __name__ == "__main__":
    main()
