"""Read-only audit of serialized candidate VBA and Office RibbonX wiring.

No Excel, COM, VBA, security settings or installation is invoked. Raw extracted
source and hashes are written only into a fresh repository artifacts directory.
This compares serialized source, not compiled p-code or runtime behavior.
"""
import argparse
import hashlib
import json
import posixpath
import re
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

REPO = Path(__file__).resolve().parents[3]
SOURCE_FILES = {
    "CSLCList": "CSLCList.cls",
    "CSLCAppEvents": "CSLCAppEvents.cls",
    "modSLCNormalize": "modSLCNormalize.bas",
    "modSLCMain": "modSLCMain.bas",
    "modSLCReport": "modSLCReport.bas",
    "ThisWorkbook": "ThisWorkbook_events.txt",
}
UI_NS = "http://schemas.microsoft.com/office/2009/07/customui"
REL_NS = "http://schemas.openxmlformats.org/package/2006/relationships"
CONTENT_NS = "http://schemas.openxmlformats.org/package/2006/content-types"
SHEET_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
DOC_REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
UI_REL_TYPE = "http://schemas.microsoft.com/office/2007/relationships/ui/extensibility"
WORKBOOK_BASE = "0{00020819-0000-0000-C000-000000000046}"
SHEET_BASE = "0{00020820-0000-0000-C000-000000000046}"
CLASS_BASE = "0{FCFB3D2A-A0FA-1068-A738-08002B3371B5}"
MENUS = {
    "ContextMenuCell": "Cell", "ContextMenuRow": "Row", "ContextMenuColumn": "Column",
    "ContextMenuListRange": "Table", "ContextMenuCellLayout": "CellLayout",
    "ContextMenuRowLayout": "RowLayout", "ContextMenuColumnLayout": "ColumnLayout",
    "ContextMenuListRangeLayout": "TableLayout",
}
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUMBER = re.compile(r"(?:&[Hh][0-9A-Fa-f]+|&[Oo][0-7]+|(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[Ee][+-]?[0-9]+)?)[%&^!#@]?")
ATTRIBUTE = re.compile(r"^Attribute VB_", re.IGNORECASE)
WITH_EVENTS = re.compile(r"^\s*(?:Public|Private|Friend|Dim)\s+WithEvents\s+([A-Za-z_][A-Za-z0-9_]*)\s+As\s+Excel\.Application\s*$", re.IGNORECASE)
DEFAULT_VAR_HELP = re.compile(r"^Attribute ([A-Za-z_][A-Za-z0-9_]*)\.VB_VarHelpID = -1$", re.IGNORECASE)


