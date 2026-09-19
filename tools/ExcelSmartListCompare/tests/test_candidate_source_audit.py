"""Independent source-audit negatives; never starts Excel or executes VBA."""
import copy
import importlib.util
import io
from pathlib import Path
import unittest
import zipfile

SPEC = importlib.util.spec_from_file_location("slc_candidate_audit", Path(__file__).with_name("audit_candidate.py"))
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


def module(name, code, base=None):
    header = 'Attribute VB_Name = "' + name + '"\r\n'
    if base:
        header += 'Attribute VB_Base = "' + base + '"\r\n'
    return {"filename": name + ".bas", "stream": "VBA/" + name, "code": header + code}


class CandidateSourceCanonicalizationTests(unittest.TestCase):
    def canonical(self, code):
        return audit.canonicalize_vba("Option Explicit\n" + code)

    def test_identifier_case_and_export_metadata_are_normalized(self):
        expected = 'Attribute VB_Name = "Demo"\r\nOption Explicit\r\nbutton.Caption = caption  \r\n'
        actual = 'Attribute VB_Name = "DEMO"\nAttribute VB_Exposed = False\nOption Explicit\nbutton.caption = Caption\n\n'
        self.assertEqual(audit.canonicalize_vba(expected), audit.canonicalize_vba(actual))

    def test_string_literal_case_and_escaped_quotes_remain_significant(self):
        for left, right in [('MsgBox "VALUE"', 'MsgBox "value"'),
                            ('MsgBox "Do ""Not"" Fold"', 'MsgBox "Do ""not"" Fold"'),
                            ('x = "it\'s DATA"', 'x = "it\'s data"')]:
            with self.subTest(left=left):
                self.assertNotEqual(self.canonical(left), self.canonical(right))

    def test_comment_spelling_numbers_operators_and_identifiers_remain_significant(self):
        for left, right in [("x = 1 'Keep Case", "x = 1 'keep case"),
                            ("Rem Keep Case", "Rem keep case"),
                            ("x = 10", "x = 11"), ("x = 1E3", "x = 1e3"),
                            ("x = &HAb", "x = &HaB"), ("x = a + b", "x = a - b"),
                            ("button.Caption = value", "button.Caption = other")]:
            with self.subTest(left=left):
                self.assertNotEqual(self.canonical(left), self.canonical(right))

    def test_missing_boundary_unterminated_string_and_hidden_prefix_code_are_rejected(self):
        for source in ['Sub Run()\nEnd Sub', 'Option Explicit\nx = "unfinished',
                       'Private Sub Evil()\nEnd Sub\nOption Explicit\nx = 1']:
            with self.subTest(source=source):
                with self.assertRaises(audit.AuditError):
                    audit.canonicalize_vba(source)

    def test_excel_export_default_withevents_help_metadata_is_narrowly_normalized(self):
        source = "Option Explicit\nPublic WithEvents ExcelApp As Excel.Application\n"
        exported = source + "Attribute ExcelApp.VB_VarHelpID = -1\n"
        self.assertEqual(audit.canonicalize_vba(source),
                         audit.canonicalize_vba(exported, serialized=True))
        self.assertNotEqual(audit.canonicalize_vba(source), audit.canonicalize_vba(exported))
        for changed in [exported.replace("-1", "0"),
                        exported.replace("Attribute ExcelApp.", "Attribute Other."),
                        exported.replace("VB_VarHelpID", "VB_UserMemId"),
                        exported.replace("\nAttribute", "\n\nAttribute"),
                        exported.replace("Public WithEvents", "Public")]:
            with self.subTest(changed=changed):
                self.assertNotEqual(audit.canonicalize_vba(source),
                                    audit.canonicalize_vba(changed, serialized=True))


class CandidateModuleContractTests(unittest.TestCase):
    def setUp(self):
        self.expected = {name: "Option Explicit\nPrivate Sub Run()\n    " + name + "_Body\nEnd Sub\n"
                         for name in audit.SOURCE_FILES}
        self.modules = []
        for component, body in self.expected.items():
            name = "현재_통합_문서" if component == "ThisWorkbook" else component
            base = audit.WORKBOOK_BASE if component == "ThisWorkbook" else (
                audit.CLASS_BASE if component in {"CSLCList", "CSLCAppEvents"} else None)
            self.modules.append(module(name, body, base))
        self.modules.append(module("Sheet1", "", audit.SHEET_BASE))

    def compare(self, modules):
        return audit.compare_modules(modules, self.expected, "현재_통합_문서", {"Sheet1"})

    def test_six_expected_components_and_empty_real_sheet_pass(self):
        result = self.compare(self.modules)
        self.assertEqual(result["status"], "PASS", result)
        self.assertEqual(len(result["modules"]), 7)

    def test_missing_product_component_is_rejected(self):
        result = self.compare(self.modules[1:])
        self.assertEqual(result["status"], "FAIL")
        self.assertIn("Missing required modules: CSLCList", result["errors"])

    def test_unexpected_executable_module_and_sheet_event_are_rejected(self):
        for extra in [module("Unrelated", "Option Explicit\nSub Run()\nEnd Sub"),
                      module("Sheet1", "Option Explicit\nPrivate Sub Worksheet_Activate()\nEnd Sub", audit.SHEET_BASE),
                      module("UnlistedEmptySheet", "", audit.SHEET_BASE)]:
            with self.subTest(extra=extra["filename"]):
                result = self.compare(self.modules[:-1] + [extra])
                self.assertEqual(result["status"], "FAIL")
                self.assertTrue(any("Unexpected or executable" in error for error in result["errors"]))

    def test_modified_body_and_duplicate_component_are_rejected(self):
        modified = copy.deepcopy(self.modules)
        modified[0]["code"] = modified[0]["code"].replace("CSLCList_Body", "Different_Body")
        self.assertTrue(any("source mismatch" in error for error in self.compare(modified)["errors"]))
        duplicated = self.modules + [self.modules[0]]
        self.assertTrue(any("Duplicate serialized module" in error for error in self.compare(duplicated)["errors"]))

    def test_workbook_events_in_an_ordinary_module_cannot_pass(self):
        modified = copy.deepcopy(self.modules)
        workbook_index = next(i for i, value in enumerate(modified) if "현재_통합_문서" in value["filename"])
        modified[workbook_index] = module("현재_통합_문서", self.expected["ThisWorkbook"])
        self.assertEqual(self.compare(modified)["status"], "FAIL")


