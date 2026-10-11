import test from 'node:test';
import assert from 'node:assert/strict';
import { HolidayClient } from '../../../docs/assets/calendar/holiday-client.mjs';
import { emptyDataset, TTL, MAX_STALE } from '../../../docs/assets/calendar/contract.mjs';

const NOW = Date.parse('2026-10-11T03:00:00.000Z');
function fixture(at = NOW) {
  const data = emptyDataset(NOW); data.datasetKind = 'fixture';
  for (const year of data.targetYears) data.years[year] = {
    year, status: 'ready', complete: true, lastSuccessfulFetchAt: new Date(at).toISOString(), snapshotId: 'fixture-' + year,
    monthResults: Array.from({ length: 12 }, (_, i) => ({ month: i + 1, rawCount: i === 0 ? 1 : 0, pages: 1, status: 'success' })),
    holidays: [{ date: year + '-01-01', name: '가상 테스트 휴일', source: 'official', category: 'public', sourceId: 'kasi:' + year + '0101:1' }],
    warnings: ['검증용 가상 자료입니다.'],
  };
  return data;
}
const reply = data => new Response(JSON.stringify(data), { headers: { 'Content-Type': 'application/json' } });

test('static loader reads only its relative public JSON and exposes an immutable fixture snapshot', async () => {
  const client = new HolidayClient();
  const result = await client.load(2027, async (url, options) => {
    assert.ok(String(url).endsWith('/docs/assets/calendar/data/calendar.json'));
    assert.equal(new URL(url).search, '');
    assert.equal(options.credentials, 'omit'); assert.equal(options.cache, 'no-cache');
    assert.deepEqual(Object.keys(options).sort(), ['cache', 'credentials', 'signal']);
    return reply(fixture());
  }, NOW);
  assert.equal(result.snapshot.status, 'ready'); assert.equal(result.snapshot.mock, true);
  assert.equal(result.snapshot.fetchedAt, '2026-10-11T03:00:00.000Z');
  assert.ok(Object.isFrozen(result.snapshot)); assert.ok(Object.isFrozen(result.snapshot.holidays[0]));
});

test('missing, malformed, and unavailable JSON never become an empty ready snapshot', async () => {
  for (const response of [new Response('', { status: 404 }), new Response('<html>error</html>'), reply({ schemaVersion: 9 }), reply(emptyDataset(NOW))]) {
    const result = await new HolidayClient().load(2027, async () => response, NOW);
    assert.ok(result.error); assert.equal(result.snapshot, undefined);
  }
});

test('invalid complete year and partial months are rejected', async () => {
  const zero = fixture(); zero.years[2027].holidays = [];
  const partial = fixture(); partial.years[2027].monthResults.pop();
  for (const data of [zero, partial]) {
    const result = await new HolidayClient().load(2027, async () => reply(data), NOW);
    assert.ok(result.error); assert.equal(result.snapshot, undefined);
  }
});

test('network failure and oversized JSON return safe errors without upstream details', async () => {
  const result = await new HolidayClient().load(2027, async () => { throw new Error('private transport detail'); }, NOW);
  assert.ok(result.error); assert.ok(!JSON.stringify(result).includes('private transport detail'));
  const large = new Response('{}', { headers: { 'Content-Length': String(3 * 1024 * 1024) } });
  assert.ok((await new HolidayClient().load(2027, async () => large, NOW)).error);
});

test('current re-evaluates 24-hour freshness and 30-day upper bound after page remains open', async () => {
  const client = new HolidayClient();
  await client.load(2027, async () => reply(fixture()), NOW);
  assert.equal(client.current(2027, NOW + TTL - 1).snapshot.status, 'ready');
  assert.equal(client.current(2027, NOW + TTL).snapshot.status, 'stale');
  assert.equal(client.current(2027, NOW + MAX_STALE).snapshot.status, 'stale');
  assert.equal(client.current(2027, NOW + MAX_STALE + 1).error.code, 'CALENDAR_DATA_EXPIRED');
});

test('preserved snapshots require stale consent even before 24 hours', async () => {
  const data = fixture(); data.years[2027].status = 'preserved';
  const result = await new HolidayClient().load(2027, async () => reply(data), NOW);
  assert.equal(result.snapshot.status, 'stale');
  assert.equal(result.snapshot.fetchedAt, data.years[2027].lastSuccessfulFetchAt);
});

test('unsupported year and Seoul year boundary are re-evaluated', async () => {
  const client = new HolidayClient();
  await client.load(2027, async () => reply(fixture()), NOW);
  assert.equal(client.current(1900, NOW).error.code, 'CALENDAR_YEAR_UNSUPPORTED');
  assert.equal(client.current(2026, Date.parse('2026-12-31T15:00:00.000Z')).error.code, 'CALENDAR_YEAR_UNSUPPORTED');
});

test('future success timestamps are rejected', async () => {
  const result = await new HolidayClient().load(2027, async () => reply(fixture(NOW + 3600000)), NOW);
  assert.equal(result.error.code, 'CALENDAR_SCHEMA_INVALID');
});

test('a late previous-year response cannot replace the latest dataset', async () => {
  const client = new HolidayClient(); let release;
  const old = client.load(2026, () => new Promise(resolve => { release = resolve; }), NOW);
  const current = await client.load(2027, async () => reply(fixture()), NOW);
  release(reply(fixture(NOW - TTL * 2)));
  assert.deepEqual(await old, { obsolete: true });
  assert.equal(client.current(2027, NOW).snapshot.snapshotId, current.snapshot.snapshotId);
  assert.equal(client.current(2027, NOW).snapshot.status, 'ready');
});

test('invalidation while response body is pending ignores late JSON', async () => {
  const client = new HolidayClient(); let release, bodyStarted;
  const started = new Promise(resolve => { bodyStarted = resolve; });
  const loading = client.load(2027, async () => ({ ok: true, headers: new Headers(), text() { bodyStarted(); return new Promise(resolve => { release = resolve; }); } }), NOW);
  await started; client.invalidate(); release(JSON.stringify(fixture()));
  assert.deepEqual(await loading, { obsolete: true }); assert.equal(client.dataset, null);
});

test('reload failure does not silently reuse formerly ready client state', async () => {
  const client = new HolidayClient(); await client.load(2027, async () => reply(fixture()), NOW);
  await client.load(2027, async () => new Response('', { status: 503 }), NOW);
  assert.equal(client.current(2027, NOW).error.code, 'CALENDAR_DATA_UNAVAILABLE');
});
