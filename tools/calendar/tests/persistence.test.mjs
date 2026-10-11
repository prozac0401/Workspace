import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, writeFile, readFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gitStore } from '../data-store.mjs';
import { prepareSite, assertDeployable } from '../prepare-site.mjs';
import { prepareWorkflow, deploymentDecision } from '../workflow-data.mjs';
import { fixture, NOW } from './fixtures/helpers.mjs';
import { MAX_STALE, MAX_DATA_BYTES, validateDataset } from '../../../docs/assets/calendar/contract.mjs';
const execute = promisify(execFile);
const artifacts = fileURLToPath(new URL('../../../artifacts/calendar-tests/', import.meta.url));
const official = () => ({ ...fixture(), datasetKind: 'official' });

test('durable Git storage: init is explicit, only JSON persists, pinned reads survive new runner and racing saves reject', async () => {
  await mkdir(artifacts, { recursive: true });
  const base = await mkdtemp(join(artifacts, 'git-'));
  const remote = join(base, 'public-data.git'), checkout = join(base, 'source'), next = join(base, 'new-runner');
  async function git(args, cwd = base) { return (await execute('git', args, { cwd, windowsHide: true })).stdout.trim(); }
  await git(['init', '--bare', remote]); await mkdir(checkout); await git(['init'], checkout);
  await git(['remote', 'add', 'origin', remote], checkout);
  await writeFile(join(checkout, 'private-source.txt'), 'source must never enter data branch');
  const store = gitStore(checkout), file = join(base, 'candidate.json');
  assert.deepEqual(await store.read({ allowMissing: true }), { sha: null, data: null });
  await assert.rejects(store.read(), /INITIALIZATION_REQUIRED/);
  await writeFile(file, JSON.stringify(official()));
  await assert.rejects(store.save({ file }), /INITIALIZATION_REQUIRED/);
  const first = await store.save({ file, initialize: true });
  assert.match(first, /^[a-f0-9]{40}$/);
  assert.equal(await git(['ls-tree', '-r', '--name-only', first], checkout), 'calendar.json');
  assert.equal(await git(['status', '--porcelain'], checkout), '?? private-source.txt');
  await mkdir(next); await git(['init'], next); await git(['remote', 'add', 'origin', remote], next);
  const recovered = await gitStore(next).read(); assert.equal(recovered.sha, first); assert.deepEqual(recovered.data, official());
  const changed = official(); changed.years[2027].snapshotId = 'second-fetch';
  await writeFile(file, JSON.stringify(changed));
  const second = await store.save({ file, expectedSha: first }); assert.notEqual(second, first);
  await assert.rejects(gitStore(next).save({ file, expectedSha: first }), /CONCURRENT_UPDATE/);
  assert.deepEqual((await gitStore(next).read({ sha: first })).data, official());
  assert.equal((await store.read()).sha, second);
  await writeFile(file, JSON.stringify(fixture()));
  await assert.rejects(store.save({ file, expectedSha: second }));
  assert.equal(await store.current(), second);
});

test('deployment skips collection errors but allows explicitly unavailable optional years after current-year success', () => {
  assert.deepEqual(deploymentDecision({ outcome: 'partial', successfulYears: [2026], failedYears: [2027], deployEligible: false }), { persist: true, deploy: false });
  assert.deepEqual(deploymentDecision({ outcome: 'failed', successfulYears: [], failedYears: [2026], deployEligible: false }), { persist: false, deploy: false });
  assert.deepEqual(deploymentDecision({ outcome: 'success', successfulYears: [2026, 2027], failedYears: [], deployEligible: true }), { persist: true, deploy: true });
  assert.deepEqual(deploymentDecision({ outcome: 'partial', successfulYears: [2026, 2027], failedYears: [], unavailableYears: [2099], deployEligible: true }), { persist: true, deploy: true });
  assert.deepEqual(deploymentDecision({ outcome: 'partial', successfulYears: [2026], failedYears: [2027], deployEligible: true }), { persist: true, deploy: false });
});