class CandidatePackageContractTests(unittest.TestCase):
    def setUp(self):
        self.ribbon = ('<customUI xmlns="' + audit.UI_NS + '" onLoad="SLC_RibbonLoad"><contextMenus>'
                       + ''.join('<contextMenu idMso="' + name + '"><dynamicMenu id="slc68' + tag
                                 + 'Menu" tag="' + tag + '" label="명단 비교" getContent="SLC_GetContextMenu"'
                                 + ' invalidateContentOnDrop="true"/></contextMenu>'
                                 for name, tag in audit.MENUS.items())
                       + '</contextMenus></customUI>').encode('utf-8')
        self.parts = {
            'customUI/customUI14.xml': self.ribbon,
            '_rels/.rels': ('<Relationships xmlns="' + audit.REL_NS + '"><Relationship Id="UI" Type="'
                            + audit.UI_REL_TYPE + '" Target="customUI/customUI14.xml"/></Relationships>').encode(),
            '[Content_Types].xml': ('<Types xmlns="' + audit.CONTENT_NS + '"><Override PartName="/customUI/customUI14.xml"'
                                    + ' ContentType="application/xml"/></Types>').encode(),
            'xl/workbook.xml': ('<workbook xmlns="' + audit.SHEET_NS + '" xmlns:r="' + audit.DOC_REL_NS
                                + '"><workbookPr codeName="ThisWorkbook"/><sheets>'
                                + '<sheet name="Sheet1" sheetId="1" r:id="S1"/></sheets></workbook>').encode(),
            'xl/_rels/workbook.xml.rels': ('<Relationships xmlns="' + audit.REL_NS + '"><Relationship Id="S1" Type="'
                                          + audit.DOC_REL_NS + '/worksheet" Target="worksheets/sheet1.xml"/></Relationships>').encode(),
            'xl/worksheets/sheet1.xml': ('<worksheet xmlns="' + audit.SHEET_NS + '"><sheetPr codeName="Sheet1"/></worksheet>').encode(),
            'xl/vbaProject.bin': b'fixture-only-never-executed',
        }

    def package(self, parts=None):
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w') as package:
            for name, content in (parts or self.parts).items():
                package.writestr(name, content)
        data.seek(0)
        return data

    def test_exact_ribbon_wiring_and_document_names_pass(self):
        package, vba = audit.inspect_package(self.package(), self.ribbon)
        self.assertEqual(package['status'], 'PASS')
        self.assertEqual(package['menuCount'], 8)
        self.assertEqual(package['worksheetCodeNames'], ['Sheet1'])
        self.assertEqual(vba, self.parts['xl/vbaProject.bin'])

    def test_binary_ribbon_must_match_source_even_with_valid_contract(self):
        with self.assertRaisesRegex(audit.AuditError, 'differs from the source'):
            audit.inspect_package(self.package(), self.ribbon + b'\n')

    def test_matching_but_changed_callback_id_or_label_is_rejected(self):
        for original, replacement in [(b'SLC_GetContextMenu', b'UnknownCallback'),
                                      (b'slc68CellMenu', b'OtherCellMenu'),
                                      ('명단 비교'.encode(), b'Other label')]:
            with self.subTest(replacement=replacement):
                changed = dict(self.parts)
                changed['customUI/customUI14.xml'] = self.ribbon.replace(original, replacement)
                with self.assertRaisesRegex(audit.AuditError, 'contract differs'):
                    audit.inspect_package(self.package(changed), changed['customUI/customUI14.xml'])

    def test_missing_duplicate_and_external_ribbon_relationship_are_rejected(self):
        value = self.parts['_rels/.rels']
        relationship = value[value.index(b'<Relationship Id='):value.index(b'</Relationships>')]
        for changed_value in [value.replace(relationship, b''),
                              value.replace(relationship, relationship + relationship),
                              value.replace(b' Target=', b' TargetMode="External" Target=')]:
            changed = dict(self.parts)
            changed['_rels/.rels'] = changed_value
            with self.assertRaisesRegex(audit.AuditError, 'RibbonX relationship'):
                audit.inspect_package(self.package(changed), self.ribbon)

    def test_content_type_and_worksheet_target_contracts_are_enforced(self):
        for part, before, after, error in [
                ('[Content_Types].xml', b'application/xml', b'text/plain', 'content type'),
                ('xl/_rels/workbook.xml.rels', b'worksheets/sheet1.xml', b'../outside.xml', 'escapes'),
                ('xl/worksheets/sheet1.xml', b'codeName="Sheet1"', b'codeName=""', 'codeName')]:
            with self.subTest(part=part):
                changed = dict(self.parts)
                changed[part] = changed[part].replace(before, after)
                with self.assertRaisesRegex(audit.AuditError, error):
                    audit.inspect_package(self.package(changed), self.ribbon)


if __name__ == "__main__":
    unittest.main()
