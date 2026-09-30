export const HOST = 'com.workspace.download_version_manager';
export const PROTOCOL = 2;
const PREFIX = 'dvm.download.';
const MAX_AGE = 7 * 24 * 60 * 60 * 1000;
const KEY = id => PREFIX + id;
const basename = p => p.split(/[\\/]/).at(-1);
const notices = {
  target_locked: '기존 파일이 사용 중이어서 교체하지 못했습니다. 기존 파일과 새 파일을 그대로 보존했습니다.',
  new_file_locked: '새 파일이 사용 중이어서 교체하지 못했습니다. 두 파일을 그대로 보존했습니다.',
  rollback_failed: '이름 교체와 복구를 마치지 못했습니다. 새 파일과 보관된 이전 파일을 직접 확인해 주세요.',
  cleanup_required: '최신 파일의 이름을 바꿨습니다. 같은 내용의 임시 이전 파일이 남아 있어 확인이 필요합니다.',
  metadata_warning: '최신 파일의 이름을 바꿨지만 파일 시간을 유지하지 못했습니다.',
  host_unavailable: '다운로드 파일을 정리하지 못했습니다. DownloadVersionManager 설치와 연결을 확인해 주세요.',
  protocol_mismatch: '프로그램과 확장의 버전이 다릅니다. 같은 버전의 설치 파일을 사용해 주세요.',
  version_mismatch: '프로그램과 확장의 버전이 다릅니다. 같은 버전의 설치 파일을 사용해 주세요.',
  uncertain: '다운로드 정리 결과를 확인하지 못했습니다. 파일을 직접 확인해 주세요.',
  filename_override: '선택한 파일 이름을 보존했습니다. 이 다운로드는 자동 정리하지 않았습니다.',
  completion_time_missing: '다운로드 완료 시각을 확인하지 못해 파일을 그대로 보존했습니다.',
  completion_order_ambiguous: '다운로드 완료 시각이 같아 최신 파일을 정하지 못했습니다. 두 파일을 그대로 보존했습니다.',
  order_state_uncertain: '이전 다운로드 처리 상태를 확인하지 못해 파일을 그대로 보존했습니다.',
  order_state_invalid: '다운로드 순서 기록을 확인하지 못해 파일을 그대로 보존했습니다.',
  order_state_unavailable: '다운로드 순서를 안전하게 기록하지 못해 파일을 그대로 보존했습니다.',
};
export function logicalFilename(tentative) {
  if (typeof tentative !== 'string' || !tentative) throw Error('filename_missing');
  const name = basename(tentative);
  if (!name || name.length > 255 || /[\x00-\x1f<>:"/\\|?*]/.test(name) || /[. ]$/.test(name)) throw Error('filename_invalid');
  return name; // Never recover an original name from a browser counter suffix.
}
// Validate the actual name against an already remembered name. This is a forward
// check of browser uniquify output, not reverse inference from " (1)".
export function belongsToLogical(actual, logical) {
  const name = basename(actual);
  if (name.toLocaleLowerCase('en-US') === logical.toLocaleLowerCase('en-US')) return true;
  const dot = logical.lastIndexOf('.');
  const split = dot > 0 ? dot : logical.length;
  const escape = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp('^' + escape(logical.slice(0, split)) + ' \\([1-9][0-9]*\\)' + escape(logical.slice(split)) + '$', 'i').test(name);
}
export function createController(api, now = Date.now, token = () => crypto.randomUUID().replaceAll('-', '')) {
  const determining = new Map();
  const completing = new Map();
  const version = api.runtime.getManifest().version;
  async function notify(status) {
    const message = notices[status] ?? '파일을 안전하게 교체하지 못했습니다. 남아 있는 파일을 확인해 주세요.';
    // One local, path-free last error; no hashes, URLs or document content.
    await api.storage.local.set({'dvm.lastIssue': {status, at: now()}}).catch(() => {});
    await api.notifications.create('dvm.error', {type: 'basic', title: 'DownloadVersionManager', message, iconUrl: api.runtime.getURL('icon.png')}).catch(() => {});
  }
  async function native(request) {
    let result;
    try { result = await api.runtime.sendNativeMessage(HOST, request); }
    catch { throw Error('host_unavailable'); }
    if (!result || result.protocolVersion !== PROTOCOL) throw Error('protocol_mismatch');
    if (result.version !== version) throw Error('version_mismatch');
    if (typeof result.ok !== 'boolean' || typeof result.status !== 'string') throw Error('uncertain');
    return result;
  }
  async function cleanup() {
    const records = await api.storage.local.get(null);
    const expired = Object.entries(records).filter(([key, value]) =>
      (key.startsWith(PREFIX) || key === 'dvm.lastIssue') && (!Number.isFinite(value?.at) || now() - value.at > MAX_AGE)).map(([key]) => key);
    if (expired.length) await api.storage.local.remove(expired);
  }
  function determine(item, suggest) {
    let called = false;
    const once = value => { if (!called) { called = true; suggest(value); } };
    const work = (async () => {
      try {
        const logicalName = logicalFilename(item.filename);
        await api.storage.local.set({[KEY(item.id)]: {logicalName, requestToken: token(), at: now(), stage: 'ready'}});
        once({filename: logicalName, conflictAction: 'uniquify'});
      } catch { once(); }
    })();
    determining.set(item.id, work);
    void work.finally(() => determining.delete(item.id));
    return true; // Required for the asynchronous suggest callback.
  }
  async function complete(id) {
    if (determining.has(id)) await determining.get(id);
    const key = KEY(id);
    const record = (await api.storage.local.get(key))[key];
    if (!record) return; // Missing metadata is never reconstructed from a suffix.
    try {
      if (record.stage !== 'ready') throw Error('uncertain'); // Do not replay an ambiguous operation.
      const items = await api.downloads.search({id});
      const item = items[0];
      if (!item || item.state !== 'complete') return;
      if (item.danger && !['safe', 'accepted'].includes(item.danger)) return;
      if (!/^[a-z]:\\/i.test(item.filename) || !belongsToLogical(item.filename, record.logicalName)) throw Error('filename_override');
      const completedAt = typeof item.endTime === 'string' ? Date.parse(item.endTime) : NaN;
      if (!Number.isSafeInteger(completedAt) || completedAt <= 0 || completedAt > 253402300799999) throw Error('completion_time_missing');
      if (!/^[0-9a-f]{32}$/.test(record.requestToken ?? '')) throw Error('uncertain');
      await api.storage.local.set({[key]: {...record, stage: 'processing'}});
      const result = await native({protocolVersion: PROTOCOL, operation: 'process', downloadId: id, completedAt, requestToken: record.requestToken, logicalName: record.logicalName, newPath: item.filename});
      if (!result.ok || ['cleanup_required', 'metadata_warning'].includes(result.status)) await notify(result.status);
    } catch (error) { await notify(error.message in notices ? error.message : 'uncertain'); }
    finally { await api.storage.local.remove(key).catch(() => {}); }
  }
  function changed(delta) {
    if (delta.state?.current === 'interrupted') {
      const pending = determining.get(delta.id) ?? Promise.resolve();
      return pending.then(() => api.storage.local.remove(KEY(delta.id)));
    }
    if (delta.state?.current !== 'complete') return Promise.resolve();
    if (completing.has(delta.id)) return completing.get(delta.id);
    const work = complete(delta.id).finally(() => completing.delete(delta.id));
    completing.set(delta.id, work); return work;
  }
  return {
    determine, changed, cleanup,
    erased: id => api.storage.local.remove(KEY(id)),
    handshake: async () => { try { return await native({protocolVersion: PROTOCOL, operation: 'ping'}); } catch (e) { return {ok: false, status: e.message}; } },
  };
}
