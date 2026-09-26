"""Append a synthetic feature sheet to an existing synthetic File List workbook."""
import argparse
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
boundary = Path(__file__).resolve().parents[1] / "artifacts"
if not args.source.resolve().is_relative_to(boundary) or not args.output.resolve().is_relative_to(boundary):
    raise ValueError("Use only repository artifact fixtures")
sheet = """<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetViews><sheetView workbookViewId="0"><selection activeCell="H1" sqref="H1:J1"/></sheetView></sheetViews>
<sheetData>
<row r="1"><c r="H1"><v>85</v></c><c r="I1"><v>90</v></c><c r="J1"><v>78</v></c></row>
<row r="2"><c r="E2" t="inlineStr"><is><t>before2</t></is></c></row>
<row r="3" hidden="1"><c r="E3" t="inlineStr"><is><t>hidden3</t></is></c></row>
<row r="4"><c r="E4" t="inlineStr"><is><t>before4</t></is></c></row>
<row r="5"><c r="E5" t="inlineStr"><is><t>before5</t></is></c></row>
<row r="6"><c r="E6" t="inlineStr"><is><t>outside6</t></is></c><c r="L6" t="inlineStr"><is><t>Alpha</t></is></c><c r="M6" t="inlineStr"><is><t>Alpha</t></is></c></row>
<row r="7"><c r="L7" t="inlineStr"><is><t>Beta</t></is></c><c r="M7" t="inlineStr"><is><t>Beta</t></is></c></row>
<row r="8"><c r="L8" t="inlineStr"><is><t>Beta</t></is></c><c r="M8" t="inlineStr"><is><t>Gamma</t></is></c></row>
</sheetData></worksheet>"""
ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
with zipfile.ZipFile(args.source) as source, zipfile.ZipFile(args.output, "x", zipfile.ZIP_DEFLATED) as dest:
    if "xl/worksheets/sheet2.xml" in source.namelist():
        raise ValueError("Expected a one-sheet File List fixture")
    for name in source.namelist():
        data = source.read(name)
        if name == "xl/workbook.xml":
            document = ET.fromstring(data)
            ET.SubElement(document.find(f"{{{ns}}}sheets"), f"{{{ns}}}sheet", {"name": "OwnedCoexist", "sheetId": "2", f"{{{rel}}}id": "rIdCoexist"})
            views = document.find(f"{{{ns}}}bookViews")
            if views is None:
                views = ET.Element(f"{{{ns}}}bookViews")
                document.insert(0, views)
            view = views.find(f"{{{ns}}}workbookView")
            if view is None:
                view = ET.SubElement(views, f"{{{ns}}}workbookView")
            view.set("activeTab", "1")
            data = ET.tostring(document, encoding="utf-8", xml_declaration=True)
        elif name == "xl/_rels/workbook.xml.rels":
            document = ET.fromstring(data)
            ET.SubElement(document, "{http://schemas.openxmlformats.org/package/2006/relationships}Relationship", {"Id": "rIdCoexist", "Type": rel + "/worksheet", "Target": "worksheets/sheet2.xml"})
            data = ET.tostring(document, encoding="utf-8", xml_declaration=True)
        elif name == "[Content_Types].xml":
            document = ET.fromstring(data)
            ET.SubElement(document, "{http://schemas.openxmlformats.org/package/2006/content-types}Override", {"PartName": "/xl/worksheets/sheet2.xml", "ContentType": "application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"})
            data = ET.tostring(document, encoding="utf-8", xml_declaration=True)
        dest.writestr(name, data)
    dest.writestr("xl/worksheets/sheet2.xml", sheet)
print("Created one synthetic workbook with File List and coexistence feature sheets")
