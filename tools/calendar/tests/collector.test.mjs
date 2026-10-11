import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { collectDataset, runCollector, atomicWriteJson } from '../collect.mjs';
import { HolidayError, createHolidayService } from '../lib/holiday-provider.mjs';
import { targetYears } from '../../../docs/assets/calendar/contract.mjs';
import { fixture, readyYear, NOW, mockFetch } from './fixtures/helpers.mjs';
const official = () => ({ ...fixture(), datasetKind: 'official' }); // Synthetic, tests only; never copied to the public site.
const fresh = { getYear: async year => readyYear(year, NOW) };
const fail = { getYear: async () => { throw new Error('SECRET-URL-OR-RESPONSE'); } };
async function directory(t) { const dir = await mkdtemp(join(tmpdir(), 'workspace-calendar-test-')); t.after(() => rm(dir, { recursive: true, force: true })); return dir; }

test('complete collection returns deployable public projection; partial preserves previous evidence', async () => {
  const success = await collectDataset({ service: fresh, now: NOW });
  assert.equal(success.report.deployEligible, true); assert.equal(success.report.outcome, 'success');
  assert.equal(success.report.successfulYears.length, 117); assert.deepEqual(success.report.successfulYears.slice(0, 2), [2026, 2027]);
  const previous = official();
  const partial = await collectDataset({ previous, now: NOW + 1000, service: { getYear: async year => year === 2026 ? readyYear(year, NOW + 1000) : fail.getYear() } });
  assert.equal(partial.report.outcome, 'partial'); assert.deepEqual(partial.report.successfulYears, [2026]);
  assert.equal(partial.report.failedYears.length, 116); assert.deepEqual(partial.report.preservedYears, partial.report.failedYears);
  assert.deepEqual(partial.report.unavailableYears, []); assert.equal(partial.report.deployEligible, false);
  for (const field of ['lastSuccessfulFetchAt', 'snapshotId', 'monthResults', 'holidays']) assert.deepEqual(partial.data.years[2027][field], previous.years[2027][field]);
  assert.equal(partial.data.years[2027].status, 'preserved');
  assert.ok(!JSON.stringify(partial).includes('SECRET'));
});
test('unpublished optional year stays unavailable and permits deployment only when current year freshly succeeded', async () => {
  const result = await collectDataset({ now: NOW, service: { getYear: async year => { if (year === 2027) throw new HolidayError('YEAR_UNAVAILABLE'); return readyYear(year); } } });
  assert.equal(result.data.years[2026].complete, true); assert.equal(result.data.years[2027].complete, false);
  assert.equal(result.data.years[2027].status, 'unavailable'); assert.equal(result.report.deployEligible, true);
  assert.equal(result.report.outcome, 'partial'); assert.deepEqual(result.report.unavailableYears, [2027]); assert.deepEqual(result.report.failedYears, []);
});
test('new-year rollover retains the fixed range and all previous source evidence on failure', async () => {
  const previous = official(), now = Date.parse('2026-12-31T15:00:00.000Z');
  const result = await collectDataset({ previous, now, service: fail });
  assert.deepEqual(result.data.targetYears, targetYears()); assert.ok(result.data.years[1983]); assert.ok(result.data.years[2099]);
  assert.equal(result.data.years[2027].snapshotId, previous.years[2027].snapshotId);
  assert.equal(result.data.years[2028].complete, true); assert.equal(result.data.years[2028].status, 'preserved');
  assert.equal(result.report.outcome, 'failed'); assert.equal(result.report.deployEligible, false);
});
test('partial atomically persists, total failure leaves prior JSON byte-for-byte, safe report persisted', async t => {
  const dir = await directory(t), outputPath = join(dir, 'calendar.json'), reportPath = join(dir, 'report.json');
  const original = JSON.stringify(official()); await writeFile(outputPath, original);
  const options = { previousPath: outputPath, outputPath, reportPath, env: { KASI_SERVICE_KEY: 'FAKE-TEST' }, now: NOW };
  await runCollector({ ...options, service: fail });
  assert.equal(await readFile(outputPath, 'utf8'), original);
  assert.equal(JSON.parse(await readFile(reportPath, 'utf8')).outcome, 'failed');
  await runCollector({ ...options, service: { getYear: async year => year === 2026 ? readyYear(year, NOW + 1) : fail.getYear() } });
  const result = JSON.parse(await readFile(outputPath, 'utf8'));
  assert.equal(result.years[2026].lastSuccessfulFetchAt, new Date(NOW + 1).toISOString());
  assert.equal(result.years[2027].status, 'preserved');
  assert.ok(!(await readdir(dir)).some(name => name.endsWith('.tmp') || name.endsWith('.lock')));
});
test('no-secret exits before fetch or writes; invalid prior and fixture never replaced', async t => {
  const dir = await directory(t), outputPath = join(dir, 'calendar.json'), reportPath = join(dir, 'report.json');
  await assert.rejects(runCollector({ outputPath, reportPath, env: {}, service: { getYear: () => assert.fail('no fetch') } }), e => e.code === 'CONFIGURATION_ERROR');
  assert.deepEqual(await readdir(dir), []);
  for (const bytes of ['{bad json', JSON.stringify(fixture()), JSON.stringify({ ...official(), schemaVersion: 1 })]) {
    await writeFile(outputPath, bytes);
    await assert.rejects(runCollector({ previousPath: outputPath, outputPath, reportPath, env: { KASI_SERVICE_KEY: 'FAKE' }, service: fresh, now: NOW }), e => e.code === 'PREVIOUS_DATA_INVALID');
    assert.equal(await readFile(outputPath, 'utf8'), bytes);
  }
  const cli = spawnSync(process.execPath, [new URL('../collect.mjs', import.meta.url).pathname.replace(/^\/(?=[A-Z]:)/, ''), '--output', outputPath, '--report', reportPath], { env: { ...process.env, KASI_SERVICE_KEY: '' }, encoding: 'utf8' });
  assert.equal(cli.status, 1); assert.equal(cli.stderr.trim(), 'CONFIGURATION_ERROR');
});
test('zero annual records for current year or a previously complete year are failures, never optional unavailability', async () => {
  const currentMissing = await collectDataset({ now: NOW, service: { getYear: async year => {
    if (year === 2026) throw new HolidayError('YEAR_UNAVAILABLE'); return readyYear(year);
  } } });
  assert.deepEqual(currentMissing.report.failedYears, [2026]); assert.deepEqual(currentMissing.report.unavailableYears, []);
  assert.equal(currentMissing.report.deployEligible, false); assert.equal(currentMissing.data.years[2026].complete, false);
  const previous = official();
  const oldMissing = await collectDataset({ previous, now: NOW, service: { getYear: async year => {
    if (year === 1983) throw new HolidayError('YEAR_UNAVAILABLE'); return readyYear(year);
  } } });
  assert.deepEqual(oldMissing.report.failedYears, [1983]); assert.deepEqual(oldMissing.report.unavailableYears, []);
  assert.equal(oldMissing.report.deployEligible, false); assert.equal(oldMissing.data.years[1983].status, 'preserved');
  assert.deepEqual(oldMissing.data.years[1983].holidays, previous.years[1983].holidays);
});
test('all 117 years and all 12 months are actually queried with current and next year priority, 1404 base requests', async () => {
  const calls = [];
  const service = createHolidayService({ key: 'FAKE-TEST-ONLY', now: () => NOW, delay: async () => {}, fetchImpl: async url => {
    calls.push(`${url.searchParams.get('solYear')}-${url.searchParams.get('solMonth')}`);
    return mockFetch(url);
  } });
  const result = await collectDataset({ service, now: NOW });
  assert.equal(result.report.outcome, 'success'); assert.equal(result.report.deployEligible, true);
  assert.equal(calls.length, 1404); assert.equal(new Set(calls).size, 1404);
  assert.ok(calls.slice(0, 12).every(call => call.startsWith('2026-')));
  assert.ok(calls.slice(12, 24).every(call => call.startsWith('2027-')));
  assert.equal(result.data.years[1983].complete, true); assert.equal(result.data.years[2099].complete, true);
});
test('interrupted atomic write keeps original, cleans temporary; concurrent collector is rejected', async t => {
  const dir = await directory(t), outputPath = join(dir, 'calendar.json'), reportPath = join(dir, 'report.json');
  await writeFile(outputPath, 'original');
  await assert.rejects(atomicWriteJson(outputPath, official(), { beforeRename: () => { throw new Error('interrupted'); } }), e => e.code === 'PERSISTENCE_ERROR');
  assert.equal(await readFile(outputPath, 'utf8'), 'original'); assert.deepEqual(await readdir(dir), ['calendar.json']);
  let release, started;
  const signal = new Promise(resolve => { started = resolve; });
  await writeFile(outputPath, JSON.stringify(official()));
  const pending = runCollector({ outputPath, reportPath, env: { KASI_SERVICE_KEY: 'FAKE' }, now: NOW, service: { getYear: async year => { if (year === 2026) { started(); await new Promise(resolve => { release = resolve; }); } return readyYear(year); } } });
  await signal;
  await assert.rejects(runCollector({ outputPath, reportPath, env: { KASI_SERVICE_KEY: 'FAKE' }, now: NOW, service: fresh }), e => e.code === 'OUTPUT_BUSY');
  release(); await pending;
  assert.equal(JSON.parse(await readFile(outputPath, 'utf8')).years[2026].complete, true);
});
test('malformed service success becomes explicit collection failure, never a persisted ready snapshot', async () => {
  const result = await collectDataset({ now: NOW, service: { getYear: async year => ({ ...readyYear(year), holidays: [] }) } });
  assert.equal(result.report.outcome, 'failed'); assert.equal(result.report.deployEligible, false);
  assert.ok(Object.values(result.data.years).every(y => y.complete === false));
});
test('preserving a full warning list or an existing failure warning stays valid without losing source evidence', async () => {
  const warning = '최근 수집 실패: 이전 검증 자료를 보존했습니다. 사용 전 최신성을 확인하세요.';
  for (const warnings of [Array.from({ length: 20 }, (_, i) => `이전 자료 안내 ${i + 1}`), [warning]]) {
    const previous = official(); previous.years[2027].warnings = warnings;
    const result = await collectDataset({ previous, now: NOW + 1, service: { getYear: async year => year === 2026 ? readyYear(year, NOW + 1) : fail.getYear() } });
    assert.equal(result.report.outcome, 'partial'); assert.equal(result.report.deployEligible, false);
    const preserved = result.data.years[2027];
    assert.equal(preserved.status, 'preserved'); assert.deepEqual(preserved.warnings, warnings); assert.ok(preserved.warnings.length <= 20);
    for (const field of ['snapshotId', 'lastSuccessfulFetchAt', 'monthResults', 'holidays']) assert.deepEqual(preserved[field], previous.years[2027][field]);
  }
});
