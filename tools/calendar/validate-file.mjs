import { readFile } from 'node:fs/promises';
import { validateDataset, MAX_DATA_BYTES } from '../../docs/assets/calendar/contract.mjs';
import { assertDeployable } from './prepare-site.mjs';
try {
  const input = await readFile(process.argv[2], 'utf8');
  if (Buffer.byteLength(input) > MAX_DATA_BYTES) throw new Error();
  const data = JSON.parse(input);
  const production = process.argv.includes('--production');
  validateDataset(data, { production });
  if (production) assertDeployable(data);
  console.log('PASS calendar JSON contract');
} catch {
  console.error('CALENDAR_DATA_INVALID');
  process.exitCode = 1;
}
