// One validated formatting snapshot drives both the preview and the workbook.
export const DEFAULT_FORMATTING = Object.freeze({
  fontFamily: '맑은 고딕', fontSize: 10, titleSize: 16, writingRowHeight: 22,
  textColor: '#17202A', holidayColor: '#9C2436', saturdayColor: '#2158A6', manualColor: '#70308C',
  titleColor: '#FFFFFF', titleBackground: '#213E46', weekdayBackground: '#E8F0F1',
  background: '#FFFFFF', outsideBackground: '#F0F2F4', borderColor: '#BAC3CC',
});
export function normalizeFormatting(input = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input) || ![Object.prototype, null].includes(Object.getPrototypeOf(input))) throw new Error('서식 설정이 올바르지 않습니다.');
  if (Object.keys(input).some(key => !Object.hasOwn(DEFAULT_FORMATTING, key))) throw new Error('지원하지 않는 서식 설정입니다.');
  const value = { ...DEFAULT_FORMATTING, ...input };
  if (!['맑은 고딕', 'Arial', '바탕'].includes(value.fontFamily)) throw new Error('지원하는 글꼴을 선택하세요.');
  for (const [key, label, min, max] of [['fontSize', '글자 크기', 8, 16], ['titleSize', '월 제목 크기', 14, 24], ['writingRowHeight', '작성칸 높이', 16, 32]]) {
    if (!Number.isInteger(value[key]) || value[key] < min || value[key] > max) throw new Error(`${label}는 ${min}~${max} 정수여야 합니다.`);
  }
  for (const key of Object.keys(value).filter(key => !['fontFamily', 'fontSize', 'titleSize', 'writingRowHeight'].includes(key))) {
    if (typeof value[key] !== 'string' || !/^#[\da-f]{6}$/i.test(value[key])) throw new Error('색상은 #RRGGBB 형식이어야 합니다.');
    value[key] = value[key].toUpperCase();
  }
  return Object.freeze(value);
}
