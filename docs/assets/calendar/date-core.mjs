export const WEEKDAYS = ['일', '월', '화', '수', '목', '금', '토'];
export function yearNumber(value) {
  if (!/^(19\d{2}|20\d{2}|2100)$/.test(String(value))) throw new Error('연도는 1900~2100년 정수여야 합니다.');
  return Number(value);
}
export const isLeap = y => y % 4 === 0 && (y % 100 !== 0 || y % 400 === 0);
export function monthLength(year, month) {
  return [31, isLeap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1];
}
export const isoDate = (y, m, d) => `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
export function validDate(date, year) {
  if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return false;
  const [y, m, d] = date.split('-').map(Number);
  return y >= 1900 && y <= 2100 && (year === undefined || y === year) && m >= 1 && m <= 12 && d >= 1 && d <= monthLength(y, m);
}
// Integer Gregorian arithmetic: no date-only timezone conversion.
export function weekday(year, month, day) {
  const offsets = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4];
  const y = month < 3 ? year - 1 : year;
  return (y + Math.floor(y / 4) - Math.floor(y / 100) + Math.floor(y / 400) + offsets[month - 1] + day) % 7;
}
export function yearLayout(value) {
  const year = yearNumber(value);
  let startRow = 5;
  return Array.from({ length: 12 }, (_, i) => {
    const month = i + 1, offset = weekday(year, month, 1), days = monthLength(year, month);
    const weeks = Math.ceil((offset + days) / 7);
    const result = { year, month, offset, days, weeks, startRow, endRow: startRow + 1 + weeks * 4,
      slots: Array.from({ length: weeks * 7 }, (_, k) => {
        const day = k - offset + 1;
        return { date: day > 0 && day <= days ? isoDate(year, month, day) : null,
          dayNumber: day > 0 && day <= days ? day : null, weekday: k % 7,
          excelRow: startRow + 2 + 4 * Math.floor(k / 7), excelColumn: k % 7 + 1 };
      }) };
    startRow += 3 + 4 * weeks;
    return result;
  });
}
export function nextSeoulYear(now = new Date()) {
  return Number(new Intl.DateTimeFormat('en', { timeZone: 'Asia/Seoul', year: 'numeric' }).format(now)) + 1;
}
