import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createController, logicalFilename, belongsToLogical, HOST} from '../../extension/controller.mjs';

function fixture(store = {}) {
  const calls = [], notes = [], items = new Map();
  const api = {
    storage: {local: {
      async set(values) { Object.assign(store, structuredClone(values)); },
      async get(keys) { if (keys === null) return structuredClone(store); return Object.fromEntries((Array.isArray(keys) ? keys : [keys]).filter(k => k in store).map(k => [k, structuredClone(store[k])])); },
      async remove(keys) { for (const k of Array.isArray(keys) ? keys : [keys]) delete store[k]; },
    }},
    downloads: {async search({id}) { return items.has(id) ? [items.get(id)] : []; }},
    notifications: {async create(id, value) { notes.push({id, ...value}); }},
    runtime: {
      getManifest: () => ({version: '0.1.0'}), getURL: p => 'chrome-extension://fixture/' + p,
      async sendNativeMessage(host, request) { calls.push({host, request}); return {protocolVersion: 2, version: '0.1.0', ok: true, status: 'renamed'}; },
    },
  };
  const control = createController(api, () => 1000000000);
  async function determine(id, name) { let suggestions = []; assert.equal(control.determine({id, filename: name}, s => suggestions.push(s)), true); await new Promise(r => setImmediate(r)); assert.equal(suggestions.length, 1); return suggestions[0]; }
  async function finish(id, name, endTime = '2026-09-30T00:00:00.000Z') { items.set(id, {id, endTime, filename: 'C:\\Downloads\\' + name, state: 'complete', danger: 'safe'}); await control.changed({id, state: {current: 'complete'}}); }
  return {api, store, calls, notes, items, control, determine, finish};
}
test('first download remembers original before uniquify and complete', async () => {
  const f=fixture(); assert.deepEqual(await f.determine(1, 'C:\\Downloads\\보고서.xlsx'), {filename:'보고서.xlsx',conflictAction:'uniquify'});
  assert.equal(f.store['dvm.download.1'].logicalName,'보고서.xlsx'); await f.finish(1,'보고서.xlsx');
  assert.equal(f.calls[0].host,HOST); assert.equal(f.calls[0].request.logicalName,'보고서.xlsx'); assert.equal(f.notes.length,0); assert.deepEqual(f.store,{});
});
test('duplicate path does not supply a guessed logical name', async () => {
  const f=fixture(); await f.determine(2,'보고서.xlsx'); await f.finish(2,'보고서 (17).xlsx');
  assert.equal(f.calls[0].request.newPath,'C:\\Downloads\\보고서 (17).xlsx'); assert.equal(f.calls[0].request.logicalName,'보고서.xlsx');
});
for (const number of [1,2]) test(`original filename includes (${number})`, async () => {
  const f=fixture(); const name=`회의자료 (${number}).pdf`; await f.determine(number,name); await f.finish(number,`회의자료 (${number}) (1).pdf`);
  assert.equal(f.calls[0].request.logicalName,name); assert.equal(logicalFilename(name),name);
});
for (const error of ['USER_CANCELED','NETWORK_FAILED','FILE_FAILED','USER_SHUTDOWN']) test(`interrupted ${error}: no native call`, async () => {
  const f=fixture(); await f.determine(1,'a.pdf'); await f.control.changed({id:1,state:{current:'interrupted'},error:{current:error}});
  assert.equal(f.calls.length,0); assert.equal(f.notes.length,0); assert.deepEqual(f.store,{});
});
test('nonterminal changes do not invoke host', async () => { const f=fixture(); await f.determine(1,'a'); await f.control.changed({id:1,filename:{current:'x'}}); assert.equal(f.calls.length,0); });
test('concurrent completions keep ID-specific logical names', async () => {
  const f=fixture(); for (let i=0;i<12;i++) await f.determine(i,`회의 ${i}.xlsx`);
  await Promise.all([...Array(12)].map((_,i)=>f.finish(i,`회의 ${i} (1).xlsx`)));
  assert.equal(f.calls.length,12); assert.equal(new Set(f.calls.map(c=>c.request.logicalName)).size,12); assert.deepEqual(f.store,{});
});
test('worker suspension between determination and completion restores storage', async () => {
  const f=fixture(); await f.determine(7,'보고서.xlsx'); const token=f.store['dvm.download.7'].requestToken; const restored=fixture(f.store); await restored.finish(7,'보고서 (1).xlsx');
  assert.equal(restored.calls[0].request.logicalName,'보고서.xlsx'); assert.deepEqual(restored.store,{});
  assert.equal(restored.calls[0].request.requestToken,token);
});
test('lost metadata never infers original from suffix', async () => { const f=fixture(); await f.finish(1,'a (1).pdf'); assert.equal(f.calls.length,0); });
test('ambiguous in-flight operation is not retried', async () => {
  const f=fixture({'dvm.download.1':{logicalName:'a',at:1000000000,stage:'processing'}}); await f.finish(1,'a (1)');
  assert.equal(f.calls.length,0); assert.equal(f.notes.length,1); assert.equal(f.store['dvm.download.1'],undefined);
});
test('stale cleanup is event-triggered and preserves unrelated storage', async () => {
  const f=fixture({'dvm.download.1':{at:1},'dvm.download.2':{at:1000000000},unrelated:{at:1}}); await f.control.cleanup();
  assert.equal(f.store['dvm.download.1'],undefined); assert.ok(f.store['dvm.download.2']); assert.deepEqual(f.store.unrelated,{at:1});
});
test('host unavailable uses short error and removes metadata', async () => {
  const f=fixture(); f.api.runtime.sendNativeMessage=async()=>{throw Error('native internal stack');}; await f.determine(1,'a'); await f.finish(1,'a (1)');
  assert.equal(f.notes.length,1); assert.equal(f.store['dvm.download.1'],undefined); assert.ok(!f.notes[0].message.includes('stack'));
});
test('host target locked error uses preservation feedback', async () => {
  const f=fixture(); f.api.runtime.sendNativeMessage=async()=>({protocolVersion:2,version:'0.1.0',ok:false,status:'target_locked'}); await f.determine(1,'a'); await f.finish(1,'a (1)');
  assert.match(f.notes[0].message,/그대로 보존/);
});
test('rollback failure does not claim files are at original locations', async () => {
  const f=fixture(); f.api.runtime.sendNativeMessage=async()=>({protocolVersion:2,version:'0.1.0',ok:false,status:'rollback_failed'}); await f.determine(1,'a'); await f.finish(1,'a (1)');
  assert.match(f.notes[0].message,/보관된 이전 파일/); assert.ok(!f.notes[0].message.includes('그대로'));
});
for (const response of [{protocolVersion:3,version:'0.1.0',ok:true,status:'ready'},{protocolVersion:2,version:'0.2.0',ok:true,status:'ready'},null,{protocolVersion:2,version:'0.1.0'}]) test(`invalid host response ${JSON.stringify(response)}`, async () => {
  const f=fixture(); f.api.runtime.sendNativeMessage=async()=>response; await f.determine(1,'a'); await f.finish(1,'a (1)'); assert.equal(f.notes.length,1); assert.equal(f.store['dvm.download.1'],undefined);
});
test('save-as different parent uses actual path and remembered name', async () => {
  const f=fixture(); await f.determine(1,'a.xlsx'); f.items.set(1,{endTime:'2026-09-30T00:00:00.000Z',state:'complete',filename:'D:\\선택 폴더\\a (1).xlsx'}); await f.control.changed({id:1,state:{current:'complete'}});
  assert.equal(f.calls[0].request.newPath,'D:\\선택 폴더\\a (1).xlsx');
});
test('user-chosen different basename is preserved without file operation', async () => { const f=fixture(); await f.determine(1,'a.xlsx'); await f.finish(1,'사용자 선택.xlsx'); assert.equal(f.calls.length,0); assert.equal(f.notes.length,1); });
test('other extension filename is not accepted as our logical name', () => { assert.equal(belongsToLogical('a (1).pdf','a (1).pdf'),true); assert.equal(belongsToLogical('a.pdf','a (1).pdf'),false); });
test('unsafe download is not automatically accepted or moved', async () => { const f=fixture(); await f.determine(1,'a'); f.items.set(1,{state:'complete',filename:'C:\\a (1)',danger:'uncommon'}); await f.control.changed({id:1,state:{current:'complete'}}); assert.equal(f.calls.length,0); assert.deepEqual(f.store,{}); });
test('metadata storage failure still suggests exactly once', async () => { const f=fixture(); f.api.storage.local.set=async()=>{throw Error('full');}; assert.equal(await f.determine(1,'a'),undefined); assert.equal(f.calls.length,0); });
test('erased metadata is removed', async () => { const f=fixture(); await f.determine(1,'a'); await f.control.erased(1); assert.deepEqual(f.store,{}); });
test('handshake uses single native request without download payload', async () => { const f=fixture(); await f.control.handshake(); assert.deepEqual(f.calls[0].request,{protocolVersion:2,operation:'ping'}); });
test('request uses browser endTime rather than worker wake-up time', async () => {
  const f=fixture(); await f.determine(1,'a'); await f.finish(1,'a (1)','2026-09-30T01:02:03.004Z');
  assert.equal(f.calls[0].request.completedAt,Date.parse('2026-09-30T01:02:03.004Z'));
  assert.match(f.calls[0].request.requestToken,/^[0-9a-f]{32}$/);
});
test('colliding download IDs in separate browsers have distinct persistent tokens', async () => {
  const a=fixture(), b=fixture(); await a.determine(1,'a'); await b.determine(1,'a');
  assert.notEqual(a.store['dvm.download.1'].requestToken,b.store['dvm.download.1'].requestToken);
});
for (const time of [undefined,'invalid','1970-01-01T00:00:00.000Z']) test(`missing or invalid completion time ${time} preserves download`, async () => {
  const f=fixture(); await f.determine(1,'a'); f.items.set(1,{id:1,state:'complete',danger:'safe',filename:'C:\\Downloads\\a (1)',endTime:time});
  await f.control.changed({id:1,state:{current:'complete'}}); assert.equal(f.calls.length,0); assert.match(f.notes[0].message,/완료 시각/);
});
test('old metadata without request token is preserved without native mutation', async () => {
  const f=fixture({'dvm.download.1':{logicalName:'a',at:1000000000,stage:'ready'}}); await f.finish(1,'a (1)'); assert.equal(f.calls.length,0); assert.equal(f.notes.length,1);
});
for (const status of ['superseded_archived','superseded_same_content']) test(`safe delayed completion ${status} stays quiet`,async () => {
  const f=fixture(); f.api.runtime.sendNativeMessage=async()=>({protocolVersion:2,version:'0.1.0',ok:true,status}); await f.determine(1,'a'); await f.finish(1,'a (1)'); assert.equal(f.notes.length,0);
});
test('ambiguous equal completion time asks user to check preserved files', async () => {
  const f=fixture(); f.api.runtime.sendNativeMessage=async()=>({protocolVersion:2,version:'0.1.0',ok:false,status:'completion_order_ambiguous'}); await f.determine(1,'a'); await f.finish(1,'a (1)');
  assert.match(f.notes[0].message,/두 파일을 그대로 보존/);
});
test('MV3 source has no native port, content scripts, timers or suffix reverse replacement', async () => {
  const manifest=JSON.parse(await readFile(new URL('../../extension/manifest.json',import.meta.url),'utf8'));
  assert.equal(manifest.manifest_version,3); assert.equal(manifest.background.type,'module'); assert.equal(manifest.content_scripts,undefined); assert.equal(manifest.host_permissions,undefined);
  const source=await readFile(new URL('../../extension/worker.mjs',import.meta.url),'utf8')+await readFile(new URL('../../extension/controller.mjs',import.meta.url),'utf8');
  assert.doesNotMatch(source,/\.connectNative\s*\(|setInterval\s*\(|setTimeout\s*\(|chrome\.alarms|removeFile\s*\(/);
});

test('connection check is diagnostic and does not enable download processing', async () => {
  const f=fixture(); await f.determine(1,'a.pdf'); await f.finish(1,'a (1).pdf');
  assert.deepEqual(f.calls.map(c=>c.request.operation),['process']);
  await f.control.handshake();
  await f.determine(2,'a.pdf'); await f.finish(2,'a (2).pdf');
  assert.deepEqual(f.calls.map(c=>c.request.operation),['process','ping','process']);
});
test('setup and popup explain activation separately from diagnostic connection check', async () => {
  const popup=await readFile(new URL('../../extension/popup.html',import.meta.url),'utf8');
  const setup=await readFile(new URL('../../installer/setup.html',import.meta.url),'utf8');
  const source=await readFile(new URL('../../extension/popup.mjs',import.meta.url),'utf8');
  for (const page of [popup,setup]) {
    assert.match(page,/활성화하면 새 다운로드부터 자동 정리/);
    assert.match(page,/연결 확인.*진단/);
  }
  assert.doesNotMatch(popup,/연결 확인이 끝나야/);
  assert.doesNotMatch(source,/다음 다운로드부터 정리합니다/);
});
