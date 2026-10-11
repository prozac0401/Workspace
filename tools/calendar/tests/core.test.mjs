import test from 'node:test';
import assert from 'node:assert/strict';
import { yearLayout, yearNumber, weekday, validDate, nextSeoulYear, isLeap } from '../../../docs/assets/calendar/date-core.mjs';
import { buildCalendar, validateManual, normalizeName, holidayDisplayName } from '../../../docs/assets/calendar/calendar-model.mjs';
import { workbookParts, exportXlsx } from '../../../docs/assets/calendar/xlsx-exporter.mjs';
import { DAY_MS, TTL, MAX_STALE } from '../../../docs/assets/calendar/contract.mjs';
import { DEFAULT_FORMATTING, normalizeFormatting } from '../../../docs/assets/calendar/formatting.mjs';
const NOW = Date.parse('2026-10-10T00:00:00Z');
const manualModel = (year = 2027, manual = []) => buildCalendar({ year, manual, mode: 'manual', manualApproved: true, generatedAt: '2026-10-10T00:00:00Z' });
const cellXml = (sheet, day) => {
  const ref = String.fromCharCode(64 + day.excelColumn) + day.excelRow;
  return sheet.match(new RegExp(`<c r="${ref}"[^>]*>[\\s\\S]*?</c>`))[0];
};
const inlineText = xml => [...xml.matchAll(/<t(?: [^>]*)?>([\s\S]*?)<\/t>/g)].map(([, text]) => text
  .replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&apos;', "'").replaceAll('&amp;', '&')
  .replace(/_x([0-9a-f]{4})_/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)))).join('');
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
test('official Christmas display aliases reach preview and OOXML while original sources and manual names stay intact', () => {
  const records = [
    { date: '2027-12-25', name: '기독탄신일', source: 'official', category: 'public', sourceId: 'fixture:christmas' },
    { date: '2027-12-25', name: '하늘휴일', source: 'official', category: 'public', sourceId: 'fixture:unchanged-last' },
    { date: '2027-12-25', name: '나눔휴일', source: 'official', category: 'public', sourceId: 'fixture:unchanged-first' },
    { date: '2027-12-27', name: '대체공휴일(기독탄신일)', source: 'official', category: 'public', sourceId: 'fixture:substitute' },
  ];
  const manual = [
    validateManual({ date: '2027-12-25', name: '크리스마스', category: 'company', sourceId: 'manual:same-display' }, 2027),
    validateManual({ date: '2027-12-25', name: '가가 수동', category: 'personal', sourceId: 'manual:sort-after-official' }, 2027),
    validateManual({ date: '2027-12-26', name: '기독탄신일', category: 'personal', sourceId: 'manual:original-name' }, 2027),
  ];
  const s = { ...snapshot(records), datasetKind: 'fixture', lastSuccessfulFetchAt: '2026-10-10T00:00:00.000Z' };
  const original = structuredClone(s);
  const model = buildCalendar({ year: 2027, snapshot: s, manual, mode: 'ready', now: NOW });
  const days = model.months[11].slots;
  const christmas = days.find(day => day.date === '2027-12-25');
  const personal = days.find(day => day.date === '2027-12-26');
  const substitute = days.find(day => day.date === '2027-12-27');
  assert.deepEqual(christmas.labels, ['나눔휴일', '크리스마스', '하늘휴일', '[개인] 가가 수동']);
  assert.equal(christmas.sources.length, 5); // Same display label retains both official and manual provenance.
  assert.deepEqual(personal.labels, ['[개인] 기독탄신일']);
  assert.deepEqual(substitute.labels, ['대체공휴일(크리스마스)']);
  assert.equal(holidayDisplayName(records[0]), '크리스마스');
  assert.equal(holidayDisplayName(records[3]), '대체공휴일(크리스마스)');
  assert.equal(holidayDisplayName(records[1]), '하늘휴일');
  assert.equal(holidayDisplayName(manual[2]), '기독탄신일');
  assert.deepEqual(s, original); assert.deepEqual(model.snapshot, original); assert.deepEqual(model.manual, manual);
  const actualSources = new Map(days.flatMap(day => day.sources).map(item => [item.sourceId, item]));
  assert.deepEqual(actualSources, new Map([...records, ...manual].map(item => [item.sourceId, item])));
  const sheet = workbookParts(model)['xl/worksheets/sheet1.xml'];
  for (const day of [christmas, personal, substitute]) {
    const ref = String.fromCharCode(64 + day.excelColumn) + day.excelRow;
    const xml = sheet.match(new RegExp(`<c r="${ref}"[^>]*>[\\s\\S]*?</c>`))[0];
    assert.ok(xml.includes(day.displayText), ref);
    if (day !== personal) assert.doesNotMatch(xml, /기독탄신일/);
  }
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
test('AT04/11/12: OOXML has 1 sheet, exact blank cells, hidden empty leading rows, 12 month merges and 11 breaks', () => {
  const manual = ['=SUM(A1:A2)', '+1', '-1', '@test', '<img src=x>', '_x0041_'].map((name, i) => validateManual({ date: `2027-01-0${i + 1}`, name, category: 'company' }, 2027));
  const model = manualModel(2027, manual), parts = workbookParts(model), sheet = parts['xl/worksheets/sheet1.xml'];
  assert.equal((parts['xl/workbook.xml'].match(/<sheet /g) || []).length, 1);
  assert.equal((sheet.match(/<mergeCell /g) || []).length, 12);
  for (let row = 1; row <= 4; row++) {
    assert.match(sheet, new RegExp(`<row r="${row}" hidden="1" ht="0" customHeight="1"/>`));
    assert.doesNotMatch(sheet, new RegExp(`<c r="[A-G]${row}"`));
  }
  assert.ok(parts['xl/workbook.xml'].includes("'2027년 달력'!$A$5:$G$291"));
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
  const parts = workbookParts(model);
  assert.match(parts['docProps/core.xml'], /모의 테스트 자료/);
  assert.ok(parts['docProps/core.xml'].includes(model.metadataText));
  assert.ok(parts['docProps/core.xml'].includes(model.legendText));
  assert.match(parts['docProps/core.xml'], /2026-10-10T01:00:00Z/);
  assert.doesNotMatch(parts['xl/worksheets/sheet1.xml'], /모의 테스트 자료|자료:|생성:|자동 갱신/);
});

test('format settings reject unknown or unsafe inputs and enforce numeric and font limits', () => {
  assert.deepEqual(normalizeFormatting(), DEFAULT_FORMATTING);
  assert.ok(Object.isFrozen(DEFAULT_FORMATTING));
  for (const bad of [null, [], 'red', { unknown: true }, { fontFamily: 'url(https://example.test)' },
    { fontSize: '10' }, { fontSize: 7 }, { fontSize: 17 }, { fontSize: 10.5 },
    { lunarFontSize: '7' }, { lunarFontSize: 5 }, { lunarFontSize: 17 }, { lunarFontSize: 7.5 },
    { titleSize: 13 }, { titleSize: 25 }, { writingRowHeight: 15 }, { writingRowHeight: 33 },
    { textColor: '#fff' }, { lunarColor: '#777' }, { lunarColor: 'gray' }, { lunarColor: null },
    { background: 'red' }, { titleColor: '#FFFFFF; color:red' }, { borderColor: null }]) {
    assert.throws(() => normalizeFormatting(bad));
    assert.throws(() => buildCalendar({ year: 2027, mode: 'manual', manualApproved: true, formatting: bad }));
  }
  for (const fontFamily of ['맑은 고딕', 'Arial', '바탕']) {
    assert.equal(normalizeFormatting({ fontFamily, fontSize: 8, titleSize: 14, writingRowHeight: 16 }).fontFamily, fontFamily);
  }
});

test('one immutable custom format drives OOXML font, colors, row height and conservative name wrapping', () => {
  const format = { fontFamily: 'Arial', fontSize: 16, titleSize: 24, writingRowHeight: 32,
    textColor: '#112233', holidayColor: '#224466', saturdayColor: '#335577', manualColor: '#446688',
    titleColor: '#aabbcc', titleBackground: '#556677', weekdayBackground: '#667788',
    background: '#778899', outsideBackground: '#8899aa', borderColor: '#99aabb' };
  const manual = [validateManual({ date: '2027-01-01', name: '가'.repeat(30), category: 'company' }, 2027)];
  const model = buildCalendar({ year: 2027, mode: 'manual', manualApproved: true, manual, formatting: format });
  const normal = manualModel(2027, manual);
  assert.deepEqual(normal.formatting, DEFAULT_FORMATTING);
  assert.deepEqual(model.formatting, normalizeFormatting(format));
  assert.ok(Object.isFrozen(model.formatting));
  assert.throws(() => { model.formatting.fontSize = 8; });
  assert.match(model.legendText, /일요일·공식 휴일 #224466 \/ 토요일 #335577 \/ 수동 일정 #446688/);
  assert.ok(model.months[0].weekHeights[0] > normal.months[0].weekHeights[0]);
  const parts = workbookParts(model), style = parts['xl/styles.xml'];
  assert.match(style, /<sz val="16"/); assert.match(style, /<sz val="24"/);
  assert.match(style, /<name val="Arial"/); assert.doesNotMatch(style, /맑은 고딕/);
  for (const value of Object.values(format).filter(value => typeof value === 'string' && value.startsWith('#'))) {
    assert.ok(style.includes('FF' + value.slice(1).toUpperCase()), value);
  }
  assert.match(parts['xl/worksheets/sheet1.xml'], /<row r="8" ht="32"/);
  format.fontSize = 8; format.textColor = '#FFFFFF';
  assert.equal(model.formatting.fontSize, 16); assert.equal(model.formatting.textColor, '#112233');
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

test('lunar display is optional, strictly boolean and limited without narrowing the Gregorian calendar', () => {
  const options = { year: 2027, mode: 'manual', manualApproved: true, generatedAt: '2026-10-10T00:00:00Z' };
  const implicit = buildCalendar(options), explicit = buildCalendar({ ...options, showLunar: false });
  assert.deepEqual(implicit, explicit);
  assert.equal(implicit.config.showLunar, false);
  assert.ok(implicit.months.flatMap(month => month.slots).every(day => day.lunar === null));
  assert.doesNotMatch(implicit.metadataText, /음력:/);
  for (const showLunar of [null, 0, 1, 'true', 'false', {}, []]) assert.throws(() => buildCalendar({ ...options, showLunar }), /음력 표시 여부/);
  for (const year of [1983, 2050]) assert.equal(buildCalendar({ ...options, year, showLunar: true }).config.showLunar, true);
  for (const year of [1982, 2051, 2099]) assert.throws(() => buildCalendar({ ...options, year, showLunar: true }), /1983~2050/);
  assert.equal(buildCalendar({ ...options, year: 2099 }).config.year, 2099);
});

test('lunar first lines share the immutable preview/export model, preserve names and leave all writing cells blank', () => {
  const manual = [validateManual({ date: '2027-01-04', name: '개인 일정', category: 'personal' }, 2027)];
  const options = { year: 2027, mode: 'manual', manualApproved: true, manual, generatedAt: '2026-10-10T00:00:00Z' };
  const normal = buildCalendar(options), model = buildCalendar({ ...options, showLunar: true, formatting: { fontSize: 16 } });
  const parts = workbookParts(model), sheet = parts['xl/worksheets/sheet1.xml'];
  assert.ok(Object.isFrozen(model.config));
  assert.match(parts['docProps/core.xml'], /음력: 한국 음력 변환표/);
  assert.doesNotMatch(sheet, /한국 음력 변환표/);
  let count = 0;
  for (let month = 0; month < 12; month++) for (let slot = 0; slot < model.months[month].slots.length; slot++) {
    const day = model.months[month].slots[slot], original = normal.months[month].slots[slot];
    assert.deepEqual(day.labels, original.labels); assert.deepEqual(day.sources, original.sources);
    assert.equal(day.excelRow, original.excelRow); assert.equal(day.excelColumn, original.excelColumn);
    if (day.date) {
      count++;
      assert.ok(Object.isFrozen(day.lunar));
      assert.match(day.lunar.text, /^\d{2}\.\d{2}$/);
      assert.equal(day.displayText.split('\n')[0], `${day.dayNumber} (${day.lunar.text})`);
      assert.equal(day.displayText.split('\n').slice(1).join('\n'), original.displayText.split('\n').slice(1).join('\n'));
      assert.equal(inlineText(cellXml(sheet, day)), day.displayText);
      assert.ok(day.height >= original.height);
    } else {
      assert.equal(day.lunar, null); assert.equal(day.displayText, '');
    }
    for (let band = 1; band <= 3; band++) {
      const ref = String.fromCharCode(64 + day.excelColumn) + (day.excelRow + band);
      assert.match(sheet, new RegExp(`<c r="${ref}" s="\\d+"/>`));
    }
  }
  assert.equal(count, 365);
});

test('lunar run font and color stay independent of official, Sunday, Saturday, manual and ordinary date colors', () => {
  const records = [{ date: '2027-01-01', name: '모의 공식 휴일', source: 'official', category: 'public', sourceId: 'fixture:new-year' }];
  const manual = [validateManual({ date: '2027-01-04', name: '개인 일정', category: 'personal' }, 2027)];
  const model = buildCalendar({ year: 2027, mode: 'ready', snapshot: snapshot(records), manual, now: NOW, showLunar: true });
  const sheet = workbookParts(model)['xl/worksheets/sheet1.xml'];
  assert.equal(model.formatting.lunarFontSize, 7); assert.equal(model.formatting.lunarColor, '#777777');
  const expectedColors = new Map([[1, '#9C2436'], [2, '#2158A6'], [3, '#9C2436'], [4, '#70308C'], [5, '#17202A']]);
  for (const [number, color] of expectedColors) {
    const day = model.months[0].slots.find(item => item.dayNumber === number);
    assert.deepEqual(day.displayRuns[0], { kind: 'solar', text: String(number), fontSize: 10, color });
    assert.deepEqual(day.displayRuns[1], { kind: 'lunar', text: ` (${day.lunar.text})`, fontSize: 7, color: '#777777' });
    if (day.labels.length) assert.deepEqual(day.displayRuns[2], { kind: 'holidays', text: '\n' + day.labels.join('\n'), fontSize: 10, color });
    const runs = [...cellXml(sheet, day).matchAll(/<r>([\s\S]*?)<\/r>/g)].map(([, run]) => run);
    assert.equal(runs.length, day.displayRuns.length);
    runs.forEach((xml, index) => {
      const run = day.displayRuns[index];
      assert.equal(inlineText(xml), run.text);
      assert.match(xml, /<rFont val="맑은 고딕"\/>/);
      assert.ok(xml.includes(`<sz val="${run.fontSize}"/>`));
      assert.ok(xml.includes(`<color rgb="FF${run.color.slice(1)}"/>`));
    });
  }
  for (const day of model.months.flatMap(month => month.slots)) {
    assert.ok(Object.isFrozen(day.displayRuns));
    assert.ok(day.displayRuns.every(Object.isFrozen));
    assert.equal(day.displayRuns.map(run => run.text).join(''), day.displayText);
    if (!day.date) assert.deepEqual(day.displayRuns, []);
  }
  assert.equal((sheet.match(/<r>/g) || []).length, 365 * 2 + 2);
  assert.throws(() => { model.months[0].slots.find(day => day.date).displayRuns[1].color = '#FFFFFF'; });
});

test('custom lunar runs preserve literal text, scale the first line safely and leave disabled exports unchanged', () => {
  const manual = [
    validateManual({ date: '2027-01-04', name: '=SUM(A1:A2)&<_x0041_>', category: 'personal' }, 2027),
    validateManual({ date: '2027-01-06', name: '가'.repeat(50), category: 'company' }, 2027),
  ];
  const options = { year: 2027, mode: 'manual', manualApproved: true, manual, generatedAt: '2026-10-10T00:00:00Z' };
  const formatting = { fontFamily: 'Arial', fontSize: 8, lunarFontSize: 16, lunarColor: '#a1b2c3' };
  const model = buildCalendar({ ...options, showLunar: true, formatting });
  const small = buildCalendar({ ...options, showLunar: true, formatting: { ...formatting, lunarFontSize: 6 } });
  const off = buildCalendar({ ...options, formatting });
  const defaultOff = buildCalendar({ ...options, formatting: { fontFamily: 'Arial', fontSize: 8 } });
  const parts = workbookParts(model), sheet = parts['xl/worksheets/sheet1.xml'];
  for (const day of model.months.flatMap(month => month.slots).filter(day => day.date)) {
    const runs = day.displayRuns;
    assert.equal(runs[0].fontSize, 8); assert.equal(runs[1].fontSize, 16); assert.equal(runs[1].color, '#A1B2C3');
    if (runs[2]) assert.equal(runs[2].fontSize, 8);
    assert.equal(inlineText(cellXml(sheet, day)), day.displayText);
  }
  const fourth = model.months[0].slots.find(day => day.dayNumber === 4), xml = cellXml(sheet, fourth);
  assert.match(xml, /<rFont val="Arial"\/>/); assert.match(xml, /&amp;&lt;_x005F_x0041_&gt;/);
  assert.match(inlineText(xml), /=SUM\(A1:A2\)&<_x0041_>/);
  assert.equal(Object.values(parts).some(part => /<f[ >]|sheetProtection|externalLink|vbaProject|connections/.test(part)), false);
  const at = (calendar, number) => calendar.months[0].slots.find(day => day.dayNumber === number);
  assert.ok(at(model, 5).height > at(small, 5).height, 'larger lunar text must reserve more first-line height');
  assert.ok(at(model, 6).height >= at(off, 6).height, 'long holiday labels must remain fully visible at the solar font size');
  assert.equal(at(model, 6).labels[0], '[회사] ' + '가'.repeat(50));
  assert.deepEqual(off.months.map(month => month.weekHeights), defaultOff.months.map(month => month.weekHeights));
  const offSheet = workbookParts(off)['xl/worksheets/sheet1.xml'];
  assert.equal(offSheet, workbookParts(defaultOff)['xl/worksheets/sheet1.xml']);
  assert.doesNotMatch(offSheet, /<r>|<rPr>/);
  assert.equal(at(off, 4).displayRuns.some(run => run.kind === 'lunar'), false);
});
