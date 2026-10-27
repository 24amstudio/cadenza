import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync, lstatSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));

/** @type {import('node:child_process').ExecFileSyncOptionsWithStringEncoding} */
const gitOptions = {
  cwd: root,
  encoding: /** @type {const} */ ('utf8'),
  stdio: ['ignore', 'pipe', 'ignore'],
};

const gitPrefix = ['-c', 'safe.directory=' + root.replaceAll('\\', '/')];

const excluded = new Set([
  '.git',
  '.cache',
  '.tools',
  'node_modules',
  'dist',
  'build',
  '.build',
  '.gradle',
  '.kotlin',
  '.swiftpm',
  'secrets',
]);

/** @param {string} directory @returns {string[]} */
function sourceFiles(directory) {
  const files = [];

  for (const item of readdirSync(join(root, directory), {
    withFileTypes: true,
  })) {
    if (
      excluded.has(item.name) ||
      item.name.startsWith('.env') ||
      item.name === 'local.properties'
    )
      continue;
    const file = join(directory, item.name);

    if (item.isDirectory()) files.push(...sourceFiles(file));
    else if (
      item.isFile() &&
      !/\.(jks|keystore|p8|p12|pem|key|pfx)$/.test(file)
    )
      files.push(file);
  }

  return files;
}

let files;
let ownRepository = false;

try {
  const repository = execFileSync(
    'git',
    [...gitPrefix, 'rev-parse', '--show-toplevel'],
    gitOptions,
  ).trim();

  ownRepository = resolve(repository) === resolve(root);

  if (!ownRepository)
    throw new Error(
      "Use source hashing outside this project's own Git repository.",
    );
  files = execFileSync(
    'git',
    [
      ...gitPrefix,
      'ls-files',
      '-z',
      '--cached',
      '--others',
      '--exclude-standard',
    ],
    gitOptions,
  )
    .split('\0')
    .filter(Boolean);
} catch {
  files = sourceFiles('');
}

files = files.map((file) => file.replaceAll('\\', '/')).sort();

const hash = createHash('sha256');

for (const file of files) {
  const path = resolve(root, file);

  if (!lstatSync(path).isFile())
    throw new Error('Build identity requires regular source files.');
  hash.update(file.replaceAll('\\', '/'));
  hash.update('\0');
  hash.update(readFileSync(path));
  hash.update('\0');
}

const source = hash.digest('hex');
let commit = '';

try {
  if (!ownRepository) throw new Error('No project Git history.');
  commit = execFileSync(
    'git',
    [...gitPrefix, 'rev-parse', '--verify', 'HEAD'],
    gitOptions,
  ).trim();
} catch {
  // A new local repository has no commit. Its source digest still identifies the build.
}

const dirty =
  !commit ||
  execFileSync(
    'git',
    [...gitPrefix, 'status', '--porcelain', '--untracked-files=normal'],
    gitOptions,
  ).length > 0;

const identity = commit && !dirty ? commit : 'source-' + source;

process.stdout.write(identity + '\n');
