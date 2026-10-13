import { yearLayout, validDate, yearNumber } from './date-core.mjs';
import { TTL, MAX_STALE, FRESH_DAYS, MAX_DAYS, MIN_YEAR, MAX_YEAR } from './contract.mjs';
import { normalizeFormatting } from './formatting.mjs';
import { lunarDate, MIN_LUNAR_YEAR, MAX_LUNAR_YEAR } from './lunar-calendar.mjs';
export const LIMITATION = '공식 공휴일은 추가·변경될 수 있습니다. 내려받은 파일은 자동 갱신되지 않습니다.';
export function normalizeName(value) {
  if (typeof value !== 'string' || /[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069\ufffe\uffff]/u.test(value)) throw new Error('이름에 줄바꿈·제어문자를 사용할 수 없습니다.');
  const name = value.trim().normalize('NFC');
  if (!name || [...name].length > 50 || /[\uD800-\uDFFF]/u.test(name)) throw new Error('이름은 1~50자여야 합니다.');
  return name;
}
export function validateManual(input, year, entries = [], excludingId = null) {
  if (!validDate(input.date, year)) throw new Error('선택 연도에 실재하는 날짜를 입력하세요.');
  if (!['company', 'personal'].includes(input.category)) throw new Error('회사 또는 개인 일정을 선택하세요.');
  const name = normalizeName(input.name);
  const others = entries.filter(x => x.sourceId !== excludingId);
  if (others.length >= 100) throw new Error('수동 일정은 최대 100개입니다.');
  if (others.some(x => x.date === input.date && normalizeName(x.name) === name && x.category === input.category)) throw new Error('같은 날짜·이름·구분의 수동 일정이 이미 있습니다.');
  return { date: input.date, name, source: 'manual', category: input.category,
    sourceId: excludingId || input.sourceId || `manual:${crypto.randomUUID()}` };
}
export const MAX_BACKUP_BYTES = 128 * 1024;
function backupEntries(value, year) {
  if (!Array.isArray(value) || value.length > 100) throw new Error('백업 일정은 배열이며 최대 100개여야 합니다.');
  const entries = [];
  for (const item of value) {
    if (!item || typeof item !== 'object' || Array.isArray(item)
      || Object.keys(item).sort().join(',') !== 'category,date,name') throw new Error('백업 일정의 형식이 올바르지 않습니다.');
    entries.push(validateManual({ date: item.date, name: item.name, category: item.category }, year, entries));
  }
  return entries;
}
export function parseManualBackup(text, selectedYear) {
  if (typeof text !== 'string' || new TextEncoder().encode(text).length > MAX_BACKUP_BYTES) throw new Error('백업 파일은 128 KiB 이하여야 합니다.');
  let data;
  try { data = JSON.parse(text); } catch { throw new Error('올바른 JSON 백업 파일을 선택하세요.'); }
  if (!data || typeof data !== 'object' || Array.isArray(data)
    || Object.keys(data).sort().join(',') !== 'entries,format,version,year'
    || data.format !== 'workspace-calendar-manual' || data.version !== 1) throw new Error('지원하는 일정 백업 형식·버전이 아닙니다.');
  if (!Number.isInteger(data.year) || data.year < MIN_YEAR || data.year > MAX_YEAR) throw new Error('백업 연도가 올바르지 않습니다.');
  if (data.year !== selectedYear) throw new Error(`백업은 ${data.year}년 일정입니다. 달력 연도를 먼저 맞춰 주세요.`);
  return backupEntries(data.entries, data.year);
}
export function serializeManualBackup(year, manual) {
  const entries = manual.map(({ date, name, category }) => ({ date, name, category }));
  const text = JSON.stringify({ format: 'workspace-calendar-manual', version: 1, year, entries }, null, 2);
  parseManualBackup(text, year);
  return text;
}
export function freezeDeep(value) {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.freeze(value); Object.values(value).forEach(freezeDeep);
  }
  return value;
}
const compare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
export function sortedHolidays(records) {
  return [...records].sort((a, b) => compare(a.date, b.date) || (a.source === b.source ? 0 : a.source === 'official' ? -1 : 1) || compare(a.name, b.name));
}
export function holidayDisplayName(record) {
  // Display only: preserve KASI names and identities in snapshots and sources.
  return record.source === 'official' ? record.name.replaceAll('기독탄신일', '크리스마스') : record.name;
}
export function seoulTime(value) {
  return value ? new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', dateStyle: 'short', timeStyle: 'medium', hour12: false }).format(new Date(value)) + ' KST' : '미확인';
}
export function estimateHeight(text, fontSize = 10, firstLineFontSize = fontSize) {
  // Conservative CJK width estimate: width 18, padding and font safety allowance.
  const capacity = 15 * 10 / fontSize;
  const lineWidth = line => [...line].reduce((n, c) => n + (c.codePointAt(0) > 255 ? 2 : 1), 0);
  const parts = text.split('\n');
  if (firstLineFontSize > fontSize) {
    // The date line can mix solar/lunar sizes; using its largest size avoids clipping.
    const firstLines = Math.max(1, Math.ceil(lineWidth(parts[0]) / (15 * 10 / firstLineFontSize)));
    const restLines = parts.slice(1).reduce((sum, line) => sum + Math.max(1, Math.ceil(lineWidth(line) / capacity)), 0);
    return Math.max(34, firstLines * firstLineFontSize * 1.6 + restLines * fontSize * 1.6 + 10);
  }
  const lines = parts.reduce((sum, line) => sum + Math.max(1, Math.ceil(lineWidth(line) / capacity)), 0);
  return Math.max(34, lines * fontSize * 1.6 + 10);
}
export function buildCalendar({ year: inputYear, snapshot = null, manual = [], mode = 'manual', staleApproved = false, manualApproved = false, generatedAt = new Date().toISOString(), now = Date.now(), formatting: inputFormatting, showLunar = false }) {
  const year = yearNumber(inputYear);
  const formatting = normalizeFormatting(inputFormatting);
  if (typeof showLunar !== 'boolean') throw new Error('음력 표시 여부는 참 또는 거짓이어야 합니다.');
  if (showLunar && (year < MIN_LUNAR_YEAR || year > MAX_LUNAR_YEAR)) throw new Error(`음력 표시는 ${MIN_LUNAR_YEAR}~${MAX_LUNAR_YEAR}년만 지원합니다.`);
  if (!['ready', 'stale', 'manual'].includes(mode)) throw new Error('미리보기를 만들 수 없는 상태입니다.');
  if (mode === 'manual' && !manualApproved) throw new Error('수동 자료만 사용하려면 명시적으로 확인하세요.');
  if (mode !== 'manual' && (!snapshot || snapshot.year !== year || !snapshot.complete || !['ready', 'stale'].includes(snapshot.status) || snapshot.status !== mode || !Array.isArray(snapshot.monthResults) || snapshot.monthResults.length !== 12 || new Set(snapshot.monthResults.map(x => x.month)).size !== 12 || snapshot.monthResults.some(x => x.status !== 'success' || x.month < 1 || x.month > 12))) throw new Error('완전한 연간 공휴일 자료가 필요합니다.');
  if (mode !== 'manual') {
    const age = Number(now) - Date.parse(snapshot.lastSuccessfulFetchAt ?? snapshot.fetchedAt);
    if (!Number.isFinite(age) || age < -5 * 60 * 1000 || age > MAX_STALE) throw new Error(`공식 자료의 수집 시각이 잘못되었거나 사용 상한 ${MAX_DAYS}일을 지났습니다.`);
    if (age >= TTL && mode !== 'stale') throw new Error(`${FRESH_DAYS}일이 지난 자료입니다. 이전 자료 사용을 확인하세요.`);
  }
  if (mode === 'stale' && !staleApproved) throw new Error('이전 자료 사용을 확인하세요.');
  const cleanedManual = [];
  for (const item of manual) cleanedManual.push(validateManual(item, year, cleanedManual));
  // Only the validated, normalized manual records enter the immutable snapshot.
  const selected = mode === 'manual' ? [] : snapshot.holidays;
  if (!Array.isArray(selected) || selected.some(x => x.source !== 'official')) throw new Error('공식 휴일 자료가 유효하지 않습니다.');
  if (mode !== 'manual' && selected.length === 0) throw new Error('연간 공식 휴일 0건: 자료 공개 여부를 확인하세요.');
  const records = sortedHolidays(structuredClone([...selected, ...cleanedManual]).map(x => {
    if (!validDate(x.date, year) || !['official', 'manual'].includes(x.source)) throw new Error('휴일 데이터가 유효하지 않습니다.');
    return { ...x, name: normalizeName(x.name) };
  }));
  const dayColors = { black: formatting.textColor, red: formatting.holidayColor, blue: formatting.saturdayColor, purple: formatting.manualColor, outside: formatting.textColor };
  const months = yearLayout(year).map(month => {
    const slots = month.slots.map(slot => {
      const sources = records.filter(x => x.date === slot.date);
      const seen = new Set();
      const labels = sources.map(record => ({ record, name: holidayDisplayName(record) }))
        .sort((a, b) => (a.record.source === b.record.source ? 0 : a.record.source === 'official' ? -1 : 1) || compare(a.name, b.name))
        .filter(({ name }) => { if (seen.has(name)) return false; seen.add(name); return true; })
        .map(({ record, name }) => record.source === 'official' ? name : `${record.category === 'company' ? '[회사]' : '[개인]'} ${name}`);
      const official = sources.some(x => x.source === 'official');
      const styleToken = !slot.date ? 'outside' : official || slot.weekday === 0 ? 'red' : slot.weekday === 6 ? 'blue' : sources.length ? 'purple' : 'black';
      const lunar = showLunar && slot.date ? lunarDate(slot.date) : null;
      const displayRuns = [];
      if (slot.date) {
        displayRuns.push({ kind: 'solar', text: String(slot.dayNumber), fontSize: formatting.fontSize, color: dayColors[styleToken] });
        if (lunar) displayRuns.push({ kind: 'lunar', text: ` (${lunar.text})`, fontSize: formatting.lunarFontSize, color: formatting.lunarColor });
        if (labels.length) displayRuns.push({ kind: 'holidays', text: '\n' + labels.join('\n'), fontSize: formatting.fontSize, color: dayColors[styleToken] });
      }
      const displayText = displayRuns.map(run => run.text).join('');
      const height = estimateHeight(displayText, formatting.fontSize, lunar ? Math.max(formatting.fontSize, formatting.lunarFontSize) : formatting.fontSize);
      if (height > 409) throw new Error(`${slot.date}: 이름이 많아 지원 행 높이(409pt)를 초과합니다. 일정 이름 또는 글자 크기를 줄이세요.`);
      return { ...slot, lunar, labels, sources, displayRuns, displayText, styleToken, height };
    });
    const weekHeights = Array.from({ length: month.weeks }, (_, q) => Math.max(...slots.slice(q * 7, q * 7 + 7).map(d => d.height)));
    return { ...month, slots, weekHeights };
  });
  const isMock = mode !== 'manual' && (snapshot.datasetKind === 'fixture' || snapshot.mock === true);
  const sourceText = mode === 'manual' ? '수동 자료만 사용 · 공식 자료 미확인' : isMock ? '모의 테스트 자료 · 공식 공휴일 미검증' : '한국천문연구원 getRestDeInfo';
  const model = { config: { year, writingRows: 3, weekStartsOn: 0, locale: 'ko-KR', layout: 'vertical', showLunar }, mode, generatedAt, formatting,
    snapshot: mode === 'manual' ? null : structuredClone(snapshot), manual: cleanedManual, months, isMock, sourceText,
    title: `${year}년 달력`, endRow: months.at(-1).endRow,
    metadataText: `${sourceText} · 자료: ${seoulTime(mode === 'manual' ? null : (snapshot.lastSuccessfulFetchAt ?? snapshot.fetchedAt))} · 생성: ${seoulTime(generatedAt)} · ${mode}${showLunar ? ' · 음력: 한국 음력 변환표' : ''}`,
    legendText: `일요일·공식 휴일 ${formatting.holidayColor} / 토요일 ${formatting.saturdayColor} / 수동 일정 ${formatting.manualColor}\n${LIMITATION}` };
  return freezeDeep(model);
}
