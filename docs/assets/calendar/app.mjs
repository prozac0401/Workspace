import { nextSeoulYear, yearNumber } from './date-core.mjs';
import { MIN_YEAR, MAX_YEAR } from './contract.mjs';
import { buildCalendar, validateManual, seoulTime, MAX_BACKUP_BYTES, parseManualBackup, serializeManualBackup } from './calendar-model.mjs';
import { DEFAULT_FORMATTING, normalizeFormatting } from './formatting.mjs';
import { MIN_LUNAR_YEAR, MAX_LUNAR_YEAR } from './lunar-calendar.mjs';
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
  let importing = false;
  $('year').min = MIN_YEAR; $('year').max = MAX_YEAR; $('year').value = year;
  const setStatus = (text, state = mode) => {
    $('status').textContent = text; $('status').dataset.state = state;
    $('status').hidden = !text || !['error', 'stale', 'manual'].includes(state);
  };
  const formattingInputs = [...root.querySelectorAll('[data-formatting]')];
  function resetFormatting() {
    for (const input of formattingInputs) input.value = DEFAULT_FORMATTING[input.dataset.formatting];
  }
  function readFormatting() {
    return normalizeFormatting(Object.fromEntries(formattingInputs.map(input => [input.dataset.formatting, input.type === 'number' ? input.valueAsNumber : input.value])));
  }
  function available() {
    return !yearEditing && ['ready', 'stale', 'manual'].includes(mode)
      && (mode !== 'stale' || staleApproved)
      && (mode !== 'manual' || manualApproved && $('manualReview').checked)
      && String(year) === $('year').value;
  }
  function buttons() {
    $('backupManual').disabled = yearEditing || exporting || importing || !manual.length;
    $('importManual').disabled = yearEditing || exporting || importing;
    $('previewButton').disabled = !available() || exporting;
    $('download').disabled = !model || exporting || !available();
    $('download').textContent = year + '년 Excel 다운로드';
    $('manualMode').disabled = exporting;
    $('manualMode').hidden = !['error', 'stale'].includes(mode) || yearEditing;
    $('approveStale').hidden = mode !== 'stale' || staleApproved;
    $('manualReviewWrap').hidden = mode !== 'manual';
    $('mockBanner').hidden = client.dataset?.datasetKind !== 'fixture' || mode === 'manual';
  }
  function invalidate() {
    model = null; $('preview').replaceChildren(); $('empty').hidden = false;
    $('exportStatus').textContent = '미리보기를 만들어 변경한 내용을 확인하세요.';
    buttons();
  }
  function dateBounds() {
    $('holidayDate').min = year + '-01-01'; $('holidayDate').max = year + '-12-31';
    const supportsLunar = year >= MIN_LUNAR_YEAR && year <= MAX_LUNAR_YEAR;
    $('showLunar').disabled = !supportsLunar;
    if (!supportsLunar) $('showLunar').checked = false;
    $('lunarRangeHelp').hidden = supportsLunar;
  }
  function resetEditor() { editId = null; $('holidayForm').reset(); $('saveHoliday').textContent = '추가'; $('cancelEdit').textContent = '입력 비우기'; $('formError').textContent = ''; }
  function renderLists() {
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
    setStatus(yearStatusText, mode); renderLists(); checkFreshness(); buttons();
  }
  function commitYear() {
    let target;
    try {
      target = yearNumber($('year').value);
      if (target < MIN_YEAR || target > MAX_YEAR) throw new Error();
    } catch { setStatus('연도는 ' + MIN_YEAR + '~' + MAX_YEAR + '년 정수로 입력하세요.', 'error'); return false; }
    if (target !== year && (manual.length || $('holidayName').value || $('holidayDate').value)
      && !confirm('연도를 바꾸면 내 일정과 입력 중인 내용이 지워집니다. 계속할까요?')) {
      $('year').value = year; restoreYear(); return false;
    }
    if (target === year) { if (yearEditing) restoreYear(); return true; }
    manual = []; resetEditor(); year = target; yearEditing = false;
    dateBounds(); $('manualReview').checked = false; loadOfficial(); return true;
  }
  function applySelection(result) {
    if (result.error) {
      snapshot = null; mode = 'error'; staleApproved = false;
      setStatus(result.error.code === 'CALENDAR_DATA_EXPIRED'
        ? '공휴일 자료가 오래되어 사용할 수 없습니다. 내 일정만 넣어 만들 수 있습니다.'
        : '이 연도의 공휴일을 사용할 수 없습니다. 내 일정만 넣어 만들 수 있습니다.', 'error');
    } else {
      snapshot = result.snapshot; mode = snapshot.status;
      setStatus(mode === 'stale'
        ? '최근 공휴일 변경이 반영되지 않았을 수 있습니다. 이전 자료를 사용할지 선택하세요.'
        : '');
    }
    renderLists(); buttons();
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
    invalidate(); renderLists(); setStatus('');
    const result = await client.load(requestedYear);
    if (destroyed || result.obsolete || yearEditing || year !== requestedYear) return;
    applySelection(result);
  }
  listen($('year'), 'input', () => {
    if (!yearEditing) yearStatusText = $('status').textContent;
    yearEditing = true; client.invalidate();
    invalidate(); setStatus('', 'idle');
  });
  listen($('year'), 'change', commitYear);
  listen($('year'), 'blur', () => { if (yearEditing) commitYear(); });
  listen($('year'), 'keydown', event => { if (event.key === 'Enter') { event.preventDefault(); $('year').blur(); } });
  listen($('approveStale'), 'click', () => {
    checkFreshness();
    if (mode !== 'stale' || !snapshot) return;
    if (confirm('마지막 성공 수집: ' + seoulTime(snapshot.fetchedAt) + '\n이후 공휴일 변경이 누락될 수 있습니다. 이 이전 자료를 사용할까요?')) {
      staleApproved = true; setStatus('이전 공휴일 자료를 사용합니다.'); buttons();
    }
  });
  listen($('manualMode'), 'click', () => {
    if (!commitYear()) return;
    if (!confirm('공휴일 없이 내 일정만 넣어 만들까요?')) return;
    client.invalidate(); snapshot = null; mode = 'manual'; manualApproved = true; staleApproved = false; $('manualReview').checked = false;
    setStatus('공휴일 없이 내 일정만 사용합니다.'); invalidate(); renderLists();
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
  listen($('backupManual'), 'click', () => {
    try {
      if (yearEditing || exporting || importing) return;
      if ($('holidayName').value || $('holidayDate').value || editId) throw new Error('입력 중인 일정을 먼저 추가하거나 수정 저장해 주세요.');
      const url = URL.createObjectURL(new Blob([serializeManualBackup(year, manual)], { type: 'application/json;charset=utf-8' }));
      const link = document.createElement('a'); link.href = url; link.download = `calendar_manual_${year}.json`;
      document.body.append(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
      $('backupStatus').textContent = `${year}년 일정 ${manual.length}개 백업 다운로드를 시작했습니다.`;
    } catch (error) { $('backupStatus').textContent = error.message; }
  });
  listen($('importManual'), 'click', () => { if (!yearEditing && !exporting && !importing) $('backupFile').click(); });
  listen($('backupFile'), 'change', async () => {
    const file = $('backupFile').files[0]; $('backupFile').value = '';
    if (!file || importing || exporting || yearEditing) return;
    importing = true; buttons();
    const requestedYear = year;
    // A user can change the year or editor while the local file is being read.
    const before = JSON.stringify([manual, editId, $('holidayDate').value, $('holidayName').value, $('category').value]);
    try {
      if (file.size > MAX_BACKUP_BYTES) throw new Error('백업 파일은 128 KiB 이하여야 합니다.');
      const restored = parseManualBackup(await file.text(), requestedYear);
      if (destroyed) return;
      if (yearEditing || year !== requestedYear || exporting || before !== JSON.stringify([manual, editId, $('holidayDate').value, $('holidayName').value, $('category').value])) throw new Error('파일을 읽는 동안 연도나 입력이 바뀌었습니다. 다시 가져오세요.');
      if (!confirm(`${year}년 기존 일정 ${manual.length}개와 입력 중인 내용을 백업 일정 ${restored.length}개로 대체할까요? 기존 내용은 지워집니다.`)) {
        $('backupStatus').textContent = '가져오기를 취소했습니다. 기존 입력을 유지합니다.'; return;
      }
      manual = restored; resetEditor(); $('manualReview').checked = false; invalidate(); renderLists();
      $('backupStatus').textContent = `${year}년 일정 ${manual.length}개를 가져왔습니다. 새 미리보기를 만들어 확인하세요.`;
    } catch (error) { if (!destroyed) $('backupStatus').textContent = error.message + ' 기존 입력은 유지됩니다.'; }
    finally { importing = false; if (!destroyed) buttons(); }
  });
  listen($('manualReview'), 'change', invalidate);
  listen($('showLunar'), 'change', invalidate);
  listen($('formattingForm'), 'submit', event => event.preventDefault());
  for (const input of formattingInputs) {
    listen(input, 'input', invalidate);
    listen(input, 'change', invalidate);
  }
  listen($('resetFormatting'), 'click', () => { resetFormatting(); invalidate(); });
  listen($('previewButton'), 'click', () => {
    try {
      checkFreshness();
      if (!available()) throw new Error('자료 상태와 확인란을 확인하세요.');
      if ($('holidayName').value || $('holidayDate').value || editId) throw new Error('입력 중인 일정을 추가하거나 입력 비우기를 눌러 주세요.');
      if (mode === 'manual' && manual.length === 0 && !confirm('추가한 일정이 없습니다. 공휴일과 일정 없이 만들까요?')) return;
      model = buildCalendar({ year, snapshot, manual, mode, staleApproved, manualApproved, formatting: readFormatting(), showLunar: $('showLunar').checked });
      renderPreview($('preview'), model); $('empty').hidden = true;
      $('exportStatus').textContent = '미리보기와 같은 서식으로 내려받습니다.';
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
      downloadXlsx(selected);
      $('exportStatus').textContent = 'calendar_' + selected.config.year + '.xlsx 다운로드를 시작했습니다.';
    } catch { $('exportStatus').textContent = '파일 생성에 실패했습니다. 다시 다운로드해 주세요.'; }
    finally { exporting = false; buttons(); }
  });
  listen(document, 'visibilitychange', () => { if (!document.hidden) checkFreshness(); });
  // Preview-only scale; keep workbook formatting and the current model intact.
  const preview = $('preview'), previewViewport = preview.parentElement;
  $('originalPreviewSize').checked = false;
  const fitPreview = () => {
    const width = previewViewport.clientWidth;
    if (width > 0) preview.style.zoom = $('originalPreviewSize').checked
      ? 1 : Math.min(1, width / parseFloat(getComputedStyle(preview).minWidth));
  };
  listen($('originalPreviewSize'), 'change', () => {
    fitPreview(); previewViewport.scrollLeft = 0;
  });
  const previewObserver = new ResizeObserver(fitPreview);
  previewObserver.observe(previewViewport); fitPreview();
  const freshnessTimer = setInterval(checkFreshness, 60000);
  resetFormatting(); dateBounds(); renderLists(); buttons(); loadOfficial();
  return { destroy() { destroyed = true; client.invalidate(); events.abort(); clearInterval(freshnessTimer); previewObserver.disconnect(); } };
}
