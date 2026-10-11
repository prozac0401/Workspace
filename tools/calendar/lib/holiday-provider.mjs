import sax from '../vendor/sax.cjs';
import { randomUUID } from 'node:crypto';
import { yearNumber, validDate } from '../../../docs/assets/calendar/date-core.mjs';
import { normalizeName, sortedHolidays } from '../../../docs/assets/calendar/calendar-model.mjs';
import { ENDPOINT, TTL, MAX_STALE, LIMITATION } from '../../../docs/assets/calendar/contract.mjs';
export { ENDPOINT, TTL, MAX_STALE };
export class HolidayError extends Error {
  constructor(code = 'UPSTREAM_ERROR', retryable = false, failedMonths = []) {
    super(code); this.code = code; this.retryable = retryable; this.failedMonths = failedMonths;
  }
}
const bad = () => { throw new HolidayError(); };
export const MAX_PAGES_PER_MONTH = 20;
export function parseHolidayXml(xml) {
  if (typeof xml !== 'string' || Buffer.byteLength(xml) > 1048576 || /<!\s*(DOCTYPE|ENTITY)/i.test(xml)) bad();
  let root = null, count = 0; const stack = [];
  const parser = sax.parser(true, { strictEntities: true, trim: false });
  parser.ondoctype = bad;
  parser.onopentag = node => {
    if (++count > 10000 || stack.length >= 10) bad();
    const entry = { name: node.name, text: '', children: [] };
    if (stack.length) stack.at(-1).children.push(entry); else { if (root) bad(); root = entry; }
    stack.push(entry);
  };
  parser.ontext = text => { if (stack.length) stack.at(-1).text += text; else if (text.trim()) bad(); };
  parser.oncdata = text => { if (!stack.length) bad(); stack.at(-1).text += text; };
  parser.onclosetag = () => stack.pop();
  try { parser.write(xml).close(); } catch { bad(); }
  function child(parent, name) { const result = parent?.children.filter(x => x.name === name); if (result?.length !== 1) bad(); return result[0]; }
  function text(parent, name, trim = true) { const node = child(parent, name); if (node.children.length) bad(); return trim ? node.text.trim() : node.text; }
  function integer(parent, name) { const value = text(parent, name); if (!/^\d+$/.test(value)) bad(); return Number(value); }
  if (root?.name !== 'response') bad();
  const header = child(root, 'header');
  const code = text(header, 'resultCode');
  if (code !== '00') throw new HolidayError('UPSTREAM_ERROR', ['01', '05', '23'].includes(code));
  text(header, 'resultMsg');
  const body = child(root, 'body');
  const totalCount = integer(body, 'totalCount'), pageNo = integer(body, 'pageNo'), numOfRows = integer(body, 'numOfRows');
  if (totalCount > 1000 || pageNo < 1 || pageNo > 1000 || numOfRows < 1 || numOfRows > 1000) bad();
  const container = child(body, 'items');
  if (container.text.trim() || container.children.some(x => x.name !== 'item')) bad();
  const items = container.children.map(item => {
    const locdate = text(item, 'locdate'), dateName = text(item, 'dateName', false), isHoliday = text(item, 'isHoliday');
    if (!/^\d{8}$/.test(locdate) || !['Y', 'N'].includes(isHoliday)) bad();
    let name; try { name = normalizeName(dateName); } catch { bad(); }
    const out = { locdate, dateName: name, isHoliday };
    for (const field of ['seq', 'dateKind']) out[field] = text(item, field);
    if (!/^\d{1,6}$/.test(out.seq) || !/^\d{2}$/.test(out.dateKind)) bad();
    return out;
  });
  if (items.length > numOfRows || items.length > totalCount) bad();
  return { items, totalCount, pageNo, numOfRows };
}
export function buildUpstreamUrl(year, month, pageNo, key) {
  // Accept the portal's decoded or percent-encoded key, normalize exactly once.
  let normalized = key;
  if (/%[0-9a-f]{2}/i.test(key)) { try { normalized = decodeURIComponent(key); } catch { throw new HolidayError('CONFIGURATION_ERROR'); } }
  const url = new URL(ENDPOINT);
  url.search = new URLSearchParams({ ServiceKey: normalized, solYear: String(year), solMonth: String(month).padStart(2, '0'), pageNo: String(pageNo), numOfRows: '100' }).toString();
  return url;
}
function semaphore(limit) {
  let active = 0; const queue = [];
  return async fn => {
    if (active >= limit) await new Promise(resolve => queue.push(resolve));
    else active++;
    try { return await fn(); } finally { const next = queue.shift(); if (next) next(); else active--; }
  };
}
async function readLimited(response) {
  if (Number(response.headers.get('content-length') || 0) > 1048576) {
    await response.body?.cancel().catch(() => {});
    bad();
  }
  if (!response.body) bad();
  const reader = response.body.getReader(); const parts = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.length; if (size > 1048576) bad(); parts.push(value);
    }
  } finally { await reader.cancel().catch(() => {}); }
  // Replacing malformed bytes could silently change an official holiday name.
  try { return new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(parts)); }
  catch { bad(); }
}
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export function createHolidayService({ key = '', fetchImpl = fetch, now = Date.now, delay = sleep, random = Math.random, timeoutMs = 8000, annualTimeoutMs = 60000 } = {}) {
  const run = semaphore(3);
  async function getPage(year, month, page, signal, deadline) {
    for (let attempt = 0; attempt < 3; attempt++) {
      let retryAfter = null;
      try {
        return await run(async () => {
          if (signal.aborted || now() >= deadline) throw new HolidayError('UPSTREAM_TIMEOUT', true);
          const requestSignal = AbortSignal.any([signal, AbortSignal.timeout(timeoutMs)]);
          let response;
          try { response = await fetchImpl(buildUpstreamUrl(year, month, page, key), { signal: requestSignal, redirect: 'error', headers: { Accept: 'application/xml' } }); }
          catch { throw new HolidayError(requestSignal.aborted ? 'UPSTREAM_TIMEOUT' : 'UPSTREAM_ERROR', true); }
          if (!response.ok) {
            const raw = response.headers.get('retry-after');
            retryAfter = raw === null ? null : /^\d+$/.test(raw) ? Number(raw) * 1000 : Math.max(0, Date.parse(raw) - now());
            await response.body?.cancel().catch(() => {});
            throw new HolidayError('UPSTREAM_ERROR', response.status === 429 || response.status >= 500);
          }
          let xml;
          try { xml = await readLimited(response); }
          catch (error) { if (error instanceof HolidayError) throw error; throw new HolidayError(requestSignal.aborted ? 'UPSTREAM_TIMEOUT' : 'UPSTREAM_ERROR', true); }
          return parseHolidayXml(xml);
        });
      } catch (error) {
        if (!(error instanceof HolidayError)) throw new HolidayError();
        if (!error.retryable || attempt === 2 || signal.aborted) throw error;
        const wait = Number.isFinite(retryAfter) ? retryAfter : (2 ** attempt) * 1000 + random() * 250;
        if (wait > 10000) throw new HolidayError('UPSTREAM_ERROR', true);
        if (now() + wait >= deadline) throw new HolidayError('UPSTREAM_TIMEOUT', true);
        await delay(wait);
      }
    }
  }
  async function collectMonth(year, month, signal, deadline) {
    let expected = null, pageSize = null, count = 0, pages = 0; const seenPages = new Set(), seenRecords = new Set(), holidays = [];
    do {
      if (pages >= MAX_PAGES_PER_MONTH) bad();
      const data = await getPage(year, month, ++pages, signal, deadline);
      if (data.pageNo !== pages || expected !== null && expected !== data.totalCount || pageSize !== null && pageSize !== data.numOfRows || data.totalCount && !data.items.length) bad();
      expected = data.totalCount;
      pageSize = data.numOfRows;
      const records = data.items.map(item => JSON.stringify(item));
      const fingerprint = JSON.stringify([...records].sort());
      if (seenPages.has(fingerprint) || pages > 1 && records.length && records.every(record => seenRecords.has(record))) bad();
      seenPages.add(fingerprint);
      records.forEach(record => seenRecords.add(record));
      for (const raw of data.items) {
        const date = `${raw.locdate.slice(0, 4)}-${raw.locdate.slice(4, 6)}-${raw.locdate.slice(6)}`;
        if (!validDate(date, year) || Number(date.slice(5, 7)) !== month) bad();
        if (raw.isHoliday === 'Y') holidays.push({ date, name: raw.dateName, source: 'official', category: 'public', sourceId: `kasi:${raw.locdate}:${raw.seq}` });
      }
      count += data.items.length;
      if (count > expected) bad();
    } while (count < expected);
    return { result: { month, status: 'success', rawCount: count, pages }, holidays };
  }
  async function collect(year) {
    const controller = new AbortController(), signal = controller.signal, deadline = now() + annualTimeoutMs;
    const succeeded = new Set(); let timer;
    const collection = Promise.allSettled(Array.from({ length: 12 }, (_, i) => collectMonth(year, i + 1, signal, deadline).then(result => { succeeded.add(i + 1); return result; })));
    // Bound the response even while another year occupies the shared upstream queue.
    let outcomes;
    try {
      outcomes = await Promise.race([collection, new Promise((_, reject) => {
        timer = setTimeout(() => {
          controller.abort();
          reject(new HolidayError('UPSTREAM_TIMEOUT', true, Array.from({ length: 12 }, (_, i) => i + 1).filter(m => !succeeded.has(m))));
        }, annualTimeoutMs);
      })]);
    } finally { clearTimeout(timer); }
    const failedMonths = outcomes.flatMap((v, i) => v.status === 'rejected' ? [i + 1] : []);
    if (failedMonths.length) {
      const errors = outcomes.filter(x => x.status === 'rejected').map(x => x.reason);
      throw new HolidayError(errors.some(x => x.code === 'UPSTREAM_TIMEOUT') ? 'UPSTREAM_TIMEOUT' : 'UPSTREAM_ERROR', errors.some(x => x.retryable), failedMonths);
    }
    const unique = new Map();
    for (const result of outcomes) for (const record of result.value.holidays) {
      const key = `${record.date}:${record.name}:${record.source}`;
      // Keep one deterministic identity, while rawCount still includes every item.
      if (!unique.has(key) || record.sourceId < unique.get(key).sourceId) unique.set(key, record);
    }
    if (!unique.size) throw new HolidayError('YEAR_UNAVAILABLE', false, Array.from({ length: 12 }, (_, i) => i + 1));
    const timestamp = now();
    return { year, snapshotId: randomUUID(), status: 'ready', complete: true,
      lastSuccessfulFetchAt: new Date(timestamp).toISOString(),
      monthResults: outcomes.map(x => x.value.result), holidays: sortedHolidays([...unique.values()]),
      warnings: [LIMITATION] };
  }
  async function getYear(input) {
    let year; try { year = yearNumber(input); } catch { throw new HolidayError('INVALID_YEAR'); }
    if (!key) throw new HolidayError('CONFIGURATION_ERROR');
    // Durability and stale decisions belong to the validated dataset, never runner memory.
    return collect(year);
  }
  return { getYear };
}
