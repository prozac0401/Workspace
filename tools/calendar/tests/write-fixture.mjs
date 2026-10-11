import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fixture } from './fixtures/helpers.mjs';
const output = resolve(process.argv[2] || 'artifacts/calendar/fixture.json');
await mkdir(dirname(output), { recursive: true });
await writeFile(output, JSON.stringify(fixture(Date.now()), null, 2) + '\n');
console.log('Synthetic fixture saved. Production validator rejects this dataset.');
