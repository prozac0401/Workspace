import { readFile, mkdir, open, rename, unlink } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { randomUUID } from 'node:crypto';
import { createHolidayService, HolidayError } from './lib/holiday-provider.mjs';
import { emptyDataset, emptyYear, validateDataset, targetYears, MAX_DATA_BYTES } from '../../docs/assets/calendar/contract.mjs';

const error = code => Object.assign(new Error(code), { code });
const safeCodes = new Set(['CONFIGURATION_ERROR', 'COLLECTION_FAILED', 'PREVIOUS_DATA_INVALID', 'OUTPUT_BUSY', 'PERSISTENCE_ERROR', 'ARGUMENT_ERROR']);
export async function atomicWriteJson(path, value, { beforeRename } = {}) {
  const destination = resolve(path);
  await mkdir(dirname(destination), { recursive: true });
  const temporary = `${destination}.${randomUUID()}.tmp`;
  let handle;
  try {
    handle = await open(temporary, 'wx', 0o600);
    await handle.writeFile(`${JSON.stringify(value, null, 2)}\n`, 'utf8');
    await handle.sync();
    await handle.close(); handle = null;
    if (beforeRename) await beforeRename(temporary);
    await rename(temporary, destination);
  } catch {
    throw error('PERSISTENCE_ERROR');
  } finally {
    await handle?.close().catch(() => {});
    await unlink(temporary).catch(() => {});
  }
}

export async function collectDataset({ previous = null, service, now = Date.now() }) {
  if (previous) validateDataset(previous, { production: true });
  const data = emptyDataset(now);
  data.datasetKind = 'official';
  const report = { outcome: 'success', successfulYears: [], preservedYears: [], failedYears: [], deployEligible: false };
  for (const year of targetYears(now)) {
    try {
      const snapshot = await service.getYear(year);
      data.years[year] = snapshot;
      // Validate each incoming year before allowing it into the durable document.
      validateDataset(data);
      if (!snapshot.complete || snapshot.status !== 'ready') throw error('COLLECTION_FAILED');
      report.successfulYears.push(year);
    } catch (failure) {
      report.failedYears.push(year);
      if (previous?.years[year]?.complete) {
        const warning = '최근 수집 실패: 이전 검증 자료를 보존했습니다. 사용 전 최신성을 확인하세요.';
        data.years[year] = { ...structuredClone(previous.years[year]), status: 'preserved',
          // The preserved status itself reports failure when the warning list is full.
          warnings: previous.years[year].warnings.includes(warning) || previous.years[year].warnings.length >= 20
            ? [...previous.years[year].warnings] : [...previous.years[year].warnings, warning] };
        report.preservedYears.push(year);
      } else {
        const unavailable = failure instanceof HolidayError && failure.code === 'YEAR_UNAVAILABLE';
        data.years[year] = emptyYear(year, unavailable ? 'unavailable' : 'error', unavailable ? '연간 공식 공휴일이 0건입니다. 자료 공개 여부를 확인하세요.' : '공식 자료 수집에 실패했습니다. 다음 수집 또는 명시적 수동 모드를 사용하세요.');
      }
    }
  }
  report.outcome = report.failedYears.length === 0 ? 'success' : report.successfulYears.length ? 'partial' : 'failed';
  report.deployEligible = report.outcome === 'success';
  validateDataset(data);
  return { data, report };
}

export async function runCollector({ previousPath, outputPath, reportPath, env = process.env, now = Date.now(), service, writeJson = atomicWriteJson }) {
  // Never inspect .env; no-key exits before fetch, directory creation or writes.
  if (!env.KASI_SERVICE_KEY || typeof env.KASI_SERVICE_KEY !== 'string' || !env.KASI_SERVICE_KEY.trim()) throw error('CONFIGURATION_ERROR');
  if (!outputPath || !reportPath || resolve(outputPath) === resolve(reportPath) || previousPath && resolve(previousPath) === resolve(reportPath)) throw error('ARGUMENT_ERROR');
  await mkdir(dirname(resolve(outputPath)), { recursive: true });
  const lockPath = `${resolve(outputPath)}.lock`;
  let lock;
  try { lock = await open(lockPath, 'wx', 0o600); }
  catch { throw error('OUTPUT_BUSY'); }
  try {
    let previous = null;
    try {
        // An existing output is also a recovery source when --previous is omitted.
        const bytes = await readFile(previousPath || outputPath);
        if (bytes.length > MAX_DATA_BYTES) throw error('PREVIOUS_DATA_INVALID');
        previous = validateDataset(JSON.parse(bytes.toString('utf8')), { production: true });
    } catch (failure) {
      if (previousPath || failure.code !== 'ENOENT') throw error('PREVIOUS_DATA_INVALID');
    }
    const result = await collectDataset({ previous, now, service: service || createHolidayService({ key: env.KASI_SERVICE_KEY }) });
    // Total failure leaves the prior file byte-for-byte intact, including timestamps.
    if (result.report.outcome !== 'failed') {
      validateDataset(result.data, { production: true });
      await writeJson(outputPath, result.data);
    }
    await writeJson(reportPath, result.report);
    return result;
  } finally {
    await lock.close().catch(() => {});
    await unlink(lockPath).catch(() => {});
  }
}

async function main() {
  const args = process.argv.slice(2), parsed = {};
  for (let i = 0; i < args.length; i += 2) {
    if (!['--previous', '--output', '--report'].includes(args[i]) || !args[i + 1] || args[i + 1].startsWith('--') || parsed[args[i]]) throw error('ARGUMENT_ERROR');
    parsed[args[i]] = args[i + 1];
  }
  const { report } = await runCollector({ previousPath: parsed['--previous'], outputPath: parsed['--output'], reportPath: parsed['--report'] });
  process.stdout.write(`${JSON.stringify(report)}\n`);
  // Partial/failed collections are handled by the explicit deployEligible report.
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(failure => {
    process.stderr.write(`${safeCodes.has(failure?.code) ? failure.code : 'COLLECTION_FAILED'}\n`);
    process.exitCode = 1;
  });
}
