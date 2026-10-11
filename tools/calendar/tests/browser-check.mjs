// Real browser integration against built MkDocs output. All holiday data are fixtures.
import assert from 'node:assert/strict';
import http from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve, extname, relative, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { fixture, NOW } from './fixtures/helpers.mjs';
import { emptyYear, TTL, MAX_STALE } from '../../../docs/assets/calendar/contract.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
const output = resolve(root, 'artifacts/calendar/browser');
await mkdir(output, { recursive: true });
const packagePath = process.env.PLAYWRIGHT_MODULE;
const { chromium } = await import(packagePath ? pathToFileURL(packagePath).href : 'playwright');
const site = resolve(root, 'site');
const server = http.createServer(async (request, response) => {
  try {
    let path = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
    if (path.startsWith('/Workspace/')) path = path.slice('/Workspace'.length);
    if (path.endsWith('/')) path += 'index.html';
    const file = resolve(site, '.' + path), rel = relative(site, file);
    if (isAbsolute(rel) || rel.startsWith('..')) throw new Error();
    const bytes = await readFile(file);
    const types = { '.html': 'text/html; charset=utf-8', '.mjs': 'text/javascript', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.svg': 'image/svg+xml' };
    response.writeHead(200, { 'Content-Type': types[extname(file)] || 'application/octet-stream' }); response.end(bytes);
  } catch { response.writeHead(404); response.end('Not found'); }
});
await new Promise(done => server.listen(0, '127.0.0.1', done));
const base = `http://127.0.0.1:${server.address().port}`;
let browser;
const results = [], errors = [], requests = [];
try {
  browser = await chromium.launch({
    ...(process.env.CALENDAR_BROWSER_EXECUTABLE ? { executablePath: process.env.CALENDAR_BROWSER_EXECUTABLE } : { channel: process.env.CALENDAR_BROWSER || 'msedge' }),
    headless: true,
  });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1050 }, acceptDownloads: true });
  await context.addInitScript(({ now }) => {
    const OriginalDate = Date; window.calendarTestNow = now;
    window.Date = class extends OriginalDate {
      constructor(...args) { super(...(args.length ? args : [window.calendarTestNow])); }
      static now() { return window.calendarTestNow; }
    };
  }, { now: NOW });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => requests.push({ url: request.url(), method: request.method() }));
  let acceptDialogs = true;
  page.on('dialog', dialog => acceptDialogs ? dialog.accept() : dialog.dismiss());
  let data = fixture(), mode = 'ready';
  await page.route('**/assets/calendar/data/calendar.json', async route => {
    if (mode === 'missing') return route.fulfill({ status: 404, body: 'missing' });
    if (mode === 'malformed') return route.fulfill({ contentType: 'application/json', body: '{bad' });
    return route.fulfill({ contentType: 'application/json', body: JSON.stringify(data) });
  });
  const load = async (prefix = '/Workspace') => {
    await page.goto(base + prefix + '/calendar/');
    await page.waitForFunction(() => document.querySelector('#status')?.dataset.state !== 'loading' && document.querySelector('#year')?.value === '2027');
  };
  const state = async expected => { await page.waitForFunction(value => document.querySelector('#status')?.dataset.state === value, expected); };
  const reloadData = async () => { await page.locator('#load').click(); await state('ready'); };
  await load(); await state('ready');
  assert.deepEqual((await page.locator('.md-tabs__list > .md-tabs__item').allTextContents()).map(x => x.trim()), ['Workspace', '달력']);
  assert.equal(await page.locator('#mockBanner').isVisible(), true);
  assert.equal(await page.locator('#download').isDisabled(), true);
  await page.locator('#holidayDate').fill('2027-01-01');
  await page.locator('#holidayName').fill('=SUM(A1:A2)');
  await page.locator('#saveHoliday').click();
  assert.equal(await page.locator('#manualList li').count(), 1);
  acceptDialogs = false;
  await page.locator('#year').fill('2028'); await page.locator('#year').press('Tab');
  assert.equal(await page.locator('#year').inputValue(), '2027');
  assert.equal(await page.locator('#manualList li').count(), 1);
  acceptDialogs = true; await reloadData();
  await page.locator('#previewButton').click();
  assert.equal(await page.locator('#preview .month').count(), 12);
  assert.equal(await page.locator('#preview [data-date]').count(), 365);
  const preview = await page.locator('#preview [data-cell]').evaluateAll(cells => cells.map(cell => ({ cell: cell.dataset.cell, text: cell.textContent, date: cell.dataset.date || null })));
  await writeFile(resolve(output, 'preview-cells.json'), JSON.stringify(preview, null, 2));
  const downloadPromise = page.waitForEvent('download'); await page.locator('#download').click();
  const download = await downloadPromise; assert.equal(download.suggestedFilename(), 'calendar_2027.xlsx');
  await download.saveAs(resolve(output, 'calendar_2027.xlsx'));
  await page.evaluate(() => window.scrollTo({ top: 0, left: 0, behavior: 'instant' }));
  await page.screenshot({ path: resolve(output, 'desktop.png'), fullPage: false, animations: 'disabled' });
  await page.evaluate(() => {
    const month = document.querySelector('#preview .month');
    window.scrollTo({ top: month.getBoundingClientRect().top + window.scrollY - 130, left: 0, behavior: 'instant' });
  });
  await page.screenshot({ path: resolve(output, 'desktop-preview.png'), animations: 'disabled' });
  // Leave room above the whole month so Material's sticky header cannot cover
  // its title during an element screenshot that would otherwise auto-scroll.
  const firstMonthHeight = (await page.locator('#preview .month').first().boundingBox()).height;
  await page.setViewportSize({ width: 1440, height: Math.ceil(firstMonthHeight) + 200 });
  await page.evaluate(() => {
    const month = document.querySelector('#preview .month');
    window.scrollTo({ top: month.getBoundingClientRect().top + window.scrollY - 130, left: 0, behavior: 'instant' });
  });
  await page.locator('#preview .month').first().screenshot({ path: resolve(output, 'desktop-first-month.png'), animations: 'disabled' });
  await page.setViewportSize({ width: 1440, height: 1050 });
  results.push('PC nav Workspace → 달력; /Workspace/ direct URL; JSON fixture; manual input; 12 months/365 dates; download');
  await page.locator('#holidayName').fill('미완성 입력'); assert.equal(await page.locator('#download').isDisabled(), true);
  await page.locator('#cancelEdit').click(); await page.locator('#previewButton').click();
  let downloads = 0; page.on('download', () => downloads++);
  await page.evaluate(() => {
    const raf = window.requestAnimationFrame;
    window.requestAnimationFrame = callback => { window.calendarPendingFrame = callback; return 1; };
    document.querySelector('#download').click();
    document.querySelector('#holidayName').value = '설정 변경';
    document.querySelector('#holidayName').dispatchEvent(new Event('input', { bubbles: true }));
    window.requestAnimationFrame = raf; window.calendarPendingFrame(performance.now());
  });
  await page.waitForFunction(() => document.querySelector('#exportStatus').textContent.includes('취소'));
  assert.equal(downloads, 0); results.push('pending export cancels after input changes; stale preview cannot download');
  await page.locator('#year').fill('2028'); await page.locator('#year').press('Tab');
  assert.equal(await page.locator('#manualList li').count(), 0);
  results.push('year change cancel preserves manual entries; explicit discard clears them');
  await page.reload(); await state('ready'); assert.equal(await page.locator('#manualList li').count(), 0);
  await page.locator('.md-tabs__link').filter({ hasText: /^\s*Workspace\s*$/ }).click();
  await page.locator('.md-tabs__link').filter({ hasText: /^\s*달력\s*$/ }).click(); await state('ready');
  await page.evaluate(async () => {
    const script = document.createElement('script'); script.src = new URL('../assets/calendar/boot.js', location.href).href;
    await new Promise((done, reject) => { script.onload = done; script.onerror = reject; document.head.append(script); });
    window[Symbol.for('workspace.calendar.boot')](); window[Symbol.for('workspace.calendar.boot')]();
  });
  await page.locator('#holidayDate').fill('2027-01-03'); await page.locator('#holidayName').fill('한 번만 추가'); await page.locator('#saveHoliday').click();
  assert.equal(await page.locator('#manualList li').count(), 1);
  results.push('reload/internal re-entry; repeated boot mounting does not duplicate event handlers');
  await page.evaluate(() => { window.calendarTestNow += 24 * 60 * 60 * 1000; });
  await page.locator('#previewButton').click(); await state('stale'); assert.equal(await page.locator('#download').isDisabled(), true);
  await page.locator('#approveStale').click(); await page.locator('#previewButton').click(); assert.equal(await page.locator('#download').isEnabled(), true);
  await page.evaluate(({ now, age }) => { window.calendarTestNow = now + age + 1; }, { now: NOW, age: MAX_STALE });
  await page.locator('#download').click(); await state('error'); assert.equal(await page.locator('#preview .month').count(), 0);
  results.push('open-page 24h stale transition requires consent; 30-day expiry blocks export');
  await page.evaluate(now => { window.calendarTestNow = now; }, NOW);
  for (const scenario of ['missing', 'malformed', 'unavailable', 'unsupported']) {
    mode = scenario; data = fixture();
    if (scenario === 'unavailable') data.years[2027] = emptyYear(2027);
    await load();
    if (scenario === 'unsupported') { await state('ready'); await page.locator('#year').fill('2000'); await page.locator('#load').click(); }
    await state('error'); assert.equal(await page.locator('#previewButton').isDisabled(), true); assert.equal(await page.locator('#download').isDisabled(), true);
  }
  results.push('missing/malformed/unavailable/unsupported do not become no-holidays ready state');
  let confirmations = 0; page.on('dialog', () => confirmations++);
  await page.locator('#manualMode').click(); await page.locator('#manualReview').check(); await page.locator('#previewButton').click();
  assert.equal(confirmations, 2); assert.equal(await page.locator('#preview [data-date]').count(), 366);
  results.push('explicit manual mode and empty-manual second confirmation; unsupported official year still allows manual leap calendar');
  mode = 'ready'; data = fixture(); await load(''); await state('ready');
  results.push('root-path deployment works without hard-coded /Workspace/ asset URLs');
  await page.locator('label[for="__palette_1"]').click();
  assert.equal(await page.locator('body').getAttribute('data-md-color-scheme'), 'slate');
  await page.evaluate(() => window.scrollTo({ top: 0, left: 0, behavior: 'instant' }));
  await page.screenshot({ path: resolve(output, 'dark.png'), animations: 'disabled' });
  await page.setViewportSize({ width: 390, height: 844 }); await load(); await state('ready');
  await page.locator('label.md-header__button[for="__drawer"]').click();
  const mobileItems = await page.locator('nav.md-nav--primary > ul.md-nav__list > li').allTextContents();
  assert.ok(mobileItems[0].includes('Workspace')); assert.ok(mobileItems[1].includes('달력'));
  await page.waitForFunction(() => {
    const drawer = document.querySelector('.md-sidebar--primary').getBoundingClientRect();
    return Math.abs(drawer.left) < 0.5 && drawer.width > 200;
  });
  await page.screenshot({ path: resolve(output, 'mobile-menu.png'), animations: 'disabled' });
  await page.locator('label.md-overlay[for="__drawer"]').click({ position: { x: 370, y: 400 }, force: true });
  await page.locator('#previewButton').click();
  assert.equal(await page.locator('#preview .month').count(), 12);
  const size = await page.evaluate(() => ({ view: innerWidth, document: document.documentElement.scrollWidth, scroll: document.querySelector('.preview-scroll').scrollWidth }));
  assert.ok(size.document <= size.view + 1, JSON.stringify(size)); assert.ok(size.scroll > size.view);
  await page.locator('#year').focus(); await page.keyboard.press('Tab');
  assert.equal(await page.evaluate(() => document.activeElement.id), 'load');
  await page.evaluate(() => window.scrollTo({ top: 0, left: 0, behavior: 'instant' }));
  await page.screenshot({ path: resolve(output, 'mobile.png'), animations: 'disabled' });
  results.push('mobile menu Workspace → 달력; contained preview horizontal scroll; keyboard navigation; dark palette');
  assert.deepEqual(errors, []);
  assert.ok(requests.every(request => request.url.startsWith(base) && request.method === 'GET'));
  await writeFile(resolve(output, 'results.json'), JSON.stringify({ result: 'PASS', browser: await browser.version(), baseHead: '28cce1cb0540b4457d6c5ef8b91cf4c18fe5ee2f', fixture: true, checks: results, pageErrors: errors, requests }, null, 2));
  console.log(JSON.stringify({ result: 'PASS', checks: results, pageErrors: errors, output }, null, 2));
} catch (error) {
  await writeFile(resolve(output, 'results.json'), JSON.stringify({ result: 'FAIL', checks: results, error: error.message, pageErrors: errors }, null, 2));
  throw error;
} finally { await browser?.close(); await new Promise(done => server.close(done)); }
