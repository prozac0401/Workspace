import { readFile, mkdir, writeFile, rename } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';
import { validateDataset, emptyDataset, selectYear, targetYears } from '../../docs/assets/calendar/contract.mjs';

export function assertDeployable(data, now = Date.now()) {
  validateDataset(data, { production: true });
  const years = targetYears(now);
  if (JSON.stringify(data.targetYears) !== JSON.stringify(years)) throw new Error('CALENDAR_REFRESH_REQUIRED');
  // A missing next year is visible as unavailable. The current year must be usable.
  selectYear(data, years[0], now);
  return data;
}

export async function prepareSite({ source, production = false, output, now = Date.now() }) {
  if (production && !source) throw new Error('CALENDAR_INITIALIZATION_REQUIRED');
  const data = source ? JSON.parse(await readFile(source, 'utf8')) : emptyDataset(now);
  validateDataset(data, { production });
  if (production) assertDeployable(data, now);
  await mkdir(dirname(output), { recursive: true });
  const temporary = `${output}.${randomUUID()}.tmp`;
  await writeFile(temporary, JSON.stringify(data, null, 2) + '\n', { flag: 'wx' });
  await rename(temporary, output);
  return data;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const option = name => args.includes(name) ? args[args.indexOf(name) + 1] : undefined;
  try {
    await prepareSite({ source: option('--source'), production: args.includes('--production'),
      output: fileURLToPath(new URL('../../docs/assets/calendar/data/calendar.json', import.meta.url)) });
    console.log('Calendar public JSON validated.');
  } catch {
    console.error('CALENDAR_BUILD_BLOCKED: validated current data required; existing Pages must be preserved.');
    process.exitCode = 1;
  }
}
