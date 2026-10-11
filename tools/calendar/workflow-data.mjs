import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { gitStore } from './data-store.mjs';
import { runCollector } from './collect.mjs';
import { assertDeployable } from './prepare-site.mjs';

export function deploymentDecision(report) {
  return { persist: report.successfulYears.length > 0,
    deploy: report.successfulYears.length > 0 && report.deployEligible === true && report.failedYears.length === 0 };
}

export async function prepareWorkflow({ action, initialize = false, directory, store = gitStore(), collect = runCollector, now = Date.now() }) {
  if (!['collect', 'reuse'].includes(action) || initialize && action !== 'collect') throw new Error('CALENDAR_ACTION_INVALID');
  await mkdir(directory, { recursive: true });
  const previous = await store.read({ allowMissing: initialize });
  const previousPath = join(directory, 'previous.json');
  if (previous.data) await writeFile(previousPath, JSON.stringify(previous.data, null, 2) + '\n');
  if (action === 'reuse') {
    assertDeployable(previous.data, now);
    return { persist: false, deploy: true, data_sha: previous.sha || '' };
  }
  const candidatePath = join(directory, 'candidate.json');
  const { report } = await collect({ previousPath: previous.data ? previousPath : undefined,
    outputPath: candidatePath, reportPath: join(directory, 'report.json'), now });
  // Only validated year/status summaries: never URLs, raw responses or errors.
  console.log(JSON.stringify({ calendarCollection: report }));
  const decision = deploymentDecision(report);
  if (decision.deploy) assertDeployable(JSON.parse(await readFile(candidatePath, 'utf8')), now);
  return { ...decision, data_sha: previous.sha || '' };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const result = await prepareWorkflow({ action: process.env.CALENDAR_ACTION,
      initialize: process.env.CALENDAR_INITIALIZE === 'true', directory: 'artifacts/calendar-pipeline' });
    if (process.env.GITHUB_OUTPUT) await writeFile(process.env.GITHUB_OUTPUT,
      Object.entries(result).map(([key, value]) => `${key}=${value}`).join('\n') + '\n', { flag: 'a' });
    console.log(JSON.stringify(result));
    if (!result.deploy) console.log('Calendar collection incomplete. Pages deployment skipped; previous site is preserved.');
  } catch {
    console.error('CALENDAR_PIPELINE_BLOCKED: initialize approved data or resolve collection/configuration failure. Pages not replaced.');
    process.exitCode = 1;
  }
}