test('local build uses explicit unavailable JSON; production refuses fixture, missing, expired and year rollover data', async () => {
  await mkdir(artifacts, { recursive: true });
  const directory = await mkdtemp(join(artifacts, 'site-')), output = join(directory, 'calendar.json');
  const data = await prepareSite({ output, now: NOW });
  assert.equal(data.datasetKind, 'uninitialized');
  const bytes = await readFile(output, 'utf8');
  await assert.rejects(prepareSite({ output, production: true, now: NOW }), /INITIALIZATION_REQUIRED/);
  assert.equal(await readFile(output, 'utf8'), bytes);
  assert.throws(() => assertDeployable(fixture(), NOW));
  assert.throws(() => assertDeployable(official(), NOW + MAX_STALE + 1), /EXPIRED/);
  assert.throws(() => assertDeployable(official(), Date.parse('2026-12-31T15:00:00Z')), /EXPIRED/);
  assert.equal(assertDeployable(official(), NOW).years[2026].lastSuccessfulFetchAt, '2026-10-11T00:00:00.000Z');
});

test('document rebuild reads exact prior success time without collecting; missing store blocks before collection', async () => {
  await mkdir(artifacts, { recursive: true });
  const directory = await mkdtemp(join(artifacts, 'workflow-'));
  let calls = 0;
  const store = { read: async () => ({ sha: 'a'.repeat(40), data: official() }) };
  const result = await prepareWorkflow({ action: 'reuse', directory, store, now: NOW, collect: async () => { calls++; } });
  assert.deepEqual(result, { persist: false, deploy: true, data_sha: 'a'.repeat(40) }); assert.equal(calls, 0);
  assert.equal(JSON.parse(await readFile(join(directory, 'previous.json'))).years[2026].lastSuccessfulFetchAt, '2026-10-11T00:00:00.000Z');
  await assert.rejects(prepareWorkflow({ action: 'collect', directory, store: { read: async () => { throw new Error('missing'); } }, collect: async () => { calls++; } }));
  assert.equal(calls, 0);
});


test('otherwise-valid oversized snapshots cannot replace durable data or public output', async () => {
  await mkdir(artifacts, { recursive: true });
  const base = await mkdtemp(join(artifacts, 'size-'));
  const remote = join(base, 'public-data.git'), checkout = join(base, 'source');
  async function git(args, cwd = base) { return (await execute('git', args, { cwd, windowsHide: true })).stdout.trim(); }
  await git(['init', '--bare', remote]); await mkdir(checkout); await git(['init'], checkout);
  await git(['remote', 'add', 'origin', remote], checkout);
  const store = gitStore(checkout), file = join(base, 'candidate.json'), output = join(base, 'site.json');
  await writeFile(file, JSON.stringify(official()));
  const first = await store.save({ file, initialize: true });
  await prepareSite({ source: file, production: true, output, now: NOW });
  const before = await readFile(output, 'utf8');
  const oversized = official();
  for (const year of [2026, 2027]) {
    oversized.years[year].holidays = [];
    for (let month = 1; month <= 12; month++) {
      const mm = String(month).padStart(2, '0');
      oversized.years[year].monthResults[month - 1].rawCount = 300;
      oversized.years[year].monthResults[month - 1].pages = 3;
      for (let sequence = 1; sequence <= 300; sequence++) oversized.years[year].holidays.push({
        date: year + '-' + mm + '-01', name: String(sequence).padStart(4, '0'), source: 'official', category: 'public', sourceId: 'kasi:' + year + mm + '01:' + sequence,
      });
    }
  }
  // All dates, order, names, counts and pages satisfy the contract before the
  // names are expanded, and remain semantically valid after expansion.
  validateDataset(oversized, { production: true });
  for (const year of oversized.targetYears) for (const holiday of oversized.years[year].holidays) holiday.name = '가'.repeat(45) + holiday.name;
  assert.ok(Buffer.byteLength(JSON.stringify(oversized, null, 2) + '\n') > MAX_DATA_BYTES);
  assert.throws(() => validateDataset(oversized, { production: true }), error => error.code === 'CALENDAR_SCHEMA_INVALID');
  await writeFile(file, JSON.stringify(oversized));
  await assert.rejects(store.save({ file, expectedSha: first }));
  assert.equal(await store.current(), first);
  assert.equal(await git(['rev-list', '--count', '--all'], remote), '1');
  assert.deepEqual((await store.read()).data, official());
  await assert.rejects(prepareSite({ source: file, production: true, output, now: NOW }));
  assert.equal(await readFile(output, 'utf8'), before);
});
