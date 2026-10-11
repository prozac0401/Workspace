// Real browser integration against built MkDocs output. All holiday data are fixtures.
import assert from 'node:assert/strict';
import http from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve, extname, relative, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { fixture, NOW } from './fixtures/helpers.mjs';
import { emptyYear, TTL, MAX_STALE } from '../../../docs/assets/calendar/contract.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
const output = resolve(root, process.env.CALENDAR_BROWSER_OUTPUT || 'artifacts/calendar/browser');
const execute = promisify(execFile);
const sourceHead = (await execute('git', ['rev-parse', 'HEAD'], { cwd: root, windowsHide: true })).stdout.trim();
const sourceDirty = (await execute('git', ['status', '--porcelain'], { cwd: root, windowsHide: true })).stdout.trim().length > 0;
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
const results = [], errors = [], requests = [], downloadedYears = [];
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
  let data = fixture(), mode = 'ready', delayNext = false, releaseDelayed = null, delayedFinished = null;
  await page.route('**/assets/calendar/data/calendar.json', async route => {
    if (delayNext) {
      delayNext = false; const body = JSON.stringify(data);
      let finish; delayedFinished = new Promise(resolve => { finish = resolve; });
      await new Promise(resolve => { releaseDelayed = resolve; });
      try { await route.fulfill({ contentType: 'application/json', body }); } catch { /* The previous year request was intentionally aborted. */ }
      finish(); return;
    }
    if (mode === 'missing') return route.fulfill({ status: 404, body: 'missing' });
    if (mode === 'malformed') return route.fulfill({ contentType: 'application/json', body: '{bad' });
    return route.fulfill({ contentType: 'application/json', body: JSON.stringify(data) });
  });
  const load = async (prefix = '/Workspace') => {
    await page.goto(base + prefix + '/calendar/');
    await page.waitForFunction(() => document.querySelector('#status')?.dataset.state !== 'loading' && document.querySelector('#year')?.value === '2027');
  };
  const state = async expected => { await page.waitForFunction(value => document.querySelector('#status')?.dataset.state === value, expected); };
  const selectYear = async (year, expected = 'ready', key = 'Tab') => {
    await page.locator('#year').fill(String(year)); await page.locator('#year').press(key); await state(expected);
  };
  await load(); await state('ready');
  assert.equal(await page.locator('#load').count(), 0);
  assert.equal(await page.getByRole('button', { name: '공휴일 자료 다시 읽기', exact: true }).count(), 0);
  assert.deepEqual((await page.locator('.md-tabs__list > .md-tabs__item').allTextContents()).map(x => x.trim()), ['Workspace', '달력']);
  assert.equal(await page.locator('#mockBanner').isVisible(), true);
  assert.equal(await page.locator('#download').isDisabled(), true);
  await page.locator('#holidayDate').fill('2027-01-01');
  await page.locator('#holidayName').fill('=SUM(A1:A2)');
  await page.locator('#saveHoliday').click();
  assert.equal(await page.locator('#manualList li').count(), 1);
  await page.locator('#holidayDate').fill('2027-02-01'); await page.locator('#holidayName').fill('입력 중 보존');
  await page.locator('#category').selectOption('personal');
  const sourceBeforeCancel = await page.locator('#sourceDetails').textContent();
  const jsonReadsBeforeCancel = requests.filter(request => request.url.endsWith('/data/calendar.json')).length;
  acceptDialogs = false;
  await page.locator('#year').fill('2028'); await page.locator('#year').press('Tab'); await state('ready');
  assert.equal(await page.locator('#year').inputValue(), '2027');
  assert.equal(await page.locator('#manualList li').count(), 1);
  assert.equal(await page.locator('#holidayDate').inputValue(), '2027-02-01');
  assert.equal(await page.locator('#holidayName').inputValue(), '입력 중 보존');
  assert.equal(await page.locator('#category').inputValue(), 'personal');
  assert.equal(await page.locator('#sourceDetails').textContent(), sourceBeforeCancel);
  assert.equal(requests.filter(request => request.url.endsWith('/data/calendar.json')).length, jsonReadsBeforeCancel);
  assert.equal(await page.locator('#previewButton').isEnabled(), true);
  acceptDialogs = true; await page.locator('#cancelEdit').click();
  await page.locator('#previewButton').click();
  assert.equal(await page.locator('#preview .month').count(), 12);
  assert.equal(await page.locator('#preview [data-date]').count(), 365);
  const preview = await page.locator('#preview [data-cell]').evaluateAll(cells => cells.map(cell => ({ cell: cell.dataset.cell, text: cell.textContent, date: cell.dataset.date || null })));
  await writeFile(resolve(output, 'preview-cells.json'), JSON.stringify(preview, null, 2));
  const downloadPromise = page.waitForEvent('download'); await page.locator('#download').click();
  const download = await downloadPromise; assert.equal(download.suggestedFilename(), 'calendar_2027.xlsx');
  await download.saveAs(resolve(output, 'calendar_2027.xlsx'));
  downloadedYears.push({ year: 2027, mode: 'fixture' });
  assert.equal(await page.locator('#download').textContent(), '2027년 Excel 다운로드');
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
  results.push('PC nav Workspace → 달력; direct URL automatically loads JSON without refresh button; manual input; 12 months/365 dates; download');
  await page.locator('#year').fill('20');
  assert.equal(await page.locator('#download').isDisabled(), true); assert.equal(await page.locator('#previewButton').isDisabled(), true);
  await page.locator('#year').fill('2027'); await page.locator('#year').press('Enter'); await state('ready');
  assert.equal(await page.locator('#manualList li').count(), 1);
  assert.equal(await page.locator('#sourceDetails').textContent(), sourceBeforeCancel);
  await page.locator('#year').fill('202'); await page.locator('#year').fill('2027'); await page.locator('#year').press('Tab'); await state('ready');
  assert.equal(await page.locator('#previewButton').isEnabled(), true);
  results.push('incomplete year input blocks preview/download; Enter and blur restore unchanged selected year');
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
  await state('ready');
  assert.equal(await page.locator('#year').inputValue(), '2028');
  assert.equal(await page.locator('#download').textContent(), '2028년 Excel 다운로드');
  results.push('cancel restores original source and manual list/editor; accepted year change clears entries and automatically loads selected year');
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
  await page.evaluate(ttl => { window.calendarTestNow += ttl; }, TTL);
  await page.locator('#previewButton').click(); await state('stale'); assert.equal(await page.locator('#download').isDisabled(), true);
  assert.match(await page.locator('#status').textContent(), /32일/);
  await page.locator('#approveStale').click(); await page.locator('#previewButton').click(); assert.equal(await page.locator('#download').isEnabled(), true);
  await page.evaluate(({ now, age }) => { window.calendarTestNow = now + age + 1; }, { now: NOW, age: MAX_STALE });
  await page.locator('#download').click(); await state('error'); assert.equal(await page.locator('#preview .month').count(), 0);
  assert.match(await page.locator('#status').textContent(), /35일/);
  results.push('open-page 32-day stale transition requires consent; over-35-day expiry blocks export');
  await page.evaluate(now => { window.calendarTestNow = now; }, NOW);

  mode = 'ready'; data = fixture();
  for (const selectedYear of [1983, 2026]) {
    await load(); await state('ready');
    await selectYear(selectedYear, 'ready', selectedYear === 1983 ? 'Enter' : 'Tab');
    assert.equal(await page.locator('#download').textContent(), selectedYear + '년 Excel 다운로드');
    await page.locator('#previewButton').click();
    assert.equal(await page.locator('#preview [data-date]').count(), 365);
    assert.equal(await page.locator('#preview [data-date]').first().getAttribute('data-date'), selectedYear + '-01-01');
    const selectedCells = await page.locator('#preview [data-cell]').evaluateAll(cells => cells.map(cell => ({ cell: cell.dataset.cell, text: cell.textContent, date: cell.dataset.date || null })));
    await writeFile(resolve(output, 'preview-cells-' + selectedYear + '.json'), JSON.stringify(selectedCells, null, 2));
    const pending = page.waitForEvent('download'); await page.locator('#download').click();
    const selectedFile = await pending; assert.equal(selectedFile.suggestedFilename(), 'calendar_' + selectedYear + '.xlsx');
    await selectedFile.saveAs(resolve(output, 'calendar_' + selectedYear + '.xlsx'));
    downloadedYears.push({ year: selectedYear, mode: 'fixture' });
  }
  results.push('1983 and 2026 selection each exports its own 365-day workbook; year shown on download button');
  mode = 'ready'; data = fixture(); await load(); await state('ready');
  data.years[2026].holidays[0].name = '이전 연도 지연자료';
  delayNext = true;
  const oldRequest = page.waitForRequest(request => request.url().endsWith('/data/calendar.json'));
  await page.locator('#year').fill('2026'); await page.locator('#year').press('Tab'); await oldRequest;
  await state('loading');
  await selectYear(1983, 'ready', 'Enter');
  await page.locator('#previewButton').click();
  assert.equal(await page.locator('#preview [data-date]').first().getAttribute('data-date'), '1983-01-01');
  releaseDelayed(); await delayedFinished;
  await page.evaluate(() => new Promise(requestAnimationFrame));
  assert.equal(await page.locator('#year').inputValue(), '1983');
  assert.equal(await page.locator('#preview [data-date]').first().getAttribute('data-date'), '1983-01-01');
  assert.equal((await page.locator('#officialList').textContent()).includes('이전 연도 지연자료'), false);
  results.push('automatic year loads discard delayed previous-year responses and retain latest preview');
  for (const outsideYear of [1982, 2100]) {
    await selectYear(outsideYear, 'error');
    assert.match(await page.locator('#status').textContent(), /1983~2099/);
    assert.equal(await page.locator('#previewButton').isDisabled(), true); assert.equal(await page.locator('#download').isDisabled(), true);
    await page.locator('#manualMode').click(); await state('error');
    assert.equal(await page.locator('#manualReviewWrap').isVisible(), false);
  }
  results.push('1982 and 2100 are rejected for both official and manual modes');
  for (const scenario of ['missing', 'malformed', 'unavailable']) {
    mode = scenario; data = fixture();
    if (scenario === 'unavailable') data.years[2027] = emptyYear(2027);
    await load();
    await state('error'); assert.equal(await page.locator('#previewButton').isDisabled(), true); assert.equal(await page.locator('#download').isDisabled(), true);
  }
  results.push('missing/malformed/unavailable do not become no-holidays ready state');
  mode = 'ready'; data = fixture(); data.years[2099] = emptyYear(2099);
  await load(); await state('ready');
  await selectYear(2099, 'error');
  assert.equal(await page.locator('#download').isDisabled(), true);
  acceptDialogs = false; await page.locator('#manualMode').click();
  assert.equal(await page.locator('#manualReviewWrap').isVisible(), false); assert.equal(await page.locator('#previewButton').isDisabled(), true);
  acceptDialogs = true;
  let confirmations = 0; page.on('dialog', () => confirmations++);
  await page.locator('#manualMode').click(); await page.locator('#manualReview').check(); await page.locator('#previewButton').click();
  assert.equal(confirmations, 2); assert.equal(await page.locator('#preview [data-date]').count(), 365);
  assert.match(await page.locator('#preview .preview-metadata').textContent(), /수동 자료만 사용/);
  assert.equal(await page.locator('#mockBanner').isVisible(), false);
  assert.equal(await page.locator('#download').textContent(), '2099년 Excel 다운로드');
  const manualCells = await page.locator('#preview [data-cell]').evaluateAll(cells => cells.map(cell => ({ cell: cell.dataset.cell, text: cell.textContent, date: cell.dataset.date || null })));
  await writeFile(resolve(output, 'preview-cells-2099.json'), JSON.stringify(manualCells, null, 2));
  const manualPending = page.waitForEvent('download'); await page.locator('#download').click();
  const manualFile = await manualPending; assert.equal(manualFile.suggestedFilename(), 'calendar_2099.xlsx');
  await manualFile.saveAs(resolve(output, 'calendar_2099.xlsx')); downloadedYears.push({ year: 2099, mode: 'manual' });
  results.push('2099 unavailable official data blocks export; manual decline blocks preview; explicit manual and empty-list confirmations allow manual-only download');
  await page.locator('#holidayDate').fill('2099-02-03'); await page.locator('#holidayName').fill('수동 목록 보존'); await page.locator('#saveHoliday').click();
  await page.locator('#manualReview').check();
  const manualSource = await page.locator('#sourceDetails').textContent();
  acceptDialogs = false; await page.locator('#year').fill('2098'); await page.locator('#year').press('Tab');
  await state('manual'); assert.equal(await page.locator('#year').inputValue(), '2099');
  assert.equal(await page.locator('#manualList li').count(), 1); assert.equal(await page.locator('#manualReview').isChecked(), true);
  assert.equal(await page.locator('#sourceDetails').textContent(), manualSource); assert.equal(await page.locator('#previewButton').isEnabled(), true);
  acceptDialogs = true;
  results.push('manual-mode year discard cancellation preserves mode, consent, source and manual entries');
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
  assert.equal(await page.evaluate(() => document.activeElement.id), 'manualMode');
  await page.evaluate(() => window.scrollTo({ top: 0, left: 0, behavior: 'instant' }));
  await page.screenshot({ path: resolve(output, 'mobile.png'), animations: 'disabled' });
  results.push('mobile menu Workspace → 달력; contained preview horizontal scroll; keyboard navigation; dark palette');
  assert.deepEqual(errors, []);
  assert.ok(requests.every(request => request.url.startsWith(base) && request.method === 'GET'));
  await writeFile(resolve(output, 'results.json'), JSON.stringify({ result: 'PASS', browser: await browser.version(), sourceHead, sourceDirty, fixture: true, downloadedYears, checks: results, pageErrors: errors, requests }, null, 2));
  console.log(JSON.stringify({ result: 'PASS', sourceHead, sourceDirty, downloadedYears, checks: results, pageErrors: errors, output }, null, 2));
} catch (error) {
  await writeFile(resolve(output, 'results.json'), JSON.stringify({ result: 'FAIL', checks: results, error: error.message, pageErrors: errors }, null, 2));
  throw error;
} finally { await browser?.close(); await new Promise(done => server.close(done)); }
