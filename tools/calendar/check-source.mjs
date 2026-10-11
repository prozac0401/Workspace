import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { writeFile } from 'node:fs/promises';
try {
  const branch = process.env.CALENDAR_SOURCE_BRANCH, expected = process.env.CALENDAR_SOURCE_SHA;
  if (!/^[a-zA-Z0-9/_-]+$/.test(branch || '') || !/^[a-f0-9]{40}$/.test(expected || '')) throw new Error();
  const { stdout } = await promisify(execFile)('git', ['ls-remote', '--heads', 'origin', `refs/heads/${branch}`], { timeout: 30000, windowsHide: true });
  const current = stdout.trim().split(/\s+/)[0] === expected;
  if (process.env.GITHUB_OUTPUT) await writeFile(process.env.GITHUB_OUTPUT, `current=${current}\n`, { flag: 'a' });
  if (!current) console.log('A newer source commit exists. This run will not save or deploy stale results.');
} catch {
  console.error('CALENDAR_SOURCE_CHECK_FAILED');
  process.exitCode = 1;
}
