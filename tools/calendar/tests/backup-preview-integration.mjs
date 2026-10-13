// Run only on the combined PR #30 + #31 tree: node --test tools/calendar/tests/backup-preview-integration.mjs
// Minimal DOM handlers; this is not real-browser layout/file-picker evidence.
import test from 'node:test';
import assert from 'node:assert/strict';
import { initCalendar } from '../../../docs/assets/calendar/app.mjs';
// Minimal DOM adapter exercises actual app handlers and renderer without a browser dependency.
class Element {
  constructor() { this.value=''; this.checked=false; this.dataset={}; this.children=[]; this.handlers={}; this.style={setProperty(){}}; this.files=[]; this.parentElement={clientWidth:358}; }
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
  elements = Object.fromEntries(['year','status','previewButton','download','manualMode','approveStale','manualReviewWrap','mockBanner','preview','empty','exportStatus','holidayDate','showLunar','lunarRangeHelp','holidayForm','saveHoliday','cancelEdit','formError','manualList','holidayName','category','manualReview','formattingForm','resetFormatting','backupManual','importManual','backupFile','backupStatus','originalPreviewSize'].map(id => [id,new Element()]));
  elements.category.value='personal';
  globalThis.document={querySelector(){},hidden:false,addEventListener(){},createElement:()=>new Element(),createDocumentFragment:()=>new Element(),body:new Element()};
  globalThis.ResizeObserver=class { observe(){} disconnect(){} };
  globalThis.getComputedStyle=()=>({minWidth:'780'});
  globalThis.fetch=async()=>({ok:false});
  globalThis.confirm=()=>true;
  return {querySelector:selector=>elements[selector.slice(1)],querySelectorAll:()=>[]};
}
const flatten = node => [node,...node.children.flatMap(flatten)];

test('combined backup/import and preview-size handlers preserve data and exported XLSX bytes', async () => {
  const app=initCalendar(dom());
  const blobs=[];
  globalThis.URL.createObjectURL=blob=>{blobs.push(blob);return 'blob:test';};
  globalThis.URL.revokeObjectURL=()=>{};
  globalThis.requestAnimationFrame=callback=>callback();
  const nativeTimeout=globalThis.setTimeout;
  globalThis.setTimeout=(callback,ms)=>{const timer=nativeTimeout(callback,ms);timer.unref();return timer;};
  const toggle=async checked=>{elements.originalPreviewSize.checked=checked;await elements.originalPreviewSize.fire('change');};
  const upload=async text=>{elements.backupFile.files=[{size:Buffer.byteLength(text),text:async()=>text}];await elements.backupFile.fire('change');};
  const save=async()=>{await elements.backupManual.fire('click');return blobs.at(-1).text();};
  const xlsx=async()=>{await elements.download.fire('click');return Buffer.from(await blobs.at(-1).arrayBuffer());};
  try {
    await new Promise(resolve=>setImmediate(resolve));
    elements.year.value='2027';await elements.year.fire('change');
    await new Promise(resolve=>setImmediate(resolve));
    await elements.manualMode.fire('click');
    for(const [date,name,category] of [['2027-01-04','회사 일정','company'],['2027-01-05','개인 일정','personal']]) {
      elements.holidayDate.value=date;elements.holidayName.value=name;elements.category.value=category;await elements.holidayForm.fire('submit');
    }
    elements.manualReview.checked=true;await elements.previewButton.fire('click');
    const text=await save(), before=await xlsx(), preview=elements.preview.children[0], list=elements.manualList.children[0];
    await toggle(true);
    assert.equal(elements.preview.style.zoom,1);assert.equal(elements.preview.children[0],preview);assert.equal(elements.manualList.children[0],list);assert.equal(elements.download.disabled,false);
    assert.deepEqual(await xlsx(),before);assert.equal(await save(),text);
    elements.holidayName.value='입력 중';await toggle(false);
    assert.equal(elements.holidayName.value,'입력 중');assert.equal(elements.preview.style.zoom,358/780);
    await upload('{');assert.equal(elements.preview.children[0],preview);assert.equal(elements.holidayName.value,'입력 중');
    globalThis.confirm=()=>false;await upload(text);assert.equal(elements.manualList.children[0],list);assert.equal(elements.preview.children[0],preview);
    globalThis.confirm=()=>true;await toggle(true);await upload(text);
    assert.equal(elements.originalPreviewSize.checked,true);assert.equal(elements.preview.style.zoom,1);assert.equal(elements.preview.children.length,0);assert.equal(elements.download.disabled,true);assert.equal(elements.manualReview.checked,false);
    assert.equal(elements.holidayName.value,'');assert.equal(await save(),text);
    elements.manualReview.checked=true;await elements.previewButton.fire('click');
    assert.equal(elements.download.disabled,false);
    const restored=await xlsx();await toggle(false);assert.deepEqual(await xlsx(),restored);
    const labels=flatten(elements.preview).filter(node=>node.dataset.date).map(node=>node.textContent).join(' ');
    assert.match(labels,/회사 일정/);assert.match(labels,/개인 일정/);
    await toggle(true);
    elements.backupFile.files=[{size:Buffer.byteLength(text),text:async()=>{await toggle(false);return text;}}];await elements.backupFile.fire('change');
    assert.match(elements.backupStatus.textContent,/2개를 가져왔습니다/);assert.equal(elements.originalPreviewSize.checked,false);assert.equal(await save(),text);
  } finally { app.destroy();globalThis.setTimeout=nativeTimeout; }
});
