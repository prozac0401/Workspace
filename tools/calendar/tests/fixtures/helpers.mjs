// Synthetic test data only; never deploy as official holiday data.
import { emptyDataset, LIMITATION } from '../../../../docs/assets/calendar/contract.mjs';
export const NOW = Date.parse('2026-10-11T00:00:00.000Z');
export const item = (date = '20270101', name = '검증자료', holiday = 'Y', seq = 1) => `<item><locdate>${date}</locdate><dateName>${name}</dateName><isHoliday>${holiday}</isHoliday><seq>${seq}</seq><dateKind>01</dateKind></item>`;
export const xml = (items = '', total = 0, page = 1, size = 100, code = '00') => `<response><header><resultCode>${code}</resultCode><resultMsg>OK</resultMsg></header><body><items>${items}</items><totalCount>${total}</totalCount><pageNo>${page}</pageNo><numOfRows>${size}</numOfRows></body></response>`;
export const response = text => new Response(text, { headers: { 'content-type': 'application/xml' } });
export const mockFetch = async url => response(url.searchParams.get('solMonth') === '01' ? xml(item(`${url.searchParams.get('solYear')}0101`), 1) : xml());
export function readyYear(year, now = NOW) {
  return { year, status: 'ready', complete: true, lastSuccessfulFetchAt: new Date(now).toISOString(), snapshotId: `fixture-${year}-${now}`,
    monthResults: Array.from({ length: 12 }, (_, i) => ({ month: i + 1, rawCount: i === 0 ? 1 : 0, pages: 1, status: 'success' })),
    holidays: [{ date: `${year}-01-01`, name: '검증 자료 (실제 공휴일 아님)', source: 'official', category: 'public', sourceId: `kasi:${year}0101:1` }], warnings: ['모의 테스트 자료입니다. 실제 공휴일 목록이 아닙니다.', LIMITATION] };
}
export function fixture(now = NOW) {
  const data = emptyDataset(now); data.datasetKind = 'fixture';
  for (const year of data.targetYears) data.years[year] = readyYear(year, now);
  return data;
}
