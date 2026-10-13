// Real browser integration against built MkDocs output. All holiday data are fixtures.
import assert from 'node:assert/strict';
import http from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve, extname, relative, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { fixture, NOW } from './fixtures/helpers.mjs';
const root = fileURLToPath(new URL('../../../', import.meta.url));
const output = resolve(root, process.env.CALENDAR_BROWSER_OUTPUT || 'artifacts/calendar/preview-size');
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
const errors = [], widths = [];
try {
  browser = await chromium.launch({
    ...(process.env.CALENDAR_BROWSER_EXECUTABLE ? { executablePath: process.env.CALENDAR_BROWSER_EXECUTABLE } : { channel: process.env.CALENDAR_BROWSER || 'msedge' }), headless: true,
  });
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, acceptDownloads: true, hasTouch: true });
  await context.addInitScript(({ now }) => {
    const OriginalDate = Date;
    window.Date = class extends OriginalDate {
      constructor(...args) { super(...(args.length ? args : [now])); }
      static now() { return now; }
    };
  }, { now: NOW });
  const page = await context.newPage();
  page.on('pageerror', error => errors.push(error.message));
  let accept = true;
  page.on('dialog', dialog => accept ? dialog.accept() : dialog.dismiss());
  await page.route('**/assets/calendar/data/calendar.json', route => route.fulfill({ contentType: 'application/json', body: JSON.stringify(fixture()) }));
  await page.goto(base + '/Workspace/calendar/');
  await page.waitForFunction(() => !document.querySelector('#previewButton').disabled);
  const toggle = page.locator('#originalPreviewSize');
  assert.equal(await toggle.isChecked(), false);
  await page.locator('#holidayDate').fill('2027-01-04');
  await page.locator('#holidayName').fill('모바일 일정 확인');
  await page.locator('#category').selectOption('company');
  await page.locator('#saveHoliday').click();
  await page.locator('#previewButton').click();
  const cells = await page.locator('#preview [data-cell]').allTextContents();
  assert.equal(await page.locator('#preview .month').count(), 12);
  assert.ok(cells.some(text => text.includes('모바일 일정 확인')));
  const download = async name => {
    const pending = page.waitForEvent('download'); await page.locator('#download').click();
    const result = await pending; assert.equal(result.suggestedFilename(), 'calendar_2027.xlsx');
    const path = resolve(output, name); await result.saveAs(path); return readFile(path);
  };
  const before = await download('fit.xlsx');
  const geometry = () => page.evaluate(() => {
    const p = document.querySelector('#preview'), s = p.parentElement, b = s.getBoundingClientRect();
    return { viewport: innerWidth, document: document.documentElement.scrollWidth, client: s.clientWidth, scroll: s.scrollWidth, zoom: Number(p.style.zoom),
      allFit: [...p.children].every(m => { const r = m.getBoundingClientRect(); return r.left >= b.left - 1 && r.right <= b.right + 1; }),
      monthWidth: p.firstElementChild.getBoundingClientRect().width, scrollLeft: s.scrollLeft,
      font: getComputedStyle(p.querySelector('td')).fontSize };
  });
  for (const width of [390, 360, 320, 804, 820]) {
    await page.setViewportSize({ width, height: 844 });
    await toggle.uncheck();
    await page.waitForFunction(() => {
      const p = document.querySelector('#preview'), s = p.parentElement;
      return Math.abs(Number(p.style.zoom) - Math.min(1, s.clientWidth / 780)) < .001;
    });
    const fit = await geometry();
    assert.ok(fit.allFit && fit.scroll <= fit.client + 1 && fit.document <= width + 1, JSON.stringify(fit));
    await toggle.check();
    const original = await geometry();
    assert.equal(original.zoom, 1); assert.ok(original.monthWidth >= 780);
    assert.equal(original.font, fit.font);
    assert.ok(original.document <= width + 1, JSON.stringify(original));
    if (original.client < 780) {
      assert.ok(original.scroll > original.client);
      await page.locator('.preview-scroll').focus();
      await page.locator('.preview-scroll').press('End');
      await page.evaluate(() => { const s = document.querySelector('.preview-scroll'); s.scrollLeft = s.scrollWidth; });
      const saturday = await page.evaluate(() => {
        const s = document.querySelector('.preview-scroll'), b = s.getBoundingClientRect();
        return [...document.querySelectorAll('#preview .month')].every(m => { const r = m.getBoundingClientRect(); return r.right <= b.right + 1 && r.right > b.left; });
      });
      assert.ok(saturday);
    }
    assert.equal(await page.locator('#download').isEnabled(), true);
    assert.deepEqual(await page.locator('#preview [data-cell]').allTextContents(), cells);
    widths.push({ fit, original });
    await toggle.uncheck();
    assert.equal((await geometry()).scrollLeft, 0);
  }
  await page.setViewportSize({ width: 390, height: 844 }); await toggle.check();
  const after = await download('original.xlsx'); assert.deepEqual(after, before);
  await page.locator('#originalPreviewSize').scrollIntoViewIfNeeded();
  await page.screenshot({ path: resolve(output, 'mobile-original.png') });
  await toggle.uncheck();
  await page.screenshot({ path: resolve(output, 'mobile-fit.png') });
  await toggle.focus(); await toggle.press('Space'); assert.equal(await toggle.isChecked(), true);
  // ResizeObserver must preserve the selected view through rotation and desktop resize.
  await page.setViewportSize({ width: 844, height: 390 }); assert.equal((await geometry()).zoom, 1);
  await page.setViewportSize({ width: 1440, height: 1050 }); assert.equal((await geometry()).zoom, 1);
  await page.locator('#holidayName').fill('입력 중 보존'); await toggle.uncheck(); await toggle.check();
  assert.equal(await page.locator('#holidayName').inputValue(), '입력 중 보존');
  assert.equal(await page.locator('#manualList li').count(), 1);
  accept = false; await page.locator('#year').fill('2028'); await page.locator('#year').press('Tab');
  assert.equal(await page.locator('#year').inputValue(), '2027');
  assert.equal(await page.locator('#holidayName').inputValue(), '입력 중 보존');
  accept = true; await page.locator('#cancelEdit').click();
  await page.locator('#year').fill('2028'); await page.locator('#year').press('Tab');
  await page.waitForFunction(() => !document.querySelector('#previewButton').disabled);
  assert.equal(await page.locator('#manualList li').count(), 0);
  assert.equal(await toggle.isChecked(), true);
  await page.locator('#previewButton').click();
  assert.equal(await page.locator('#preview [data-date]').count(), 366);
  assert.equal(await page.locator('#download').isEnabled(), true);
  await page.reload(); await page.waitForFunction(() => !document.querySelector('#previewButton').disabled);
  assert.equal(await toggle.isChecked(), false);
  assert.deepEqual(errors, []);
  const result = { result: 'PASS', browser: await browser.version(), sourceHead, sourceDirty, fixture: true, widths,
    checks: ['fit/original views and contained horizontal scroll', 'same 12 months and date/event text; identical XLSX bytes', 'keyboard toggle, resize, year cancellation/commit and unsaved input preservation', 'reload defaults to fit'], pageErrors: errors };
  await writeFile(resolve(output, 'results.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  await writeFile(resolve(output, 'failure.json'), JSON.stringify({ result: 'FAIL', error: error.stack, widths, pageErrors: errors }, null, 2));
  throw error;
} finally { await browser?.close(); await new Promise(done => server.close(done)); }
