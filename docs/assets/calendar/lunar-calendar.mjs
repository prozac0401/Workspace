import { validDate } from './date-core.mjs';
import { LUNAR_MONTH_STARTS } from './lunar-data.mjs';

export const MIN_LUNAR_YEAR = 1983;
export const MAX_LUNAR_YEAR = 2050;
const DAY_MS = 86_400_000;
const dayNumber = iso => {
  const [year, month, day] = iso.split('-').map(Number);
  return Date.UTC(year, month - 1, day) / DAY_MS;
};
const starts = LUNAR_MONTH_STARTS.map(row => dayNumber(row[0]));
const pad = number => String(number).padStart(2, '0');

// Date-only UTC arithmetic is independent of browser locale and local time zone.
export function lunarDate(iso) {
  if (!validDate(iso) || iso < `${MIN_LUNAR_YEAR}-01-01` || iso > `${MAX_LUNAR_YEAR}-12-31`) {
    throw new RangeError(`음력 표시는 ${MIN_LUNAR_YEAR}~${MAX_LUNAR_YEAR}년의 실제 날짜만 지원합니다.`);
  }
  const target = dayNumber(iso);
  let low = 0, high = starts.length;
  while (low + 1 < high) {
    const middle = Math.floor((low + high) / 2);
    if (starts[middle] <= target) low = middle;
    else high = middle;
  }
  const [, year, month, isLeapMonth] = LUNAR_MONTH_STARTS[low];
  const day = target - starts[low] + 1;
  return Object.freeze({ year, month, day, isLeapMonth, text: `${pad(month)}.${pad(day)}` });
}
