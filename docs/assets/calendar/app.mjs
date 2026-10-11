import { nextSeoulYear, yearNumber } from './date-core.mjs';
import { MIN_YEAR, MAX_YEAR, FRESH_DAYS } from './contract.mjs';
import { buildCalendar, validateManual, seoulTime } from './calendar-model.mjs';
import { HolidayClient } from './holiday-client.mjs';
import { renderPreview } from './preview-renderer.mjs';
import { downloadXlsx } from './xlsx-exporter.mjs';

// The original draft's UI flow is retained; only its source is now static JSON.
export function initCalendar(root) {
  const $ = id => root.querySelector('#' + id);
  const client = new HolidayClient();
  const events = new AbortController();
  const listen = (element, event, handler) => element.addEventListener(event, handler, { signal: events.signal });
  let year = Math.max(MIN_YEAR, Math.min(MAX_YEAR, nextSeoulYear())), manual = [], snapshot = null, model = null;
  let mode = 'idle', staleApproved = false, manualApproved = false, editId = null, exporting = false, destroyed = false;
  let yearEditing = false, yearStatusText = '';
  $('year').min = MIN_YEAR; $('year').max = MAX_YEAR; $('year').value = year;
  const setStatus = (text, state = mode) => { $('status').textContent = text; $('status').dataset.state = state; };
  function available() {
    return !yearEditing && ['ready', 'stale', 'manual'].includes(mode)
      && (mode !== 'stale' || staleApproved)
      && (mode !== 'manual' || manualApproved && $('manualReview').checked)
      && String(year) === $('year').value;
  }
  function buttons() {
    $('previewButton').disabled = !available() || exporting;
    $('download').disabled = !model || exporting || !available();
    $('download').textContent = year + '년 Excel 다운로드';
    $('manualMode').disabled = exporting;
    $('progress').hidden = mode !== 'loading' || yearEditing;
    $('approveStale').hidden = mode !== 'stale' || staleApproved;
    $('manualReviewWrap').hidden = mode !== 'manual';
    const count = yearEditing ? '미확인 (연도 입력 중)' : mode === 'manual' ? '미확인 (수동 모드)' : snapshot ? snapshot.holidays.length + '건' : '미확인';
    $('holidaySummary').textContent = '휴일 목록 확인 · ' + (snapshot?.mock ? '가상 공식 ' : '공식 ') + count + ' / 수동 ' + manual.length + '건';
  }
  function invalidate() {
    model = null; $('preview').replaceChildren(); $('empty').hidden = false;
    $('exportStatus').textContent = '설정 또는 자료 상태가 바뀌었습니다. 새 미리보기를 만들어 주세요.';
    buttons();
  }
  function dateBounds() { $('holidayDate').min = year + '-01-01'; $('holidayDate').max = year + '-12-31'; }
  function resetEditor() { editId = null; $('holidayForm').reset(); $('saveHoliday').textContent = '휴일 추가'; $('cancelEdit').textContent = '입력 비우기'; $('formError').textContent = ''; }
  function showAvailability() {
    const data = client.dataset;
    $('availabilityList').replaceChildren();
    $('mockBanner').hidden = data?.datasetKind !== 'fixture' || mode === 'manual';
    if (!data) {
      const li = document.createElement('li'); li.textContent = '공개 자료 준비 상태를 확인하지 못했습니다.'; $('availabilityList').append(li); return;
    }
    for (const target of data.targetYears) {
      const entry = data.years[String(target)], selected = client.current(target);
      const li = document.createElement('li');
      const label = selected.error ? selected.error.code === 'CALENDAR_DATA_EXPIRED' ? '사용 상한 초과' : selected.error.code === 'CALENDAR_YEAR_UNSUPPORTED' ? '현재 지원 대상 아님' : entry?.status === 'error' ? '수집 오류 · 완전한 자료 없음' : '미제공 · 아직 준비되지 않음' : selected.snapshot.status === 'stale' ? '이전 자료 · 동의 필요' : '준비됨';
      li.textContent = target + '년 · ' + label + ' · 마지막 성공 수집: ' + seoulTime(entry?.lastSuccessfulFetchAt);
      if (entry?.status === 'preserved') li.textContent += ' · 최근 수집 실패로 이전 정상 자료 보존';
      $('availabilityList').append(li);
    }
  }
  function showSource() {
    if (snapshot) {
      $('sourceDetails').textContent = (snapshot.mock ? '출처: 검증용 가상 자료 (실제 공식 자료 아님)' : '출처: 한국천문연구원 getRestDeInfo')
        + '\n마지막 성공 수집: ' + seoulTime(snapshot.fetchedAt)
        + '\n' + snapshot.warnings.join('\n');
    } else if (mode === 'manual') $('sourceDetails').textContent = '출처: 브라우저에 직접 입력한 수동 자료 · 공식 자료 미확인';
    else {
      const entry = client.dataset?.years[String(year)];
      $('sourceDetails').textContent = '출처: 한국천문연구원 getRestDeInfo · 선택 연도 자료 사용 불가'
        + '\n마지막 성공 수집: ' + seoulTime(entry?.lastSuccessfulFetchAt);
    }
    showAvailability();
  }
  function renderLists() {
    $('officialList').replaceChildren();
    if (mode !== 'manual' && snapshot) for (const item of snapshot.holidays) {
      const li = document.createElement('li'); li.textContent = item.date + ' · ' + item.name + (snapshot.mock ? ' (가상 자료)' : ' (공식)'); $('officialList').append(li);
    }
    if (!$('officialList').childNodes.length) { const li = document.createElement('li'); li.textContent = '확인된 공식 목록이 없습니다.'; $('officialList').append(li); }
    $('manualList').replaceChildren();
    for (const item of [...manual].sort((a, b) => a.date.localeCompare(b.date) || a.name.localeCompare(b.name))) {
      const li = document.createElement('li'), text = document.createElement('div');
      text.textContent = item.date + ' · [' + (item.category === 'company' ? '회사' : '개인') + '] ' + item.name;
      const edit = document.createElement('button'); edit.type = 'button'; edit.textContent = '수정'; edit.setAttribute('aria-label', item.name + ' 수정');
      edit.onclick = () => { editId = item.sourceId; $('holidayDate').value = item.date; $('holidayName').value = item.name; $('category').value = item.category; $('saveHoliday').textContent = '수정 저장'; $('cancelEdit').textContent = '수정 취소'; invalidate(); $('holidayName').focus(); };
      const remove = document.createElement('button'); remove.type = 'button'; remove.textContent = '삭제'; remove.setAttribute('aria-label', item.name + ' 삭제');
      remove.onclick = () => { manual = manual.filter(x => x.sourceId !== item.sourceId); if (editId === item.sourceId) resetEditor(); $('manualReview').checked = false; invalidate(); renderLists(); };
      li.append(text, edit, remove); $('manualList').append(li);
    }
    buttons();
  }
  function restoreYear() {
    yearEditing = false;
    if (mode === 'loading') { loadOfficial(); return; }
    setStatus(yearStatusText, mode); showSource(); renderLists(); checkFreshness(); buttons();
  }
  function commitYear() {
    let target;
    try {
      target = yearNumber($('year').value);
      if (target < MIN_YEAR || target > MAX_YEAR) throw new Error();
    } catch { setStatus('연도는 ' + MIN_YEAR + '~' + MAX_YEAR + '년 정수로 입력하세요.', 'error'); return false; }
    if (target !== year && (manual.length || $('holidayName').value || $('holidayDate').value)
      && !confirm('연도를 바꾸면 현재 수동 휴일 목록과 입력 중인 내용을 버립니다. 계속할까요?')) {
      $('year').value = year; restoreYear(); return false;
    }
    if (target === year) { if (yearEditing) restoreYear(); return true; }
    manual = []; resetEditor(); year = target; yearEditing = false;
    dateBounds(); $('manualReview').checked = false; loadOfficial(); return true;
  }
  function applySelection(result) {
    if (result.error) {
      snapshot = null; mode = 'error'; staleApproved = false;
      setStatus(result.error.message + '\n' + result.error.code, 'error');
    } else {
      snapshot = result.snapshot; mode = snapshot.status;
      setStatus(mode === 'stale'
        ? '이전 완전 자료입니다. ' + FRESH_DAYS + '일이 지났거나 최근 수집이 실패하여 변경된 공휴일이 누락될 수 있습니다. 기준 시각과 경고를 확인하고 사용 여부를 선택하세요.'
        : '12개월 수집·검증 자료 준비 · ' + snapshot.holidays.length + '건. 이후 지정될 임시공휴일까지 확정된 것은 아닙니다.' + (snapshot.mock ? '\n검증용 가상 자료이며 실제 공휴일은 확인하지 않았습니다.' : ''));
    }
    showSource(); renderLists(); buttons();
  }
  // Re-evaluate age and Seoul year at each action; a long-open page cannot keep a ready preview indefinitely.
  function checkFreshness() {
    if (yearEditing || !['ready', 'stale'].includes(mode)) return;
    const result = client.current(year);
    if (result.error || result.snapshot.status !== mode || result.snapshot.snapshotId !== snapshot?.snapshotId) {
      staleApproved = false; invalidate(); applySelection(result); invalidate();
    }
  }
  async function loadOfficial() {
    const requestedYear = year;
    mode = 'loading'; snapshot = null; manualApproved = false; staleApproved = false;
    invalidate(); renderLists(); setStatus('사이트에 공개된 공휴일 자료를 읽고 있습니다.');
    const result = await client.load(requestedYear);
    if (destroyed || result.obsolete || yearEditing || year !== requestedYear) return;
    applySelection(result);
  }
  listen($('year'), 'input', () => {
    if (!yearEditing) yearStatusText = $('status').textContent;
    yearEditing = true; client.invalidate();
    $('sourceDetails').textContent = ''; invalidate();
    setStatus('연도를 입력한 뒤 Enter를 누르거나 다른 항목으로 이동하면 공개 자료를 자동으로 확인합니다.', 'idle');
  });
  listen($('year'), 'change', commitYear);
  listen($('year'), 'blur', () => { if (yearEditing) commitYear(); });
  listen($('year'), 'keydown', event => { if (event.key === 'Enter') { event.preventDefault(); $('year').blur(); } });
  listen($('approveStale'), 'click', () => {
    checkFreshness();
    if (mode !== 'stale' || !snapshot) return;
    if (confirm('마지막 성공 수집: ' + seoulTime(snapshot.fetchedAt) + '\n이후 공휴일 변경이 누락될 수 있습니다. 이 이전 자료를 사용할까요?')) {
      staleApproved = true; setStatus('이전 완전 자료 사용을 확인했습니다. 새 미리보기를 만들어 주세요.'); buttons();
    }
  });
  listen($('manualMode'), 'click', () => {
    if (!commitYear()) return;
    if (!confirm('공식 공휴일을 확인하지 않고 수동 자료만 사용합니다. 공식 공휴일 누락 가능성을 이해하고 진행할까요?')) return;
    client.invalidate(); snapshot = null; mode = 'manual'; manualApproved = true; staleApproved = false; $('manualReview').checked = false;
    setStatus('수동 모드 · 공식 공휴일 미확인\n수동 목록을 검토하고 확인란을 선택하세요.'); showSource(); invalidate(); renderLists();
  });
  listen($('holidayForm'), 'submit', event => {
    event.preventDefault();
    try {
      if (yearEditing || String(year) !== $('year').value) throw new Error('먼저 연도 변경을 완료하세요.');
      const record = validateManual({ date: $('holidayDate').value, name: $('holidayName').value, category: $('category').value }, year, manual, editId);
      manual = [...manual.filter(x => x.sourceId !== editId), record]; resetEditor(); $('manualReview').checked = false; invalidate(); renderLists();
    } catch (error) { $('formError').textContent = error.message; }
  });
  for (const id of ['holidayDate', 'holidayName', 'category']) listen($(id), 'input', invalidate);
  listen($('cancelEdit'), 'click', () => { resetEditor(); invalidate(); });
  listen($('manualReview'), 'change', invalidate);
  listen($('previewButton'), 'click', () => {
    try {
      checkFreshness();
      if (!available()) throw new Error('자료 상태와 확인란을 확인하세요.');
      if ($('holidayName').value || $('holidayDate').value || editId) throw new Error('입력 중인 휴일을 추가·저장하거나 입력 비우기로 비운 뒤 미리보기를 만드세요.');
      if (mode === 'manual' && manual.length === 0 && !confirm('수동 휴일도 0개입니다. 공휴일 표시 없이 주말만 구분한 달력을 만들까요?')) return;
      model = buildCalendar({ year, snapshot, manual, mode, staleApproved, manualApproved });
      renderPreview($('preview'), model); $('empty').hidden = true;
      $('exportStatus').textContent = '미리보기 준비 완료 · ' + model.months.reduce((n, m) => n + m.days, 0) + '일 · 이 자료 그대로 내려받습니다.' + (model.isMock ? ' 검증용 가상 자료입니다.' : '');
      buttons();
    } catch (error) { model = null; $('exportStatus').textContent = error.message; buttons(); }
  });
  listen($('download'), 'click', async () => {
    checkFreshness();
    if (!model || exporting || !available()) return;
    const selected = model; exporting = true; buttons(); $('exportStatus').textContent = 'Excel 파일 생성 중…';
    try {
      await new Promise(resolve => requestAnimationFrame(resolve));
      checkFreshness();
      if (destroyed || model !== selected || !available()) {
        $('exportStatus').textContent = '설정 또는 자료 상태가 바뀌어 다운로드를 취소했습니다. 새 미리보기를 만들어 주세요.'; return;
      }
      const size = downloadXlsx(selected);
      $('exportStatus').textContent = '파일 생성 완료 · calendar_' + selected.config.year + '.xlsx · ' + Math.ceil(size / 1024) + ' KB. 브라우저 다운로드 목록에서 확인하세요.';
    } catch { $('exportStatus').textContent = '파일 생성에 실패했습니다. 다시 다운로드해 주세요.'; }
    finally { exporting = false; buttons(); }
  });
  listen(document, 'visibilitychange', () => { if (!document.hidden) checkFreshness(); });
  const freshnessTimer = setInterval(checkFreshness, 60000);
  dateBounds(); renderLists(); buttons(); loadOfficial();
  return { destroy() { destroyed = true; client.invalidate(); events.abort(); clearInterval(freshnessTimer); } };
}
