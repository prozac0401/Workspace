import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { validateDataset, emptyDataset, selectYear, targetYears, currentSeoulYear, MIN_YEAR, MAX_YEAR, DAY_MS, FRESH_DAYS, MAX_DAYS, TTL, MAX_STALE } from '../../../docs/assets/calendar/contract.mjs';
import { fixture, NOW } from './fixtures/helpers.mjs';
test('strict schema/version/extra-field checks, complete months/counts, dates and production fixture guard', async () => {
  const schema = JSON.parse(await readFile(new URL('../calendar.schema.json', import.meta.url)));
  assert.equal(schema.properties.schemaVersion.const, 2);
  assert.equal(validateDataset(fixture()).datasetKind, 'fixture');
  assert.throws(() => validateDataset(fixture(), { production: true }));
  assert.throws(() => validateDataset(emptyDataset(NOW), { production: true }));
  const mutations = [d => d.schemaVersion = 1, d => d.schemaVersion = 3, d => d.extra = 'secret', d => d.source.extra = 1, d => d.years[2027].holidays[0].raw = {}, d => d.years[2027].monthResults.pop(), d => d.years[2027].monthResults[1].month = 1, d => d.years[2027].monthResults[0].rawCount = 0, d => d.years[2027].holidays = [], d => d.years[2027].holidays[0].date = '2027-02-29', d => d.years[2027].holidays[0].name = 'x\n', d => d.years[2027].holidays.push(d.years[2027].holidays[0]), d => d.years[2027].lastSuccessfulFetchAt = '2026-99-11T00:00:00.000Z', d => d.years[2027].snapshotId = 'https://secret', d => d.years[2027].holidays[0].sourceId = 'kasi:secret', d => d.targetYears = [2026, 2028], d => d.supportedYears.reverse(), d => delete d.years[MIN_YEAR]];
  for (const mutate of mutations) { const data = fixture(); mutate(data); assert.throws(() => validateDataset(data), e => e.code === 'CALENDAR_SCHEMA_INVALID'); }
});
test('32d stale, explicit failure preserved stale, 35d hard expiry and immutable snapshot', () => {
  const data = fixture();
  assert.equal(DAY_MS, 86_400_000); assert.equal(FRESH_DAYS, 32); assert.equal(MAX_DAYS, 35);
  assert.equal(TTL, 32 * DAY_MS); assert.equal(MAX_STALE, 35 * DAY_MS);
  const ready = selectYear(data, 2027, NOW); assert.equal(ready.status, 'ready'); assert.equal(ready.mock, true); assert.equal(ready.fetchedAt, data.years[2027].lastSuccessfulFetchAt);
  assert.equal(ready.expiresAt, new Date(NOW + 32 * DAY_MS).toISOString());
  assert.throws(() => ready.holidays.push({}), TypeError);
  assert.equal(selectYear(data, 2027, NOW + TTL - 1).status, 'ready');
  assert.equal(selectYear(data, 2027, NOW + TTL).status, 'stale');
  assert.equal(selectYear(data, 2027, NOW + MAX_STALE - 1).status, 'stale');
  assert.equal(selectYear(data, 2027, NOW + MAX_STALE).status, 'stale');
  assert.throws(() => selectYear(data, 2027, NOW + MAX_STALE + 1), e => e.code === 'CALENDAR_DATA_EXPIRED');
  data.years[2027].status = 'preserved';
  const preserved = selectYear(data, 2027, NOW);
  assert.equal(preserved.status, 'stale');
  assert.equal(preserved.fetchedAt, ready.fetchedAt); assert.equal(preserved.expiresAt, ready.expiresAt);
  assert.throws(() => selectYear(data, 2027, NOW - 300001), e => e.code === 'CALENDAR_SCHEMA_INVALID');
});

test('monthly collection intervals of 28, 29, 30 and 31 days remain fresh', () => {
  for (const [from, to, days] of [
    ['2027-01-01T03:17:00.000Z', '2027-02-01T03:17:00.000Z', 31],
    ['2027-02-01T03:17:00.000Z', '2027-03-01T03:17:00.000Z', 28],
    ['2027-04-01T03:17:00.000Z', '2027-05-01T03:17:00.000Z', 30],
    ['2028-02-01T03:17:00.000Z', '2028-03-01T03:17:00.000Z', 29],
  ]) {
    const collected = Date.parse(from), nextRun = Date.parse(to);
    assert.equal(nextRun - collected, days * DAY_MS);
    assert.equal(selectYear(fixture(collected), 2027, nextRun).status, 'ready');
  }
});
test('fixed 1983..2099 support includes both endpoints across the Seoul year boundary', () => {
  const before = Date.parse('2026-12-31T14:59:59.999Z'), after = before + 1;
  assert.equal(MIN_YEAR, 1983); assert.equal(MAX_YEAR, 2099); assert.equal(targetYears().length, 117);
  assert.equal(currentSeoulYear(before), 2026); assert.equal(currentSeoulYear(after), 2027);
  assert.deepEqual(targetYears(before), targetYears(after));
  const data = fixture(before);
  for (const year of [1983, 2026, 2027, 2028, 2099]) assert.equal(selectYear(data, year, after).status, 'ready');
  for (const year of [1982, 2100, 2027.5, '2027']) assert.throws(() => selectYear(data, year, after), e => e.code === 'CALENDAR_YEAR_UNSUPPORTED');
  assert.throws(() => selectYear(emptyDataset(NOW), 2027, NOW), e => e.code === 'CALENDAR_DATA_UNAVAILABLE');
});
