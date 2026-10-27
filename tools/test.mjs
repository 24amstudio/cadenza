import { spawnSync } from 'node:child_process';
import { mkdirSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const temporary = join(root, '.cache', 'tmp');

mkdirSync(temporary, { recursive: true });

const tests = readdirSync(join(root, 'tests')).filter((file) =>
  file.endsWith('.test.mjs'),
);

const result = spawnSync(
  process.execPath,
  [
    '--experimental-sqlite',
    '--test',
    ...tests.map((file) => join(root, 'tests', file)),
  ],
  {
    cwd: root,
    stdio: 'inherit',
    env: { ...process.env, TEMP: temporary, TMP: temporary, TMPDIR: temporary },
  },
);

if (result.error) throw result.error;

process.exitCode = result.status ?? 1;
