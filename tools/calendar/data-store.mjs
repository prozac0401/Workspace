// A single public JSON file on an isolated Git branch is the durable store.
// No source checkout is staged. No credential, URL, raw response or error is logged.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFile, writeFile, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { dirname, join, resolve, relative, isAbsolute } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { validateDataset, MAX_DATA_BYTES } from '../../docs/assets/calendar/contract.mjs';
const execute = promisify(execFile);
const branch = 'refs/heads/calendar-data';
const isSha = value => /^[a-f0-9]{40}$/.test(value);

export function gitStore(cwd = process.cwd(), remote = 'origin') {
  async function git(args, options = {}) {
    try {
      return (await execute('git', args, { cwd, windowsHide: true, maxBuffer: 3 * 1024 * 1024,
        timeout: 60000, ...options })).stdout.trim();
    } catch { throw new Error('CALENDAR_GIT_OPERATION_FAILED'); }
  }
  async function current() {
    const listing = await git(['ls-remote', '--heads', remote, branch]);
    if (!listing) return null;
    const [sha, ref] = listing.split(/\s+/);
    if (!isSha(sha) || ref !== branch) throw new Error('CALENDAR_DATA_REF_INVALID');
    return sha;
  }
  async function read({ sha, allowMissing = false } = {}) {
    const selected = sha || await current();
    if (!selected) {
      if (allowMissing) return { sha: null, data: null };
      throw new Error('CALENDAR_INITIALIZATION_REQUIRED');
    }
    if (!isSha(selected)) throw new Error('CALENDAR_DATA_REF_INVALID');
    await git(['fetch', '--no-tags', remote, selected]);
    if (await git(['ls-tree', '-r', '--name-only', selected]) !== 'calendar.json') throw new Error('CALENDAR_DATA_TREE_INVALID');
    const size = Number(await git(['cat-file', '-s', `${selected}:calendar.json`]));
    if (!Number.isSafeInteger(size) || size > MAX_DATA_BYTES) throw new Error('CALENDAR_DATA_SIZE_INVALID');
    const data = JSON.parse(await git(['show', `${selected}:calendar.json`]));
    validateDataset(data, { production: true });
    return { sha: selected, data };
  }
  async function save({ file, expectedSha = null, initialize = false }) {
    const data = JSON.parse(await readFile(file, 'utf8'));
    validateDataset(data, { production: true });
    const observed = await current();
    if (observed !== expectedSha) throw new Error('CALENDAR_DATA_CONCURRENT_UPDATE');
    if (!observed && !initialize) throw new Error('CALENDAR_INITIALIZATION_REQUIRED');
    if (observed) await read({ sha: observed });
    const temporary = await mkdtemp(join(tmpdir(), 'workspace-calendar-index-'));
    const env = { ...process.env, GIT_INDEX_FILE: join(temporary, 'index'),
      GIT_AUTHOR_NAME: 'github-actions[bot]', GIT_AUTHOR_EMAIL: '41898282+github-actions[bot]@users.noreply.github.com',
      GIT_COMMITTER_NAME: 'github-actions[bot]', GIT_COMMITTER_EMAIL: '41898282+github-actions[bot]@users.noreply.github.com' };
    try {
      const normalized = join(temporary, 'calendar.json');
      await writeFile(normalized, JSON.stringify(data, null, 2) + '\n');
      const blob = await git(['hash-object', '-w', normalized]);
      await git(['read-tree', '--empty'], { env });
      await git(['update-index', '--add', '--cacheinfo', `100644,${blob},calendar.json`], { env });
      const tree = await git(['write-tree'], { env });
      if (observed && tree === await git(['rev-parse', `${observed}^{tree}`])) return observed;
      const args = ['commit-tree', tree, ...(observed ? ['-p', observed] : []), '-m', 'Update validated calendar snapshots'];
      const committed = await git(args, { env });
      // A normal fast-forward push rejects a writer racing after current(). Never force.
      await git(['push', remote, `${committed}:${branch}`]);
      return committed;
    } finally {
      // Verify the absolute target stays in the intended temporary output directory.
      const child = relative(resolve(tmpdir()), resolve(temporary));
      if (isAbsolute(child) || child.startsWith('..') || !child.startsWith('workspace-calendar-index-')) throw new Error('CALENDAR_TEMP_PATH_INVALID');
      await rm(temporary, { recursive: true, force: true });
    }
  }
  return { current, read, save };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2), option = name => args.includes(name) ? args[args.indexOf(name) + 1] : undefined;
  try {
    const store = gitStore();
    if (args[0] === 'read') {
      const result = await store.read({ sha: option('--sha'), allowMissing: args.includes('--allow-missing') });
      const out = option('--output');
      if (result.data) { await mkdir(dirname(out), { recursive: true }); await writeFile(out, JSON.stringify(result.data, null, 2) + '\n'); }
      if (option('--meta')) await writeFile(option('--meta'), JSON.stringify({ sha: result.sha }));
      console.log(result.sha || 'CALENDAR_INITIALIZATION_REQUIRED');
    } else if (args[0] === 'save') {
      const sha = await store.save({ file: option('--input'), expectedSha: option('--expected-sha') || null, initialize: args.includes('--initialize') });
      if (process.env.GITHUB_OUTPUT) await writeFile(process.env.GITHUB_OUTPUT, `data_sha=${sha}\n`, { flag: 'a' });
      console.log(`Calendar data saved at ${sha}`);
    } else throw new Error();
  } catch {
    console.error('CALENDAR_DATA_STORE_FAILED: data missing, invalid, or changed concurrently. No force overwrite performed.');
    process.exitCode = 1;
  }
}
