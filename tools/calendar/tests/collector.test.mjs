import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { collectDataset, runCollector, atomicWriteJson } from '../collect.mjs';
import { HolidayError } from '../lib/holiday-provider.mjs';
import { fixture, readyYear, NOW } from './fixtures/helpers.mjs';
const official = () => ({ ...fixture(), datasetKind: 'official' }); // Synthetic, tests only; never copied to the public site.
const fresh = { getYear: async year => readyYear(year, NOW) };
const fail = { getYear: async () => { throw new Error('SECRET-URL-OR-RESPONSE'); } };
async function directory(t) { const dir = await mkdtemp(join(tmpdir(), 'workspace-calendar-test-')); t.after(() => rm(dir, { recursive: true, force: true })); return dir; }

test('complete collection returns deployable public projection; partial preserves previous evidence', async () => {
  const success = await collectDataset({ service: fresh, now: NOW });
  assert.equal(success.report.deployEligible, true); assert.equal(success.report.outcome, 'success');
  const previous = official();
  const partial = await collectDataset({ previous, now: NOW + 1000, service: { getYear: async year => year === 2026 ? readyYear(year, NOW + 1000) : fail.getYear() } });
  assert.deepEqual(partial.report, { outcome: 'partial', successfulYears: [2026], preservedYears: [2027], failedYears: [2027], deployEligible: false });
  for (const field of ['lastSuccessfulFetchAt', 'snapshotId', 'monthResults', 'holidays']) assert.deepEqual(partial.data.years[2027][field], previous.years[2027][field]);
  assert.equal(partial.data.years[2027].status, 'preserved');
  assert.ok(!JSON.stringify(partial).includes('SECRET'));
});
test('future unpublished year is unavailable, not ready/empty holidays; current-year data retained', async () => {
  const result = await collectDataset({ now: NOW, service: { getYear: async year => { if (year === 2027) throw new HolidayError('YEAR_UNAVAILABLE'); return readyYear(year); } } });
  assert.equal(result.data.years[2026].complete, true); assert.equal(result.data.years[2027].complete, false);
  assert.equal(result.data.years[2027].status, 'unavailable'); assert.equal(result.report.deployEligible, false);
});
test('new-year rollover retains still-supported data and adds unavailable next target', async () => {
  const previous = official(), now = Date.parse('2026-12-31T15:00:00.000Z');
  const result = await collectDataset({ previous, now, service: fail });
  assert.deepEqual(result.data.targetYears, [2027, 2028]); assert.ok(!result.data.years[2026]);
  assert.equal(result.data.years[2027].snapshotId, previous.years[2027].snapshotId);
  assert.equal(result.data.years[2028].complete, false); assert.equal(result.report.outcome, 'failed');
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
  for (const bytes of ['{bad json', JSON.stringify(fixture()), JSON.stringify({ ...official(), schemaVersion: 2 })]) {
    await writeFile(outputPath, bytes);
    await assert.rejects(runCollector({ previousPath: outputPath, outputPath, reportPath, env: { KASI_SERVICE_KEY: 'FAKE' }, service: fresh, now: NOW }), e => e.code === 'PREVIOUS_DATA_INVALID');
    assert.equal(await readFile(outputPath, 'utf8'), bytes);
  }
  const cli = spawnSync(process.execPath, [new URL('../collect.mjs', import.meta.url).pathname.replace(/^\/(?=[A-Z]:)/, ''), '--output', outputPath, '--report', reportPath], { env: { ...process.env, KASI_SERVICE_KEY: '' }, encoding: 'utf8' });
  assert.equal(cli.status, 1); assert.equal(cli.stderr.trim(), 'CONFIGURATION_ERROR');
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
