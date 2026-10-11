import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { validateDataset, emptyDataset, selectYear, targetYears, TTL, MAX_STALE } from '../../../docs/assets/calendar/contract.mjs';
import { fixture, NOW } from './fixtures/helpers.mjs';
test('strict schema/version/extra-field checks, complete months/counts, dates and production fixture guard', async () => {
  const schema = JSON.parse(await readFile(new URL('../calendar.schema.json', import.meta.url)));
  assert.equal(schema.properties.schemaVersion.const, 1);
  assert.equal(validateDataset(fixture()).datasetKind, 'fixture');
  assert.throws(() => validateDataset(fixture(), { production: true }));
  assert.throws(() => validateDataset(emptyDataset(NOW), { production: true }));
  const mutations = [d => d.schemaVersion = 2, d => d.extra = 'secret', d => d.source.extra = 1, d => d.years[2027].holidays[0].raw = {}, d => d.years[2027].monthResults.pop(), d => d.years[2027].monthResults[1].month = 1, d => d.years[2027].monthResults[0].rawCount = 0, d => d.years[2027].holidays = [], d => d.years[2027].holidays[0].date = '2027-02-29', d => d.years[2027].holidays[0].name = 'x\n', d => d.years[2027].holidays.push(d.years[2027].holidays[0]), d => d.years[2027].lastSuccessfulFetchAt = '2026-99-11T00:00:00.000Z', d => d.years[2027].snapshotId = 'https://secret', d => d.years[2027].holidays[0].sourceId = 'kasi:secret', d => d.targetYears = [2026, 2028]];
  for (const mutate of mutations) { const data = fixture(); mutate(data); assert.throws(() => validateDataset(data), e => e.code === 'CALENDAR_SCHEMA_INVALID'); }
});
test('24h stale, explicit failure preserved stale, 30d hard expiry and immutable snapshot', () => {
  const data = fixture();
  const ready = selectYear(data, 2027, NOW); assert.equal(ready.status, 'ready'); assert.equal(ready.mock, true); assert.equal(ready.fetchedAt, data.years[2027].lastSuccessfulFetchAt);
  assert.throws(() => ready.holidays.push({}), TypeError);
  assert.equal(selectYear(data, 2027, NOW + TTL - 1).status, 'ready');
  assert.equal(selectYear(data, 2027, NOW + TTL).status, 'stale');
  assert.equal(selectYear(data, 2027, NOW + MAX_STALE).status, 'stale');
  assert.throws(() => selectYear(data, 2027, NOW + MAX_STALE + 1), e => e.code === 'CALENDAR_DATA_EXPIRED');
  data.years[2027].status = 'preserved'; assert.equal(selectYear(data, 2027, NOW).status, 'stale');
  assert.throws(() => selectYear(data, 2027, NOW - 300001), e => e.code === 'CALENDAR_SCHEMA_INVALID');
});
test('Seoul year boundary: default targets and old envelopes cannot grant historic support', () => {
  const before = Date.parse('2026-12-31T14:59:59.999Z'), after = before + 1;
  assert.deepEqual(targetYears(before), [2026, 2027]); assert.deepEqual(targetYears(after), [2027, 2028]);
  const data = fixture(before);
  assert.throws(() => selectYear(data, 2026, after), e => e.code === 'CALENDAR_YEAR_UNSUPPORTED');
  assert.equal(selectYear(data, 2027, after).status, 'ready');
  assert.throws(() => selectYear(data, 2028, after), e => e.code === 'CALENDAR_DATA_UNAVAILABLE');
  assert.throws(() => selectYear(emptyDataset(NOW), 2027, NOW), e => e.code === 'CALENDAR_DATA_UNAVAILABLE');
});
