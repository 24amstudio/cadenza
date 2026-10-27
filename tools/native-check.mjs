import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));

if (process.platform !== 'darwin') {
  throw new Error(
    'The complete Cadenza gate requires macOS for Swift compilation and tests. Run it from the same source on the Mac with the Android command-line toolchain available. No tools were downloaded. check:portable is an explicitly partial check and does not satisfy commit or release gates.',
  );
}

for (const script of ['apps/host/Scripts/check.sh', 'apps/remote/check.sh']) {
  const result = spawnSync('/bin/bash', [script], {
    cwd: root,
    stdio: 'inherit',
  });

  if (result.error) throw result.error;

  if (result.status !== 0) throw new Error(`Native checks failed: ${script}`);
}

process.stdout.write(
  'Portable and native source checks passed. Device, accessibility, native Music, latency, and update-installation acceptance still require their recorded integration runs.\n',
);