class AuditError(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def normalized_lines(text):
    return text.replace("\r\n", "\n").replace("\r", "\n").split("\n")


def canonicalize_line(line):
    """Fold only ASCII identifiers; retain quoted text, comments and numbers."""
    pieces = []
    offset = 0
    while offset < len(line):
        char = line[offset]
        if char == "'":
            pieces.append(line[offset:])
            break
        if char == '"':
            end = offset + 1
            while end < len(line):
                if line[end] == '"':
                    if end + 1 < len(line) and line[end + 1] == '"':
                        end += 2
                        continue
                    end += 1
                    break
                end += 1
            else:
                raise AuditError("Unterminated VBA string literal")
            pieces.append(line[offset:end])
            offset = end
            continue
        number = NUMBER.match(line, offset)
        if number:
            pieces.append(number.group())
            offset = number.end()
            continue
        identifier = IDENTIFIER.match(line, offset)
        if identifier:
            token = identifier.group()
            # REM is a comment only at a statement boundary, not object.Rem.
            prefix = line[:offset].rstrip()
            if (token.lower() == "rem" and (not prefix or prefix.endswith(":"))
                    and (identifier.end() == len(line) or line[identifier.end()].isspace())):
                pieces.append(line[offset:])
                break
            pieces.append(token.lower())
            offset = identifier.end()
            continue
        pieces.append(char)
        offset += 1
    return "".join(pieces)


def canonicalize_vba(text, *, serialized=False):
    """Normalize builder boundaries and explicitly identified export metadata."""
    lines = normalized_lines(text)
    first = next((i for i, line in enumerate(lines) if line.strip() == "Option Explicit"), None)
    if first is None:
        raise AuditError("VBA source is missing its expected Option Explicit boundary")
    # Unlike blindly dropping a prefix, do not hide a procedure before Option.
    for line in lines[:first]:
        stripped = line.strip()
        if (not stripped or stripped.startswith("'") or ATTRIBUTE.match(line)
                or stripped in {"VERSION 1.0 CLASS", "BEGIN", "END"}
                or re.fullmatch(r"MultiUse\s*=\s*-1(?:\s*'.*)?", stripped)):
            continue
        raise AuditError("Unexpected code before Option Explicit")
    canonical = []
    for index, line in enumerate(lines[first:], first):
        if ATTRIBUTE.match(line):
            continue
        # Excel adds this hidden default member-help attribute on export, but
        # CodeModule.Lines and the source snapshot do not expose it. Ignore only
        # the default value immediately after its own Excel WithEvents field;
        # other member attributes/values/locations remain comparison-significant.
        help_attribute = DEFAULT_VAR_HELP.fullmatch(line.rstrip()) if serialized else None
        declaration = WITH_EVENTS.fullmatch(lines[index - 1]) if index > first else None
        if (help_attribute and declaration
                and help_attribute[1].lower() == declaration[1].lower()):
            continue
        canonical.append(canonicalize_line(line.rstrip()))
    return "\n".join(canonical).rstrip("\n")


def attribute_value(code, name, required=False):
    found = re.findall(r'^Attribute ' + re.escape(name) + r'\s*=\s*"((?:[^"\r\n]|"")*)"\s*$',
                       code.replace("\r\n", "\n"), re.MULTILINE | re.IGNORECASE)
    if len(found) > 1 or (required and len(found) != 1):
        raise AuditError("Expected one serialized " + name + " attribute")
    return found[0].replace('""', '"') if found else None


def empty_sheet_module(code):
    for line in normalized_lines(code):
        stripped = line.strip()
        if (not stripped or ATTRIBUTE.match(line) or stripped == "Option Explicit"
                or stripped.startswith("'") or re.match(r"(?i)^Rem(?:\s|$)", stripped)):
            continue
        return False
    return True


def compare_modules(modules, expected_sources, workbook_name, sheet_names):
    records, errors, seen_names, found_components = [], [], set(), set()
    expected_by_lower = {name.lower(): name for name in SOURCE_FILES if name != "ThisWorkbook"}
    for module in modules:
        record = {"reportedFileName": module["filename"], "stream": module["stream"], "status": "FAIL"}
        try:
            code = module["code"]
            name = attribute_value(code, "VB_Name", required=True)
            base = attribute_value(code, "VB_Base")
            record.update(name=name, base=base, extractedSourceSha256=digest(code.encode("utf-8")))
            if name.lower() in seen_names:
                raise AuditError("Duplicate serialized module name: " + name)
            seen_names.add(name.lower())
            if name == workbook_name:
                component = "ThisWorkbook"
                if base != WORKBOOK_BASE:
                    raise AuditError("Workbook event source is not in the workbook document module")
            elif name.lower() in expected_by_lower:
                component = expected_by_lower[name.lower()]
                expected_base = CLASS_BASE if component in {"CSLCList", "CSLCAppEvents"} else None
                if base != expected_base:
                    raise AuditError("Unexpected module type for " + component)
            elif name in sheet_names and base == SHEET_BASE and empty_sheet_module(code):
                record.update(status="PASS", kind="empty worksheet module")
                records.append(record)
                continue
            else:
                raise AuditError("Unexpected or executable worksheet module: " + name)
            found_components.add(component)
            record["component"] = component
            wanted = canonicalize_vba(expected_sources[component])
            actual = canonicalize_vba(code, serialized=True)
            record.update(sourceNormalizedSha256=digest(wanted.encode("utf-8")),
                          serializedNormalizedSha256=digest(actual.encode("utf-8")))
            if wanted != actual:
                raise AuditError("Serialized VBA source mismatch: " + component)
            record["status"] = "PASS"
        except (AuditError, KeyError) as error:
            record["error"] = str(error)
            errors.append(str(error))
        records.append(record)
    missing = sorted(set(SOURCE_FILES) - found_components)
    if missing:
        errors.append("Missing required modules: " + ", ".join(missing))
    return {"status": "FAIL" if errors else "PASS", "modules": records, "errors": errors}


def inspect_package(xlam, ribbon_source):
    with zipfile.ZipFile(xlam) as package:
        names = package.namelist()
        if len(names) != len(set(names)):
            raise AuditError("Duplicate XLAM package entries")
        if package.testzip() is not None:
            raise AuditError("XLAM ZIP integrity failed")
        ribbon = package.read("customUI/customUI14.xml")
        if ribbon.replace(b"\r\n", b"\n") != ribbon_source.replace(b"\r\n", b"\n"):
            raise AuditError("Packaged RibbonX differs from the source snapshot")
        root = ET.fromstring(ribbon)
        menus = root.findall("{" + UI_NS + "}contextMenus/{" + UI_NS + "}contextMenu")
        if (root.tag != "{" + UI_NS + "}customUI" or root.attrib != {"onLoad": "SLC_RibbonLoad"}
                or len(root) != 1 or root[0].tag != "{" + UI_NS + "}contextMenus"
                or root[0].attrib or len(root[0]) != 8 or len(menus) != 8):
            raise AuditError("Incomplete RibbonX registration")
        actual, ids = {}, set()
        for menu in menus:
            children = list(menu)
            if len(children) != 1 or children[0].tag != "{" + UI_NS + "}dynamicMenu":
                raise AuditError("Each context menu must contain exactly one dynamic menu")
            dynamic = children[0]
            actual[menu.get("idMso")] = dynamic.get("tag")
            ids.add(dynamic.get("id"))
            tag = MENUS.get(menu.get("idMso"))
            expected_attributes = {"id": "slc68" + (tag or "") + "Menu", "tag": tag,
                                   "label": "명단 비교", "getContent": "SLC_GetContextMenu",
                                   "invalidateContentOnDrop": "true"}
            if (menu.attrib != {"idMso": menu.get("idMso")} or len(dynamic)
                    or dynamic.attrib != expected_attributes):
                raise AuditError("Context menu callback or refresh contract differs")
        if actual != MENUS or len(ids) != 8 or None in ids or "" in ids:
            raise AuditError("Context menu identifiers differ or are duplicated")
        rels = ET.fromstring(package.read("_rels/.rels"))
        ui_rels = [r for r in rels.findall("{" + REL_NS + "}Relationship") if r.get("Type") == UI_REL_TYPE]
        if len(ui_rels) != 1 or ui_rels[0].get("Target") != "customUI/customUI14.xml" or ui_rels[0].get("TargetMode", "Internal") != "Internal":
            raise AuditError("Missing, duplicate or external RibbonX relationship")
        types = ET.fromstring(package.read("[Content_Types].xml"))
        ui_types = [t for t in types.findall("{" + CONTENT_NS + "}Override") if t.get("PartName") == "/customUI/customUI14.xml"]
        if len(ui_types) != 1 or ui_types[0].get("ContentType") != "application/xml":
            raise AuditError("Missing or duplicate RibbonX content type override")
        workbook = ET.fromstring(package.read("xl/workbook.xml"))
        props = workbook.findall("{" + SHEET_NS + "}workbookPr")
        if len(props) != 1 or not props[0].get("codeName"):
            raise AuditError("Workbook document codeName is missing or ambiguous")
        workbook_name = props[0].get("codeName")
        workbook_rels = ET.fromstring(package.read("xl/_rels/workbook.xml.rels"))
        rel_by_id = {}
        for relation in workbook_rels.findall("{" + REL_NS + "}Relationship"):
            if relation.get("Id") in rel_by_id:
                raise AuditError("Duplicate workbook relationship Id")
            rel_by_id[relation.get("Id")] = relation
        sheet_names = set()
        for sheet in workbook.findall("{" + SHEET_NS + "}sheets/{" + SHEET_NS + "}sheet"):
            relation = rel_by_id.get(sheet.get("{" + DOC_REL_NS + "}id"))
            if relation is None or relation.get("Type") != DOC_REL_NS + "/worksheet" or relation.get("TargetMode", "Internal") != "Internal":
                raise AuditError("Unexpected worksheet relationship")
            target = relation.get("Target", "")
            part = posixpath.normpath(target.lstrip("/") if target.startswith("/") else posixpath.join("xl", target))
            if not part.startswith("xl/worksheets/") or not part.endswith(".xml"):
                raise AuditError("Worksheet relationship escapes its package directory")
            sheet_props = ET.fromstring(package.read(part)).find("{" + SHEET_NS + "}sheetPr")
            if sheet_props is None or not sheet_props.get("codeName") or sheet_props.get("codeName") in sheet_names:
                raise AuditError("Worksheet codeName is missing or duplicated")
            sheet_names.add(sheet_props.get("codeName"))
        if workbook_name in sheet_names:
            raise AuditError("Workbook and worksheet codeName collide")
        vba_part = package.read("xl/vbaProject.bin")
        return {"status": "PASS", "workbookCodeName": workbook_name,
                "worksheetCodeNames": sorted(sheet_names), "ribbonSha256": digest(ribbon),
                "vbaProjectSha256": digest(vba_part), "menuCount": len(menus)}, vba_part


def fresh_output(path):
    path = path.absolute()
    for ancestor in (path, *path.parents):
        if ancestor.is_symlink() or (hasattr(ancestor, "is_junction") and ancestor.is_junction()):
            raise AuditError("Evidence path must not traverse a symlink or junction")
    output = path.resolve()
    artifacts = (REPO / "artifacts").resolve()
    if not output.is_relative_to(artifacts) or output == artifacts:
        raise AuditError("Use a fresh output directory below repository artifacts")
    if output.exists():
        raise AuditError("Existing output is preserved; choose a fresh directory")
    output.mkdir(parents=True)
    return output


def run_audit(xlam, source_directory, output_directory):
    xlam = xlam.resolve(strict=True)
    source_directory = source_directory.resolve(strict=True)
    if xlam.suffix.lower() != ".xlam":
        raise AuditError("The audited input must be an XLAM file")
    output = fresh_output(output_directory)
    report = {"schemaVersion": 1, "status": "FAIL", "xlamPath": str(xlam),
              "xlamSha256Before": digest(xlam.read_bytes()), "xlamSha256After": None,
              "sourceDirectory": str(source_directory), "sourceHashes": {}, "package": None,
              "serializedVba": None, "extractedModules": [], "errors": [],
              "scriptSha256": digest(Path(__file__).read_bytes()),
              "limitations": ["Read-only serialized source audit; no Excel or VBA was executed.",
                              "Compiled p-code, runtime behavior, installation and build cleanup are not verified.",
                              "Identifier case is normalized; strings, numeric tokens and comments retain their spelling.",
                              "Module export attributes and the default VB_VarHelpID=-1 immediately after its own Excel.Application WithEvents declaration are normalized."]}
    parser = None
    try:
        expected = {}
        for component, filename in SOURCE_FILES.items():
            data = (source_directory / filename).read_bytes()
            expected[component] = data.decode("ascii")
            report["sourceHashes"][filename] = digest(data)
        ribbon = (source_directory / "customUI14.xml").read_bytes()
        report["sourceHashes"]["customUI14.xml"] = digest(ribbon)
        package, vba_part = inspect_package(xlam, ribbon)
        report["package"] = package
        (output / "vbaProject.private.bin").write_bytes(vba_part)
        from oletools.olevba import VBA_Parser
        parser = VBA_Parser(str(xlam))
        modules = []
        containers = set()
        for index, (container, stream, filename, code) in enumerate(parser.extract_macros()):
            if not isinstance(code, str):
                raise AuditError("oletools did not decode serialized VBA source as text")
            extracted_name = "module-" + str(index).zfill(2) + ".private.txt"
            raw = code.encode("utf-8")
            (output / extracted_name).write_bytes(raw)
            module = {"container": str(container), "stream": stream, "filename": filename, "code": code}
            modules.append(module)
            containers.add(str(container))
            report["extractedModules"].append({"container": str(container), "stream": stream,
                                               "reportedFileName": filename, "file": extracted_name,
                                               "utf8Sha256": digest(raw)})
        if containers != {"xl/vbaProject.bin"}:
            raise AuditError("Expected only the xl/vbaProject.bin VBA project container")
        report["serializedVba"] = compare_modules(modules, expected, package["workbookCodeName"], set(package["worksheetCodeNames"]))
        report["errors"].extend(report["serializedVba"]["errors"])
        for filename, before in report["sourceHashes"].items():
            if digest((source_directory / filename).read_bytes()) != before:
                raise AuditError("Source snapshot changed during audit: " + filename)
    except Exception as error:
        report["errors"].append(type(error).__name__ + ": " + str(error))
    finally:
        if parser is not None:
            try:
                parser.close()
            except Exception as error:
                report["errors"].append("VBA parser cleanup failed: " + str(error))
        try:
            report["xlamSha256After"] = digest(xlam.read_bytes())
            if report["xlamSha256Before"] != report["xlamSha256After"]:
                report["errors"].append("XLAM changed during read-only audit")
        except OSError as error:
            report["errors"].append("Final XLAM hash unavailable: " + str(error))
        report["status"] = "PASS" if not report["errors"] else "FAIL"
        (output / "audit.private.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main():
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument("--xlam", type=Path, required=True)
    arguments.add_argument("--source-directory", type=Path, required=True)
    arguments.add_argument("--output-directory", type=Path, required=True)
    args = arguments.parse_args()
    try:
        report = run_audit(args.xlam, args.source_directory, args.output_directory)
    except (AuditError, OSError) as error:
        raise SystemExit(str(error)) from error
    print(json.dumps({"status": report["status"], "xlamSha256": report["xlamSha256After"],
                      "moduleCount": len(report["extractedModules"]), "errors": report["errors"],
                      "report": str(args.output_directory / "audit.private.json")}, ensure_ascii=True, indent=2))
    raise SystemExit(0 if report["status"] == "PASS" else 1)


if __name__ == "__main__":
    main()
