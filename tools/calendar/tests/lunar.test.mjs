import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import KoreanLunarCalendar from 'korean-lunar-calendar';
import { lunarDate, MIN_LUNAR_YEAR, MAX_LUNAR_YEAR } from '../../../docs/assets/calendar/lunar-calendar.mjs';
import { LUNAR_MONTH_STARTS } from '../../../docs/assets/calendar/lunar-data.mjs';

test('pinned lunar table regenerates byte for byte with its MIT notice', () => {
  const result = execFileSync(process.execPath, [fileURLToPath(new URL('../generate-lunar-data.mjs', import.meta.url)), '--check'], { encoding: 'utf8' });
  assert.match(result, /Lunar table reproducible/);
  assert.equal(MIN_LUNAR_YEAR, 1983); assert.equal(MAX_LUNAR_YEAR, 2050);
  assert.ok(Object.isFrozen(LUNAR_MONTH_STARTS));
  assert.ok(LUNAR_MONTH_STARTS.every(Object.isFrozen));
});

test('Korean lunar boundaries, festivals, leap months and 2033 month numbering', () => {
  const expected = [
    ['1983-01-01', 1982, 11, 18, false],
    ['2027-01-01', 2026, 11, 24, false],
    ['2027-02-07', 2027, 1, 1, false],
    ['2027-09-15', 2027, 8, 15, false],
    ['2017-02-26', 2017, 2, 1, false],
    ['2017-06-24', 2017, 5, 1, true],
    ['2033-08-25', 2033, 8, 1, false],
    ['2033-12-22', 2033, 11, 1, true],
    ['2050-12-31', 2050, 11, 18, false],
  ];
  for (const [date, year, month, day, isLeapMonth] of expected) {
    assert.deepEqual(lunarDate(date), { year, month, day, isLeapMonth, text: `${String(month).padStart(2, '0')}.${String(day).padStart(2, '0')}` }, date);
  }
  for (const invalid of [null, undefined, '', '1982-12-31', '2051-01-01', '2099-12-31', '2027-02-29', '2027-13-01', '2027-2-07', '2027-02-07T00:00:00Z']) {
    assert.throws(() => lunarDate(invalid), RangeError);
  }
  assert.ok(Object.isFrozen(lunarDate('2027-02-07')));
});

test('all 24,837 supported days match the pinned Korean table with continuous 29/30-day months', () => {
  const reference = new KoreanLunarCalendar();
  let previous = null, total = 0;
  for (let time = Date.UTC(1983, 0, 1); time < Date.UTC(2051, 0, 1); time += 86_400_000) {
    const date = new Date(time), iso = date.toISOString().slice(0, 10);
    assert.equal(reference.setSolarDate(date.getUTCFullYear(), date.getUTCMonth() + 1, date.getUTCDate()), true);
    const expected = reference.getLunarCalendar();
    const actual = lunarDate(iso);
    assert.deepEqual([actual.year, actual.month, actual.day, actual.isLeapMonth], [expected.year, expected.month, expected.day, expected.intercalation], iso);
    if (previous) {
      if (actual.day === 1) {
        assert.ok(previous.day === 29 || previous.day === 30, iso);
        if (actual.isLeapMonth) assert.equal(actual.month, previous.month, iso);
        else assert.equal(actual.month, previous.month % 12 + 1, iso);
      } else assert.equal(actual.day, previous.day + 1, iso);
    }
    previous = actual; total++;
  }
  assert.equal(total, 24_837);
});

test('lunar date-only output is invariant across host time zones', () => {
  const script = `import { lunarDate } from ${JSON.stringify(new URL('../../../docs/assets/calendar/lunar-calendar.mjs', import.meta.url).href)}; console.log(JSON.stringify(['1983-01-01','2017-02-26','2027-02-07','2033-12-22','2050-12-31'].map(lunarDate)));`;
  const outputs = ['UTC', 'Asia/Seoul', 'America/Los_Angeles'].map(TZ => execFileSync(process.execPath, ['--input-type=module', '-e', script], { env: { ...process.env, TZ }, encoding: 'utf8' }));
  assert.equal(outputs[0], outputs[1]); assert.equal(outputs[0], outputs[2]);
});
