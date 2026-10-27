import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));

/** @param {string} name @param {string} executable @param {string[]} arguments_ */
function run(name, executable, arguments_) {
  process.stdout.write(`Running ${name} checks...\n`);

  const result = spawnSync(executable, arguments_, {
    cwd: root,
    stdio: 'inherit',
    shell: false,
  });

  if (result.error) throw result.error;

  if (result.status !== 0) throw new Error(`${name} checks failed.`);
}

const remoteCommand =
  process.platform === 'win32'
    ? {
        executable: process.env['ComSpec'] ?? 'cmd.exe',
        arguments: ['/d', '/c', 'apps\\remote\\check.cmd'],
      }
    : { executable: '/bin/bash', arguments: ['apps/remote/check.sh'] };

if (process.platform === 'darwin') {
  run('Host', '/bin/bash', ['apps/host/Scripts/check.sh']);
} else {
  process.stdout.write(
    `Host checks deferred on ${process.platform}; run them on macOS or in Host CI.\n`,
  );
}

run('Remote', remoteCommand.executable, remoteCommand.arguments);

process.stdout.write(
  'Platform-available native checks passed. CI still runs both Host and Remote native checks; device, accessibility, native Music, latency, and update-installation acceptance require their recorded integration runs.\n',
);
