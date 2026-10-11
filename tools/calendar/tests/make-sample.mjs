// Reproducible software fixture only. Never install these holidays as public data.
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { buildCalendar, validateManual } from '../../../docs/assets/calendar/calendar-model.mjs';
import { exportXlsx } from '../../../docs/assets/calendar/xlsx-exporter.mjs';

const year = Number(process.argv[2] ?? 2027);
const output = process.argv[3] ? resolve(process.argv[3]) : fileURLToPath(new URL('../../../artifacts/calendar/', import.meta.url));
const fetchedAt = '2026-10-11T00:00:00.000Z';
const holidays = [
  { date: `${year}-01-01`, name: '모의 신정', source: 'official', category: 'public', sourceId: 'fixture:1' },
  { date: `${year}-10-03`, name: '모의 국경일', source: 'official', category: 'public', sourceId: 'fixture:2' },
];
const snapshot = {
  year, snapshotId: `fixture-${year}`, status: 'ready', complete: true, datasetKind: 'fixture',
  fetchedAt, lastSuccessfulFetchAt: fetchedAt, holidays, warnings: ['자동 검증용 가상 자료'],
  monthResults: Array.from({ length: 12 }, (_, i) => ({
    month: i + 1, status: 'success', rawCount: [1, 10].includes(i + 1) ? 1 : 0, pages: 1, fetchedAt,
  })),
};
const manual = ['=SUM(A1:A2)', '+1', '-1', '@test', '<img src=x>', '_x0041_'].map((name, i) => validateManual({
  date: `${year}-02-0${i + 1}`, name, category: 'company', sourceId: `fixture:manual:${i}`,
}, year));
manual.push(validateManual({ date: `${year}-01-15`, name: '회사 휴일 (예시)', category: 'company', sourceId: 'fixture:company' }, year));
const model = buildCalendar({ year, snapshot, manual, mode: 'ready', generatedAt: fetchedAt, now: Date.parse(fetchedAt) });
await mkdir(output, { recursive: true });
await writeFile(resolve(output, `calendar_${year}.xlsx`), exportXlsx(model));
await writeFile(resolve(output, `model_${year}.json`), `${JSON.stringify(model, null, 2)}\n`);
console.log(JSON.stringify({ output, year, datasetKind: 'fixture', warning: 'Synthetic test holidays; not official calendar data.' }));
