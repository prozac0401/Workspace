import { validateDataset, selectYear, MAX_DATA_BYTES, MIN_YEAR, MAX_YEAR } from './contract.mjs';

const DATA_URL = new URL('./data/calendar.json', import.meta.url);
const unavailable = (code, message) => ({ error: { code, message } });

// Only the checked public JSON is loaded. User-entered holidays never leave the page.
export class HolidayClient {
  #version = 0;
  #controller = null;
  #dataset = null;
  get dataset() { return this.#dataset; }
  invalidate() { this.#version++; this.#controller?.abort(); }
  current(year, now = Date.now()) {
    if (!this.#dataset) return unavailable('CALENDAR_DATA_UNAVAILABLE', '검증된 공휴일 자료가 없습니다. 다시 읽거나 수동 모드를 선택하세요.');
    try { return { snapshot: selectYear(this.#dataset, year, now), dataset: this.#dataset }; }
    catch (error) {
      const messages = {
        CALENDAR_YEAR_UNSUPPORTED: '선택할 수 있는 연도는 ' + MIN_YEAR + '~' + MAX_YEAR + '년입니다. 범위 안의 연도를 입력하세요.',
        CALENDAR_DATA_UNAVAILABLE: '이 연도의 완전한 공식 자료가 아직 준비되지 않았습니다. 다시 읽거나 수동 모드를 선택하세요.',
        CALENDAR_DATA_EXPIRED: '마지막 성공 수집 후 30일을 넘었습니다. 공식 자료로 만들 수 없습니다. 새 자료를 기다리거나 수동 모드를 선택하세요.',
      };
      const code = Object.hasOwn(messages, error.code) ? error.code : 'CALENDAR_SCHEMA_INVALID';
      return { ...unavailable(code, messages[code] || '공휴일 자료 검증에 실패했습니다. 다시 읽거나 수동 모드를 선택하세요.'), dataset: this.#dataset };
    }
  }
  async load(year, fetchImpl = fetch, now = () => Date.now()) {
    this.invalidate();
    const version = this.#version;
    const controller = this.#controller = new AbortController();
    this.#dataset = null;
    const timer = setTimeout(() => controller.abort(), 10000);
    try {
      const response = await fetchImpl(DATA_URL, { signal: controller.signal, cache: 'no-cache', credentials: 'omit' });
      if (version !== this.#version) return { obsolete: true };
      if (!response.ok) return unavailable('CALENDAR_DATA_UNAVAILABLE', '공개 공휴일 자료를 읽지 못했습니다. 자료가 준비된 뒤 다시 읽거나 수동 모드를 선택하세요.');
      if (Number(response.headers?.get('content-length')) > MAX_DATA_BYTES) throw new Error('size');
      const body = await response.text();
      if (version !== this.#version) return { obsolete: true };
      if (new TextEncoder().encode(body).length > MAX_DATA_BYTES) throw new Error('size');
      const data = JSON.parse(body);
      validateDataset(data);
      this.#dataset = data;
      return this.current(year, typeof now === 'function' ? now() : now);
    } catch {
      if (version !== this.#version) return { obsolete: true };
      return unavailable('CALENDAR_DATA_INVALID', '자료 연결 또는 검증에 실패했습니다. 완전한 공식 자료 없이 다운로드할 수 없습니다. 다시 읽거나 수동 모드를 선택하세요.');
    } finally { clearTimeout(timer); }
  }
}
