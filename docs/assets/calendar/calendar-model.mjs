import { yearLayout, validDate, yearNumber } from './date-core.mjs';
import { TTL, MAX_STALE, FRESH_DAYS, MAX_DAYS } from './contract.mjs';
export const LIMITATION = '공식 공휴일은 추가·변경될 수 있습니다. 내려받은 파일은 자동 갱신되지 않습니다.';
export const LEGEND = '빨강: 일요일·공식 휴일 / 파랑: 토요일 / 보라: 수동 휴일';
export function normalizeName(value) {
  if (typeof value !== 'string' || /[\u0000-\u001f\u007f-\u009f\u2028\u2029\u202a-\u202e\u2066-\u2069\ufffe\uffff]/u.test(value)) throw new Error('휴일명에 줄바꿈·제어문자를 사용할 수 없습니다.');
  const name = value.trim().normalize('NFC');
  if (!name || [...name].length > 50 || /[\uD800-\uDFFF]/u.test(name)) throw new Error('휴일명은 1~50자여야 합니다.');
  return name;
}
export function validateManual(input, year, entries = [], excludingId = null) {
  if (!validDate(input.date, year)) throw new Error('선택 연도에 실재하는 날짜를 입력하세요.');
  if (!['company', 'personal'].includes(input.category)) throw new Error('회사 또는 개인 휴일을 선택하세요.');
  const name = normalizeName(input.name);
  const others = entries.filter(x => x.sourceId !== excludingId);
  if (others.length >= 100) throw new Error('수동 휴일은 최대 100개입니다.');
  if (others.some(x => x.date === input.date && normalizeName(x.name) === name && x.category === input.category)) throw new Error('같은 날짜·이름·구분의 수동 휴일이 이미 있습니다.');
  return { date: input.date, name, source: 'manual', category: input.category,
    sourceId: excludingId || input.sourceId || `manual:${crypto.randomUUID()}` };
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
export function seoulTime(value) {
  return value ? new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', dateStyle: 'short', timeStyle: 'medium', hour12: false }).format(new Date(value)) + ' KST' : '미확인';
}
export function estimateHeight(text) {
  // Conservative CJK width estimate: width 18, padding and font safety allowance.
  const lines = text.split('\n').reduce((sum, line) => sum + Math.max(1, Math.ceil([...line].reduce((n, c) => n + (c.codePointAt(0) > 255 ? 2 : 1), 0) / 15)), 0);
  return Math.max(34, lines * 16 + 10);
}
export function buildCalendar({ year: inputYear, snapshot = null, manual = [], mode = 'manual', staleApproved = false, manualApproved = false, generatedAt = new Date().toISOString(), now = Date.now() }) {
  const year = yearNumber(inputYear);
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
  const months = yearLayout(year).map(month => {
    const slots = month.slots.map(slot => {
      const sources = records.filter(x => x.date === slot.date);
      const seen = new Set();
      const labels = sources.filter(x => { if (seen.has(x.name)) return false; seen.add(x.name); return true; })
        .map(x => x.source === 'official' ? x.name : `${x.category === 'company' ? '[회사]' : '[개인]'} ${x.name}`);
      const official = sources.some(x => x.source === 'official');
      const styleToken = !slot.date ? 'outside' : official || slot.weekday === 0 ? 'red' : slot.weekday === 6 ? 'blue' : sources.length ? 'purple' : 'black';
      const displayText = slot.date ? [String(slot.dayNumber), ...labels].join('\n') : '';
      const height = estimateHeight(displayText);
      if (height > 409) throw new Error(`${slot.date}: 휴일명이 많아 지원 행 높이(409pt)를 초과합니다. 수동 휴일명을 줄이세요.`);
      return { ...slot, labels, sources, displayText, styleToken, height };
    });
    const weekHeights = Array.from({ length: month.weeks }, (_, q) => Math.max(...slots.slice(q * 7, q * 7 + 7).map(d => d.height)));
    return { ...month, slots, weekHeights };
  });
  const isMock = mode !== 'manual' && (snapshot.datasetKind === 'fixture' || snapshot.mock === true);
  const sourceText = mode === 'manual' ? '수동 자료만 사용 · 공식 자료 미확인' : isMock ? '모의 테스트 자료 · 공식 공휴일 미검증' : '한국천문연구원 getRestDeInfo';
  const model = { config: { year, writingRows: 3, weekStartsOn: 0, locale: 'ko-KR', layout: 'vertical' }, mode, generatedAt,
    snapshot: mode === 'manual' ? null : structuredClone(snapshot), manual: cleanedManual, months, isMock, sourceText,
    title: `${year}년 달력`, endRow: months.at(-1).endRow,
    metadataText: `${sourceText} · 자료: ${seoulTime(mode === 'manual' ? null : (snapshot.lastSuccessfulFetchAt ?? snapshot.fetchedAt))} · 생성: ${seoulTime(generatedAt)} · ${mode}`,
    legendText: `${LEGEND}\n${LIMITATION}` };
  return freezeDeep(model);
}
