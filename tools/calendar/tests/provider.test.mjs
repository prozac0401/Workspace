import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { parseHolidayXml, createHolidayService, HolidayError, buildUpstreamUrl, ENDPOINT, MAX_PAGES_PER_MONTH, MAX_REQUESTS_PER_RUN } from '../lib/holiday-provider.mjs';
import { item, xml, response, mockFetch, NOW } from './fixtures/helpers.mjs';
const service = options => createHolidayService({ key: 'FAKE-TEST-ONLY', now: () => NOW, delay: async () => {}, random: () => 0, ...options });

test('XML normalizes empty, single, multiple items and checks required fields', () => {
  assert.deepEqual(parseHolidayXml(xml()).items, []);
  assert.equal(parseHolidayXml(xml(item(), 1)).items.length, 1);
  assert.equal(parseHolidayXml(xml(item() + item('20270102'), 2)).items.length, 2);
  for (const field of ['locdate', 'dateName', 'isHoliday', 'seq', 'dateKind']) {
    assert.throws(() => parseHolidayXml(xml(item().replace(new RegExp(`<${field}>.*?</${field}>`), ''), 1)), HolidayError);
  }
});
test('business errors, HTML, malformed XML, DTD/entity, oversized response and invalid fields fail safely', () => {
  for (const source of [xml('', 0, 1, 100, '30'), '<html>secret error</html>', '<response>', xml().replace('<totalCount>0</totalCount>', ''), '<!DOCTYPE response [<!ENTITY x SYSTEM "file:///secret">]>' + xml(), xml(item('20270101', '&unknown;'), 1), ' '.repeat(1048577), xml(item('20270101', 'x', 'maybe'), 1), xml().replace('<pageNo>1</pageNo>', '<pageNo>1</pageNo><pageNo>1</pageNo>'), xml('', 1001)]) {
    assert.throws(() => parseHolidayXml(source), error => error instanceof HolidayError && !error.message.includes('secret'));
  }
});
test('raw pre-filter count, exact duplicate raw items and different same-date holiday names', async () => {
  const calls = [];
  const s = service({ fetchImpl: async url => {
    calls.push(url); const m = url.searchParams.get('solMonth'), page = +url.searchParams.get('pageNo');
    if (m !== '01') return response(xml());
    return response(page === 1 ? xml(item('20270101', 'A') + item('20270101', 'A'), 4, 1, 2) : xml(item('20270101', 'B', 'Y', 2) + item('20270102', '기념일', 'N', 3), 4, 2, 2));
  } });
  const data = await s.getYear(2027);
  assert.equal(data.complete, true); assert.deepEqual(data.holidays.map(h => h.name), ['A', 'B']);
  assert.equal(data.monthResults[0].rawCount, 4); assert.equal(data.monthResults[0].pages, 2); assert.equal(calls.length, 13);
  assert.ok(calls.every(u => u.href.startsWith(ENDPOINT) && u.searchParams.get('numOfRows') === '100' && u.searchParams.has('solMonth')));
  assert.ok(data.holidays.every(h => !('raw' in h) && !('rawRecords' in h)));
});
test('repeated/stalled pages, totals/page-size changes, wrong year/month and impossible dates fail', async () => {
  const variants = [
    page => xml(item(), 2, 1, 1),
    page => page === 1 ? xml(item(), 2, 1, 1) : xml('', 2, 2, 1),
    page => page === 1 ? xml(item(), 2, 1, 1) : xml(item('20270102'), 3, 2, 1),
    page => page === 1 ? xml(item(), 2, 1, 1) : xml(item('20270102'), 2, 2, 2),
    () => xml(item('20270201'), 1), () => xml(item('20270132'), 1), () => xml(item('20260101'), 1),
    page => xml(item(), 2, page, 1),
    page => xml(page === 1 ? item() + item('20270102') : item('20270102') + item(), 4, page, 2)
  ];
  for (const variant of variants) await assert.rejects(service({ fetchImpl: async url => response(url.searchParams.get('solMonth') === '01' ? variant(+url.searchParams.get('pageNo')) : xml()) }).getYear(2027), e => e.code === 'UPSTREAM_ERROR' && e.failedMonths.includes(1));
});
test('normal empty months accepted; all-year zero is unavailable; key/year errors explicit before fetch', async () => {
  await assert.rejects(service({ fetchImpl: async () => response(xml()) }).getYear(2027), e => e.code === 'YEAR_UNAVAILABLE');
  await assert.rejects(createHolidayService({ fetchImpl: () => assert.fail('must not fetch') }).getYear(2027), e => e.code === 'CONFIGURATION_ERROR');
  await assert.rejects(createHolidayService().getYear('2027x'), e => e.code === 'INVALID_YEAR');
  assert.equal((await service({ fetchImpl: mockFetch }).getYear(2027)).monthResults.filter(m => m.rawCount === 0).length, 11);
});
test('429 Retry-After bounded retries, HTTP auth no retry, business auth no retry, network errors redacted', async () => {
  let count = 0; const delays = [];
  await service({ delay: async ms => delays.push(ms), fetchImpl: async url => {
    if (url.searchParams.get('solMonth') !== '01') return response(xml());
    if (++count < 3) return new Response('busy', { status: 429, headers: { 'Retry-After': '2' } });
    return response(xml(item(), 1));
  } }).getYear(2027);
  assert.equal(count, 3); assert.deepEqual(delays, [2000, 2000]);
  for (const fetcher of [() => new Response('auth', { status: 401 }), () => response(xml('', 0, 1, 100, '30'))]) {
    count = 0; await assert.rejects(service({ fetchImpl: async () => { count++; return fetcher(); } }).getYear(2027)); assert.equal(count, 12);
  }
  count = 0;
  await assert.rejects(service({ fetchImpl: async () => { count++; throw new Error('SECRET-URL'); } }).getYear(2027), e => e.message === 'UPSTREAM_ERROR');
  assert.equal(count, 36);
  await assert.rejects(service({ delay: () => assert.fail('unbounded delay'), fetchImpl: async () => new Response('', { status: 429, headers: { 'Retry-After': '999999' } }) }).getYear(2027));
});
test('request timeout and annual deadline fail; concurrent calls bounded to three', async () => {
  const hanging = async (url, options) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => resolve(response(xml())), 200);
    options.signal.addEventListener('abort', () => { clearTimeout(timer); reject(new Error('secret timeout')); }, { once: true });
  });
  await assert.rejects(service({ timeoutMs: 5, fetchImpl: hanging }).getYear(2027), e => e.code === 'UPSTREAM_TIMEOUT');
  const start = performance.now();
  await assert.rejects(service({ timeoutMs: 1000, annualTimeoutMs: 20, fetchImpl: hanging }).getYear(2027), e => e.code === 'UPSTREAM_TIMEOUT' && e.failedMonths.length === 12);
  assert.ok(performance.now() - start < 300);
  let active = 0, max = 0;
  const s = service({ fetchImpl: async url => { active++; max = Math.max(max, active); await new Promise(r => setTimeout(r, 2)); active--; return mockFetch(url); } });
  await Promise.all([s.getYear(2026), s.getYear(2027)]); assert.equal(max, 3);
});
test('service key decoded once; plus preserved; fixed destination; no memory cache reused', async () => {
  const decoded = 'fake+/=key';
  const a = buildUpstreamUrl(2027, 1, 1, decoded), b = buildUpstreamUrl(2027, 1, 1, encodeURIComponent(decoded));
  assert.equal(a.href, b.href); assert.equal(a.searchParams.get('ServiceKey'), decoded); assert.equal(a.origin + a.pathname, ENDPOINT);
  let calls = 0; const s = service({ fetchImpl: async url => { calls++; return mockFetch(url); } });
  await s.getYear(2027); await s.getYear(2027); assert.equal(calls, 24);
});
test('provider call budget capped at 20 pages per month and names reject newline before trim', async () => {
  assert.throws(() => parseHolidayXml(xml(item('20270101', '\nname'), 1)));
  let count = 0;
  await assert.rejects(service({ fetchImpl: async url => {
    if (url.searchParams.get('solMonth') !== '01') return response(xml());
    const page = Number(url.searchParams.get('pageNo')); count++;
    return response(xml(item('20270101', `name${page}`, 'Y', page), 21, page, 1));
  } }).getYear(2027));
  assert.equal(count, MAX_PAGES_PER_MONTH);
});
test('run budget covers concurrent years and every retry, with no requests after exhaustion', async () => {
  assert.equal(MAX_REQUESTS_PER_RUN, 2000);
  let calls = 0;
  const s = service({ maxRequests: 5, fetchImpl: async () => { calls++; return new Response('busy', { status: 429 }); } });
  const results = await Promise.allSettled([s.getYear(2026), s.getYear(2027)]);
  assert.ok(results.every(result => result.status === 'rejected' && result.reason.code === 'REQUEST_BUDGET_EXCEEDED'));
  assert.equal(calls, 5);
  await assert.rejects(s.getYear(1983), e => e.code === 'REQUEST_BUDGET_EXCEEDED'); assert.equal(calls, 5);
  assert.throws(() => createHolidayService({ maxRequests: 2001 }), e => e.code === 'CONFIGURATION_ERROR');
});
test('oversized Content-Length cancels the unread body; malformed UTF-8 never becomes a holiday name', async () => {
  let cancelled = 0, calls = 0;
  const huge = service({ fetchImpl: async () => {
    calls++;
    return new Response(new ReadableStream({ cancel() { cancelled++; } }), { headers: { 'content-length': '1048577' } });
  } });
  await assert.rejects(huge.getYear(2027), e => e.code === 'UPSTREAM_ERROR');
  assert.equal(calls, 12); assert.equal(cancelled, 12);
  calls = 0;
  const malformed = Buffer.from(xml(item('20270101', 'MALFORMED'), 1));
  malformed[malformed.indexOf('MALFORMED')] = 0xff;
  await assert.rejects(service({ fetchImpl: async url => {
    if (url.searchParams.get('solMonth') !== '01') return response(xml());
    calls++; return new Response(malformed);
  } }).getYear(2027), e => e.code === 'UPSTREAM_ERROR' && e.failedMonths.includes(1));
  assert.equal(calls, 1); // Malformed data is a permanent validation error.
});
test('native fetch aborts a stalled streamed response body within request timeout and closes connections', async t => {
  let requests = 0, attempts = 0, active = 0;
  const server = createServer((request, response) => {
    requests++; active++;
    response.on('close', () => { active--; });
    response.writeHead(200, { 'content-type': 'application/xml' });
    response.flushHeaders(); response.write('<response>');
    // Deliberately never finish the body. The service must abort it itself.
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); });
  const local = `http://127.0.0.1:${server.address().port}/stalled-body`;
  const start = performance.now();
  await assert.rejects(service({ timeoutMs: 200, annualTimeoutMs: 5000, fetchImpl: async (url, options) => {
    assert.equal(url.origin + url.pathname, ENDPOINT);
    if (url.searchParams.get('solMonth') !== '01') return response(xml());
    attempts++;
    // Only a test transport rewrite; the loopback URL contains no query/key.
    return fetch(local, options);
  } }).getYear(2027), e => e.code === 'UPSTREAM_TIMEOUT' && e.failedMonths.includes(1));
  assert.equal(attempts, 3);
  // A connection can expire before dispatch on a loaded runner, but at least one
  // received body must be exercised; all three transport attempts are bounded.
  assert.ok(requests >= 1 && requests <= 3); assert.ok(performance.now() - start < 1500);
  for (let i = 0; active && i < 50; i++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(active, 0);
});
