import test from 'node:test';
import assert from 'node:assert/strict';
import { yearLayout, yearNumber, weekday, validDate, nextSeoulYear, isLeap } from '../../../docs/assets/calendar/date-core.mjs';
import { buildCalendar, validateManual, normalizeName } from '../../../docs/assets/calendar/calendar-model.mjs';
import { workbookParts, exportXlsx } from '../../../docs/assets/calendar/xlsx-exporter.mjs';
import { DAY_MS, TTL, MAX_STALE } from '../../../docs/assets/calendar/contract.mjs';
const NOW = Date.parse('2026-10-10T00:00:00Z');
const manualModel = (year = 2027, manual = []) => buildCalendar({ year, manual, mode: 'manual', manualApproved: true, generatedAt: '2026-10-10T00:00:00Z' });
test('AT01-03: every date and coordinate, 1900 through 2100, independently checked with UTC Date', () => {
  for (let y = 1900; y <= 2100; y++) {
    const months = yearLayout(y); assert.equal(months.length, 12); let count = 0; const seen = new Set();
    months.forEach((m, i) => {
      assert.ok(m.weeks >= 4 && m.weeks <= 6);
      if (i) assert.equal(m.startRow, months[i - 1].endRow + 2);
      for (const day of m.slots) if (day.date) {
        count++; assert.equal(day.weekday, new Date(Date.UTC(y, m.month - 1, day.dayNumber)).getUTCDay());
        assert.equal(day.excelColumn, day.weekday + 1); assert.ok(day.excelRow >= m.startRow + 2 && day.excelRow + 3 <= m.endRow);
        assert.equal(seen.has(day.date), false); seen.add(day.date);
      }
    });
    assert.equal(count, isLeap(y) ? 366 : 365);
  }
});
test('AT02: exact sample cells and 4/5/6 week months', () => {
  const [jan, feb] = yearLayout(2027);
  assert.equal(jan.weeks, 6); assert.equal(feb.weeks, 5); assert.equal(feb.startRow, 32);
  assert.equal(yearLayout(2015)[1].weeks, 4);
  assert.deepEqual(jan.slots.find(x => x.dayNumber === 1), { date: '2027-01-01', dayNumber: 1, weekday: 5, excelRow: 7, excelColumn: 6 });
  assert.equal(jan.slots.find(x => x.dayNumber === 31).excelRow, 27);
});
test('AT03: leap centuries, strict input, Seoul next year boundary', () => {
  for (const year of [1900, 2100]) assert.equal(validDate(`${year}-02-29`), false);
  for (const year of [2000, 2028]) assert.equal(validDate(`${year}-02-29`), true);
  for (const input of ['2027.0', '2027x', ' 2027', '1e3', '', 1899, 2101, null]) assert.throws(() => yearNumber(input));
  assert.equal(validDate('2027-2-01'), false); assert.equal(validDate('2027-04-31'), false);
  assert.equal(nextSeoulYear(new Date('2026-12-31T14:59:59Z')), 2027);
  assert.equal(nextSeoulYear(new Date('2026-12-31T15:00:00Z')), 2028);
  assert.equal(weekday(2027, 1, 1), 5);
});
test('AT10: manual names, dates, duplicates, maximum and edit identity', () => {
  const base = { date: '2027-03-01', name: '  회사 휴일  ', category: 'company' };
  const item = validateManual(base, 2027); assert.equal(item.name, '회사 휴일');
  assert.throws(() => validateManual(base, 2027, [item]));
  assert.equal(validateManual({ ...base, category: 'personal' }, 2027, [item]).category, 'personal');
  assert.equal(validateManual(base, 2027, [item], item.sourceId).sourceId, item.sourceId);
  for (const name of ['', ' ', 'a\nb', 'a\tb', '\u0000', '가'.repeat(51), '\u202ex', '\ufffe', '\uffff']) assert.throws(() => normalizeName(name));
  assert.equal(normalizeName('가'.repeat(50)).length, 50);
  assert.throws(() => validateManual({ ...base, date: '2028-03-01' }, 2027));
  assert.throws(() => validateManual({ ...base, date: '2027-02-29' }, 2027));
  assert.throws(() => validateManual({ ...base, category: 'public' }, 2027));
  const hundred = Array.from({ length: 100 }, (_, i) => ({ ...item, name: `휴일${i}`, sourceId: String(i) }));
  assert.throws(() => validateManual(base, 2027, hundred));
});
const snapshot = holidays => ({ year: 2027, snapshotId: 'test', status: 'ready', complete: true, fetchedAt: '2026-10-10T00:00:00Z', expiresAt: new Date(NOW + TTL).toISOString(), holidays,
  monthResults: Array.from({ length: 12 }, (_, i) => ({ month: i + 1, status: 'success' })), warnings: [] });
