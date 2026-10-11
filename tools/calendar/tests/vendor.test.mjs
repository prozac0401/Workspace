import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';

test('vendored SAX parser and license match the pinned upstream-byte manifest', async () => {
  const base = new URL('../vendor/', import.meta.url);
  const manifest = JSON.parse(await readFile(new URL('manifest.json', base)));
  assert.equal(manifest.name, 'sax'); assert.equal(manifest.version, '1.6.1');
  assert.equal(manifest.license, 'BlueOak-1.0.0');
  assert.deepEqual(manifest.files.map(file => file.path), ['sax.cjs', 'sax-LICENSE.md']);
  for (const file of manifest.files) {
    const bytes = await readFile(new URL(file.path, base));
    assert.equal(bytes.length, file.bytes);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), file.sha256);
  }
});
