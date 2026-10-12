import test from 'node:test';
import assert from 'node:assert/strict';
import { buildCalendar, validateManual, parseManualBackup, serializeManualBackup, MAX_BACKUP_BYTES } from '../../../docs/assets/calendar/calendar-model.mjs';
import { workbookParts } from '../../../docs/assets/calendar/xlsx-exporter.mjs';
import { renderPreview } from '../../../docs/assets/calendar/preview-renderer.mjs';
import { initCalendar } from '../../../docs/assets/calendar/app.mjs';
const entry = { date: '2027-01-04', name: '회사 일정', category: 'company' };
const backup = entries => JSON.stringify({ format: 'workspace-calendar-manual', version: 1, year: 2027, entries });
test('backup round trip normalizes names, projects only manual fields and assigns fresh IDs', () => {
  const original = [validateManual({ ...entry, name: '  회사 일정  ' }, 2027), validateManual({ ...entry, category: 'personal' }, 2027)];
  const text = serializeManualBackup(2027, original), restored = parseManualBackup(text, 2027);
  assert.deepEqual(JSON.parse(text).entries, original.map(({date,name,category}) => ({date,name,category})));
  assert.notEqual(restored[0].sourceId, original[0].sourceId);
  assert.equal(new Set(restored.map(x => x.sourceId)).size, 2);
  assert.deepEqual(parseManualBackup(backup([]), 2027), []);
});
test('backup rejects malformed envelopes, unsupported versions, wrong year and byte limits', () => {
  for (const text of ['{', 'null', '[]', '{}', backup([]).replace('"version":1', '"version":2'), backup([]).replace('"year":2027', '"year":"2027"'), backup([]).replace('"year":2027', '"year":2100'), backup([]).replace('"entries":[]', '"entries":[],"extra":0'), '가'.repeat(MAX_BACKUP_BYTES)]) assert.throws(() => parseManualBackup(text, 2027));
  assert.throws(() => parseManualBackup(backup([]), 2028), /연도를 먼저/);
});
test('backup reuses date, category, name, normalized duplicate and 100 item validation', () => {
  for (const entries of [null, {}, [null], [1], [{...entry, date:'2027-02-29'}], [{...entry, date:'2028-01-01'}], [{...entry, category:'official'}], [{...entry, name:''}], [{...entry, name:'a\nb'}], [{...entry, name:'a'.repeat(51)}], [{...entry, sourceId:'fake'}], [entry,{...entry,name:' 회사 일정 '}], [{...entry,name:'é'},{...entry,name:'e\u0301'}]]) assert.throws(() => parseManualBackup(backup(entries), 2027));
  const entries = Array.from({length:100}, (_, i) => ({...entry,name:String(i)}));
  assert.equal(parseManualBackup(backup(entries),2027).length,100);
  assert.throws(() => parseManualBackup(backup([...entries,{...entry,name:'101'}]),2027));
});
// Minimal DOM adapter exercises actual app handlers and renderer without a browser dependency.
class Element {
  constructor() { this.value=''; this.checked=false; this.dataset={}; this.children=[]; this.handlers={}; this.style={setProperty(){}}; this.files=[]; this.parentElement={clientWidth:800}; }
  get value() { return this._value; }
  set value(value) { this._value=String(value); }
  addEventListener(event,handler) { this.handlers[event]=handler; }
  async fire(event) { return this.handlers[event]?.({preventDefault(){}}); }
  append(...items) { this.children.push(...items); }
  replaceChildren(...items) { this.children=items; }
  setAttribute() {} focus() {} click() {} remove() {}
  reset() { for(const id of ['holidayDate','holidayName']) elements[id].value=''; elements.category.value='personal'; }
}
let elements;
function dom() {
  elements = Object.fromEntries(['year','status','previewButton','download','manualMode','approveStale','manualReviewWrap','mockBanner','preview','empty','exportStatus','holidayDate','showLunar','lunarRangeHelp','holidayForm','saveHoliday','cancelEdit','formError','manualList','holidayName','category','manualReview','formattingForm','resetFormatting','backupManual','importManual','backupFile','backupStatus'].map(id => [id,new Element()]));
  elements.category.value='personal';
  globalThis.document={querySelector(){},hidden:false,addEventListener(){},createElement:()=>new Element(),createDocumentFragment:()=>new Element(),body:new Element()};
  globalThis.ResizeObserver=class { observe(){} disconnect(){} };
  globalThis.getComputedStyle=()=>({minWidth:'780'});
  globalThis.fetch=async()=>({ok:false});
  globalThis.confirm=()=>true;
  return {querySelector:selector=>elements[selector.slice(1)],querySelectorAll:()=>[]};
}
const flatten = node => [node,...node.children.flatMap(flatten)];
test('restored schedules have identical model, rendered preview and XLSX cell content', () => {
  dom();
  const original=[validateManual(entry,2027),validateManual({...entry,date:'2027-01-05',name:'=<tag>&',category:'personal'},2027)];
  const options={year:2027,mode:'manual',manualApproved:true,generatedAt:'2026-10-12T00:00:00Z'};
  const a=buildCalendar({...options,manual:original}), b=buildCalendar({...options,manual:parseManualBackup(serializeManualBackup(2027,original),2027)});
  assert.deepEqual(b.months.flatMap(x=>x.slots.map(s=>s.displayText)),a.months.flatMap(x=>x.slots.map(s=>s.displayText)));
  assert.deepEqual(workbookParts(b),workbookParts(a));
  const container=new Element(); renderPreview(container,b);
  for(const day of b.months.flatMap(x=>x.slots).filter(x=>x.sources.length)) assert.equal(flatten(container).find(x=>x.dataset.date===day.date).textContent,day.displayText);
});
test('app preserves existing list/editor/preview on failure and cancellation, invalidates after confirmed replacement', async () => {
  const app=initCalendar(dom());
  try {
    await new Promise(resolve=>setImmediate(resolve));
    elements.year.value='2027'; await elements.year.fire('change');
    await new Promise(resolve=>setImmediate(resolve));
    await elements.manualMode.fire('click');
    elements.holidayDate.value=entry.date; elements.holidayName.value='既存'; await elements.holidayForm.fire('submit');
    elements.manualReview.checked=true; await elements.previewButton.fire('click');
    assert.equal(elements.download.disabled,false);
    const prior=elements.manualList.children[0], preview=elements.preview.children[0];
    elements.holidayName.value='編集中';
    async function upload(text, size=text.length) { elements.backupFile.files=[{size,text:async()=>text}]; await elements.backupFile.fire('change'); }
    for(const text of ['{',backup([entry,{...entry,name:' 会社予定\n'}]),backup([entry]).replace('2027','2028')]) {
      await upload(text); assert.equal(elements.manualList.children[0],prior); assert.equal(elements.holidayName.value,'編集中'); assert.equal(elements.preview.children[0],preview);
    }
    await upload(backup([entry]),MAX_BACKUP_BYTES+1); assert.equal(elements.manualList.children[0],prior);
    globalThis.confirm=()=>false; await upload(backup([entry])); assert.equal(elements.manualList.children[0],prior); assert.equal(elements.holidayName.value,'編集中');
    globalThis.confirm=()=>true; await upload(backup([entry])); assert.notEqual(elements.manualList.children[0],prior); assert.equal(elements.holidayName.value,''); assert.equal(elements.preview.children.length,0); assert.equal(elements.download.disabled,true); assert.equal(elements.manualReview.checked,false);
    elements.manualReview.checked=true; await elements.previewButton.fire('click'); assert.equal(elements.download.disabled,false);
    await upload(backup([])); assert.equal(elements.manualList.children.length,0); assert.equal(elements.download.disabled,true);
    elements.backupFile.files=[{size:1,text:async()=>{elements.holidayName.value='changed';return backup([entry]);}}]; await elements.backupFile.fire('change'); assert.equal(elements.manualList.children.length,0); assert.equal(elements.holidayName.value,'changed');
    elements.backupFile.files=[{size:1,text:async()=>{throw Error('read failure');}}]; await elements.backupFile.fire('change'); assert.equal(elements.holidayName.value,'changed');
  } finally { app.destroy(); }
});