test('AT05/09: stable ordering, same-name dedup with source preservation, holiday color priorities and frozen model', () => {
  const records = [ { date: '2027-01-02', name: '겹침', source: 'official', category: 'public', sourceId: 'a' }, { date: '2027-01-02', name: '가나다', source: 'official', category: 'public', sourceId: 'b' } ];
  const manual = [validateManual({ date: '2027-01-02', name: '겹침', category: 'company' }, 2027), validateManual({ date: '2027-01-04', name: '개인 일정', category: 'personal' }, 2027)];
  const model = buildCalendar({ year: 2027, mode: 'ready', snapshot: snapshot(records), manual, now: NOW });
  const days = model.months[0].slots;
  const second = days.find(d => d.dayNumber === 2); assert.equal(second.styleToken, 'red');
  assert.deepEqual(second.labels, ['가나다', '겹침']); assert.equal(second.sources.length, 3);
  assert.equal(days.find(d => d.dayNumber === 3).styleToken, 'red');
  assert.equal(days.find(d => d.dayNumber === 4).styleToken, 'purple');
  assert.equal(days.find(d => d.dayNumber === 9).styleToken, 'blue');
  assert.ok(Object.isFrozen(model.months[0].slots[0])); assert.throws(() => { model.mode = 'manual'; });
  records[0].name = 'changed'; assert.equal(second.labels[1], '겹침');
});
test('AT05: long names grow a week uniformly; excessive names explicitly block export', () => {
  const long = validateManual({ date: '2027-01-01', name: '가'.repeat(50), category: 'company' }, 2027);
  const model = manualModel(2027, [long]); assert.ok(model.months[0].weekHeights[0] > 100);
  const crowded = Array.from({ length: 12 }, (_, i) => ({ ...long, name: '가'.repeat(48) + i, sourceId: String(i) }));
  assert.throws(() => manualModel(2027, crowded), /2027-01-01.*409pt/);
});
test('AT08: explicit manual/stale consent and complete snapshots are enforced', () => {
  assert.throws(() => buildCalendar({ year: 2027 }));
  const s = snapshot([{ date: '2027-01-01', name: 'test', source: 'official' }]); s.status = 'stale';
  assert.throws(() => buildCalendar({ year: 2027, mode: 'stale', snapshot: s, now: NOW }));
  assert.equal(buildCalendar({ year: 2027, mode: 'stale', snapshot: s, staleApproved: true, now: NOW }).mode, 'stale');
  s.complete = false; assert.throws(() => buildCalendar({ year: 2027, mode: 'stale', snapshot: s, staleApproved: true, now: NOW }));
  assert.throws(() => buildCalendar({ year: 2027, mode: 'ready', snapshot: snapshot([]), now: NOW }));
});
test('AT04/11/12: OOXML has 1 sheet, exact blank cells, inline text, 15 title merges and 11 breaks', () => {
  const manual = ['=SUM(A1:A2)', '+1', '-1', '@test', '<img src=x>', '_x0041_'].map((name, i) => validateManual({ date: `2027-01-0${i + 1}`, name, category: 'company' }, 2027));
  const model = manualModel(2027, manual), parts = workbookParts(model), sheet = parts['xl/worksheets/sheet1.xml'];
  assert.equal((parts['xl/workbook.xml'].match(/<sheet /g) || []).length, 1);
  assert.equal((sheet.match(/<mergeCell /g) || []).length, 15);
  assert.equal((sheet.match(/<brk /g) || []).length, 11);
  assert.match(sheet, /<brk id="31"/); assert.match(sheet, /orientation="portrait" fitToWidth="1" fitToHeight="0"/);
  for (const month of model.months) for (const day of month.slots) {
    const col = String.fromCharCode(64 + day.excelColumn);
    for (let b = 1; b <= 3; b++) assert.match(sheet, new RegExp(`<c r="${col}${day.excelRow + b}" s="\\d+"/>`));
  }
  assert.equal(Object.values(parts).some(x => /<f[ >]|sheetProtection|externalLink|vbaProject|connections/.test(x)), false);
  assert.match(sheet, /&lt;img src=x&gt;/); assert.match(sheet, /_x005F_x0041_/);
  const bytes = exportXlsx(model); assert.equal(bytes[0], 0x50); assert.equal(bytes[1], 0x4b);
});
test('normalized manual snapshot preserves identities, category provenance, and formula-like literal names', () => {
  const manual = [
    { date: '2027-01-04', name: '  e\u0301  ', category: 'company', sourceId: 'manual:company' },
    { date: '2027-01-04', name: 'é', category: 'personal', sourceId: 'manual:personal' },
  ];
  assert.throws(() => validateManual({ ...manual[0], name: 'é' }, 2027, manual));
  const model = manualModel(2027, manual);
  assert.deepEqual(model.manual.map(x => x.name), ['é', 'é']);
  assert.deepEqual(model.manual.map(x => x.sourceId), ['manual:company', 'manual:personal']);
  assert.ok(model.manual.every(x => x.source === 'manual'));
  const day = model.months[0].slots.find(x => x.date === '2027-01-04');
  assert.equal(day.labels.length, 1);
  assert.equal(day.sources.length, 2);
  assert.deepEqual(day.sources.map(x => x.category), ['company', 'personal']);
  manual[0].name = 'changed'; assert.equal(day.sources[0].name, 'é');
  assert.throws(() => { model.manual[0].name = 'changed'; });
});

