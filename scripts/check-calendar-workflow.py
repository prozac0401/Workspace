"""Offline contract checks for event, permission and artifact dependencies. Does not run Actions."""
from pathlib import Path
import yaml

root = Path(__file__).resolve().parent.parent
workflow = yaml.load((root / '.github/workflows/docs.yml').read_text(encoding='utf-8'), Loader=yaml.BaseLoader)
events, jobs = workflow['on'], workflow['jobs']
assert set(events) == {'push', 'pull_request', 'schedule', 'workflow_dispatch'}
assert events['schedule'] == [{'cron': '17 3 1 * *'}]
assert events['workflow_dispatch']['inputs']['action']['options'] == ['collect', 'reuse']
assert events['workflow_dispatch']['inputs']['action']['default'] == 'collect'
assert events['workflow_dispatch']['inputs']['initialize_data']['default'] == 'false'
assert workflow['permissions'] == {'contents': 'read'}
assert workflow['concurrency']['cancel-in-progress'] == 'false'
assert 'workspace-pages-production' in workflow['concurrency']['group']
assert set(jobs) == {'verify', 'prepare-data', 'store-data', 'build', 'deploy'}
for name in ['prepare-data', 'deploy']:
    gate = jobs[name]['if']
    for token in ["vars.CALENDAR_ENABLED == 'true'", "github.repository == 'prozac0401/Workspace'", 'github.event.repository.default_branch', '"push","schedule","workflow_dispatch"']:
        assert token in gate, (name, token)
assert jobs['prepare-data']['needs'] == 'verify'
assert jobs['store-data']['needs'] == 'prepare-data'
assert jobs['store-data']['if'] == "needs.prepare-data.outputs.persist == 'true'"
assert jobs['build']['needs'] == ['verify', 'prepare-data', 'store-data']
assert "needs.prepare-data.outputs.deploy == 'true'" in jobs['build']['if']
assert "needs.store-data.outputs.data_sha != ''" in jobs['build']['if']
assert jobs['deploy']['needs'] == 'build'
# reuse intentionally skips store-data. An explicit status function prevents
# an implicit success() from propagating that ancestor's skip through build.
assert "!cancelled()" in jobs['deploy']['if']
assert "needs.build.result == 'success'" in jobs['deploy']['if']
assert jobs['deploy']['environment']['name'] == 'github-pages'
for name, job in jobs.items():
    permissions = job.get('permissions', workflow['permissions'])
    assert permissions.get('contents') == ('write' if name == 'store-data' else 'read')
    if name == 'deploy':
        assert permissions == {'contents': 'read', 'pages': 'write', 'id-token': 'write'}
    else:
        assert set(permissions) == {'contents'}
    text = yaml.dump(job)
    if 'secrets.' in text:
        assert name == 'prepare-data' and 'secrets.KASI_SERVICE_KEY' in text
    if name == 'verify':
        assert 'upload-pages-artifact' not in text and 'secrets.' not in text
    if 'upload-pages-artifact' in text:
        assert name == 'build' and '--production' in text and 'CALENDAR_PRODUCTION' in text
deployers = []
for path in (root / '.github/workflows').glob('*.yml'):
    data = yaml.load(path.read_text(encoding='utf-8'), Loader=yaml.BaseLoader)
    if 'actions/deploy-pages@' in yaml.dump(data):
        deployers.append(path.name)
assert deployers == ['docs.yml'], deployers
print('PASS workflow events, production gates, least job permissions, pinned data dependency, one Pages deployer')
