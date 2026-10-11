// Public data contract v2. Keep schema and the stricter semantic checks in sync.
import { validDate } from './date-core.mjs';
export const ENDPOINT = 'https://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService/getRestDeInfo';
export const MAX_DATA_BYTES = 2 * 1024 * 1024;
export const MIN_YEAR = 1983;
export const MAX_YEAR = 2099;
export const TTL = 24 * 60 * 60 * 1000;
export const MAX_STALE = 30 * TTL;
export const LIMITATION = '12개월 조회 완료는 향후 임시공휴일 확정을 뜻하지 않습니다. 이미 다운로드한 파일은 자동 갱신되지 않습니다.';
export class CalendarDataError extends Error {
  constructor(code) { super(code); this.code = code; }
}
const fail = (code = 'CALENDAR_SCHEMA_INVALID') => { throw new CalendarDataError(code); };
const keys = (value, expected) => {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).length !== expected.length || expected.some(key => !Object.hasOwn(value, key))) fail();
};
const integer = (n, low, high) => Number.isInteger(n) && n >= low && n <= high;
const safeText = (text, max) => typeof text === 'string' && text === text.trim() && text.length > 0 && [...text].length <= max && !/[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069\ufffe\uffff\uD800-\uDFFF]/u.test(text);
const timestamp = text => typeof text === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(text) && Number.isFinite(Date.parse(text)) && new Date(text).toISOString() === text;
export function currentSeoulYear(now = Date.now()) {
  return Number(new Intl.DateTimeFormat('en', { timeZone: 'Asia/Seoul', year: 'numeric' }).format(new Date(now)));
}
export function targetYears() {
  return Array.from({ length: MAX_YEAR - MIN_YEAR + 1 }, (_, index) => MIN_YEAR + index);
}
export function emptyYear(year, status = 'unavailable', warning = '공식 자료를 아직 수집하지 않았습니다.') {
  return { year, status, complete: false, lastSuccessfulFetchAt: null, snapshotId: null,
    monthResults: Array.from({ length: 12 }, (_, index) => ({ month: index + 1, rawCount: 0, pages: 0, status })),
    holidays: [], warnings: [warning, LIMITATION] };
}
export function emptyDataset(now = Date.now()) {
  const years = targetYears(now);
  return { schemaVersion: 2, source: { provider: 'KASI', operation: 'getRestDeInfo', url: ENDPOINT },
    datasetKind: 'uninitialized', supportedYears: years, targetYears: [...years],
    years: Object.fromEntries(years.map(year => [year, emptyYear(year)])) };
}
export function validateDataset(data, { production = false } = {}) {
  keys(data, ['schemaVersion', 'source', 'datasetKind', 'supportedYears', 'targetYears', 'years']);
  if (data.schemaVersion !== 2 || !['official', 'fixture', 'uninitialized'].includes(data.datasetKind) || production && data.datasetKind !== 'official') fail();
  keys(data.source, ['provider', 'operation', 'url']);
  if (data.source.provider !== 'KASI' || data.source.operation !== 'getRestDeInfo' || data.source.url !== ENDPOINT) fail();
  const expectedYears = targetYears();
  if (!Array.isArray(data.targetYears) || JSON.stringify(data.targetYears) !== JSON.stringify(expectedYears) || !Array.isArray(data.supportedYears) || JSON.stringify(data.supportedYears) !== JSON.stringify(expectedYears)) fail();
  keys(data.years, data.targetYears.map(String));
  for (const year of data.targetYears) {
    const snapshot = data.years[year];
    keys(snapshot, ['year', 'status', 'complete', 'lastSuccessfulFetchAt', 'snapshotId', 'monthResults', 'holidays', 'warnings']);
    if (snapshot.year !== year || !['ready', 'preserved', 'unavailable', 'error'].includes(snapshot.status) || typeof snapshot.complete !== 'boolean') fail();
    if (!Array.isArray(snapshot.warnings) || snapshot.warnings.length > 20 || !snapshot.warnings.every(w => safeText(w, 250))) fail();
    if (!Array.isArray(snapshot.monthResults) || snapshot.monthResults.length !== 12 || !Array.isArray(snapshot.holidays) || snapshot.holidays.length > 12000) fail();
    let rawCount = 0;
    snapshot.monthResults.forEach((month, index) => {
      keys(month, ['month', 'rawCount', 'pages', 'status']);
      if (month.month !== index + 1 || !integer(month.rawCount, 0, 1000) || !integer(month.pages, 0, 1000) || !['success', 'unavailable', 'error'].includes(month.status)) fail();
      if (snapshot.complete ? month.status !== 'success' || month.pages < 1 || month.pages > Math.max(1, month.rawCount) : month.status === 'success' || month.pages !== 0 || month.rawCount !== 0) fail();
      rawCount += month.rawCount;
    });
    if (snapshot.complete) {
      if (!['ready', 'preserved'].includes(snapshot.status) || !timestamp(snapshot.lastSuccessfulFetchAt) || !safeText(snapshot.snapshotId, 100) || !/^[a-zA-Z0-9_-]+$/.test(snapshot.snapshotId) || snapshot.holidays.length === 0 || snapshot.holidays.length > rawCount) fail();
    } else if (!['unavailable', 'error'].includes(snapshot.status) || snapshot.lastSuccessfulFetchAt !== null || snapshot.snapshotId !== null || snapshot.holidays.length !== 0) fail();
    let previous = '';
    const perMonth = new Map();
    for (const holiday of snapshot.holidays) {
      keys(holiday, ['date', 'name', 'source', 'category', 'sourceId']);
      if (!validDate(holiday.date, year) || !safeText(holiday.name, 50) || holiday.name !== holiday.name.normalize('NFC') || holiday.source !== 'official' || holiday.category !== 'public' || !/^kasi:\d{8}:\d{1,6}$/.test(holiday.sourceId) || holiday.sourceId.slice(5, 13) !== holiday.date.replaceAll('-', '')) fail();
      const order = `${holiday.date}\u0000${holiday.name}`;
      if (previous && previous >= order) fail();
      previous = order;
      const month = Number(holiday.date.slice(5, 7));
      perMonth.set(month, (perMonth.get(month) || 0) + 1);
    }
    for (const [month, count] of perMonth) if (count > snapshot.monthResults[month - 1].rawCount) fail();
    if (data.datasetKind === 'uninitialized' && snapshot.complete) fail();
  }
  if (production && !Object.values(data.years).some(year => year.complete)) fail();
  // Every producer writes this canonical representation. A snapshot accepted for
  // persistence must also fit the browser, pinned Git reader and build limit.
  if (new TextEncoder().encode(JSON.stringify(data, null, 2) + '\n').length > MAX_DATA_BYTES) fail();
  return data;
}
const freeze = value => { if (value && typeof value === 'object') { Object.values(value).forEach(freeze); Object.freeze(value); } return value; };
export function selectYear(data, year, now = Date.now()) {
  validateDataset(data);
  if (!Number.isInteger(year) || year < MIN_YEAR || year > MAX_YEAR) fail('CALENDAR_YEAR_UNSUPPORTED');
  const snapshot = data.years[year];
  if (!snapshot?.complete || data.datasetKind === 'uninitialized') fail('CALENDAR_DATA_UNAVAILABLE');
  const age = Number(new Date(now)) - Date.parse(snapshot.lastSuccessfulFetchAt);
  if (!Number.isFinite(age) || age < -5 * 60 * 1000) fail();
  if (age > MAX_STALE) fail('CALENDAR_DATA_EXPIRED');
  return freeze({ ...structuredClone(snapshot), status: age >= TTL || snapshot.status === 'preserved' ? 'stale' : 'ready',
    fetchedAt: snapshot.lastSuccessfulFetchAt, expiresAt: new Date(Date.parse(snapshot.lastSuccessfulFetchAt) + TTL).toISOString(),
    datasetKind: data.datasetKind, mock: data.datasetKind === 'fixture' });
}