test('freshness is evaluated from real collection time, not a ready label or claimed expiry', () => {
  const s = snapshot([{ date: '2027-01-01', name: '모의 신정', source: 'official' }]);
  for (const days of [28, 29, 30, 31]) assert.equal(buildCalendar({ year: 2027, mode: 'ready', snapshot: s, now: NOW + days * DAY_MS }).mode, 'ready');
  assert.equal(buildCalendar({ year: 2027, mode: 'ready', snapshot: s, now: NOW + TTL - 1 }).mode, 'ready');
  assert.throws(() => buildCalendar({ year: 2027, mode: 'ready', snapshot: s, now: NOW + TTL }), /32일/);
  s.expiresAt = '2099-01-01T00:00:00Z';
  assert.throws(() => buildCalendar({ year: 2027, mode: 'ready', snapshot: s, now: NOW + TTL + 1 }), /32일/);
  s.status = 'stale';
  assert.throws(() => buildCalendar({ year: 2027, mode: 'stale', snapshot: s, now: NOW + TTL }), /이전 자료 사용/);
  assert.equal(buildCalendar({ year: 2027, mode: 'stale', snapshot: s, staleApproved: true, now: NOW + TTL }).mode, 'stale');
  assert.equal(buildCalendar({ year: 2027, mode: 'stale', snapshot: s, staleApproved: true, now: NOW + MAX_STALE - 1 }).mode, 'stale');
  assert.equal(buildCalendar({ year: 2027, mode: 'stale', snapshot: s, staleApproved: true, now: NOW + MAX_STALE }).mode, 'stale');
  assert.throws(() => buildCalendar({ year: 2027, mode: 'stale', snapshot: s, staleApproved: true, now: NOW + MAX_STALE + 1 }), /35일/);
  assert.throws(() => buildCalendar({ year: 2027, mode: 'stale', snapshot: s, staleApproved: true, now: NOW - 5 * 60 * 1000 - 1 }), /수집 시각/);
  s.fetchedAt = 'not-a-date';
  assert.throws(() => buildCalendar({ year: 2027, mode: 'stale', snapshot: s, staleApproved: true, now: NOW }), /수집 시각/);
});

test('fixture provenance and canonical success time appear in workbook metadata', () => {
  const s = snapshot([{ date: '2027-01-01', name: '모의 신정', source: 'official' }]);
  s.datasetKind = 'fixture'; s.lastSuccessfulFetchAt = s.fetchedAt;
  const model = buildCalendar({ year: 2027, mode: 'ready', snapshot: s, now: NOW, generatedAt: '2026-10-10T01:00:00Z' });
  assert.equal(model.isMock, true);
  assert.match(model.metadataText, /모의 테스트 자료/);
  assert.match(model.metadataText, /KST/);
  assert.match(workbookParts(model)['xl/worksheets/sheet1.xml'], /모의 테스트 자료/);
});

test('calendar date coordinates do not move between process timezones', () => {
  const previous = process.env.TZ;
  try {
    const baseline = JSON.stringify(yearLayout(2028));
    for (const zone of ['UTC', 'Asia/Seoul', 'America/Los_Angeles', 'Pacific/Kiritimati']) {
      process.env.TZ = zone;
      assert.equal(JSON.stringify(yearLayout(2028)), baseline);
    }
  } finally {
    if (previous === undefined) delete process.env.TZ; else process.env.TZ = previous;
  }
});
