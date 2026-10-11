"""Independent JSON Schema implementation complements browser semantic validation."""
import copy
import json
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker

root = Path(__file__).resolve().parents[3]
schema = json.loads((root / 'tools/calendar/calendar.schema.json').read_text(encoding='utf-8'))
Draft202012Validator.check_schema(schema)
validator = Draft202012Validator(schema, format_checker=FormatChecker())
data = json.loads((root / 'artifacts/calendar/fixture.json').read_text(encoding='utf-8'))
validator.validate(data)
for mutate in [lambda d: d.update(schemaVersion=999), lambda d: d.update(unreviewed='field'),
               lambda d: d['years'][str(d['targetYears'][0])]['monthResults'].pop()]:
    broken = copy.deepcopy(data)
    mutate(broken)
    assert list(validator.iter_errors(broken)), 'schema must reject broken contract'
print('PASS independent Draft 2020-12 schema and malformed schema/version/month checks')
