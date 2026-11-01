import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import development from '../package.json' with { type: 'json' };

const root = fileURLToPath(new URL('../', import.meta.url));

const configuredDependencies = process.env['CADENZA_NODE_MODULES'];

const gitCommonDirectory = spawnSync('git', ['rev-parse', '--git-common-dir'], {
  cwd: root,
  encoding: 'utf8',
  stdio: ['ignore', 'pipe', 'ignore'],
}).stdout?.trim();

const sharedRepositoryRoot = gitCommonDirectory
  ? dirname(resolve(root, gitCommonDirectory))
  : null;

const dependenciesRoot =
  configuredDependencies ??
  (existsSync(join(root, 'node_modules', '@oxlint', 'plugins', 'package.json'))
    ? join(root, 'node_modules')
    : sharedRepositoryRoot
      ? join(sharedRepositoryRoot, 'node_modules')
      : join(root, 'node_modules'));

const temporaryDirectory = join(root, '.cache', 'tmp');
const staticOnly = process.argv.includes('--static');

mkdirSync(temporaryDirectory, { recursive: true });

process.env['TEMP'] = temporaryDirectory;

process.env['TMP'] = temporaryDirectory;

process.env['TMPDIR'] = temporaryDirectory;

const excluded = new Set([
  '.git',
  'node_modules',
  '.cache',
  '.tools',
  '.build',
  '.gradle',
  'build',
  'dist',
  'vendor',
]);

const checkedExtensions =
  /\.(mjs|js|ts|json|md|sql|sh|ps1|applescript|swift|kt|kts|xml|plist|modulemap|h|toml|yml|properties|cmd|bat)$/;

const formatExtensions = /\.(mjs|js|ts|json|md|yml|yaml)$/;

for (const [name, version] of Object.entries({
  ...development.devDependencies,
  ...development.overrides,
})) {
  const installed = JSON.parse(
    readFileSync(join(dependenciesRoot, name, 'package.json'), 'utf8'),
  );

  if (installed.version !== version)
    throw new Error(
      `Dependency version mismatch: ${name}; expected ${version}`,
    );
}

/** @param {string} directory @returns {string[]} */
function sourceFiles(directory) {
  const files = [];

  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    if (excluded.has(entry.name)) continue;
    const path = join(directory, entry.name);

    if (entry.isDirectory()) files.push(...sourceFiles(path));
    else if (
      (checkedExtensions.test(entry.name) ||
        entry.name === 'gradlew' ||
        directory.endsWith('.githooks')) &&
      entry.name !== 'package-lock.json'
    )
      files.push(path);
  }

  return files.sort();
}

/** @param {string} executable @param {string[]} arguments_ */
function run(executable, arguments_) {
  const result = spawnSync(executable, arguments_, {
    cwd: root,
    stdio: 'inherit',
    shell: false,
  });

  if (result.error) throw result.error;

  if (result.status !== 0)
    throw new Error(`Check failed: ${executable} ${arguments_.join(' ')}`);
}

const files = sourceFiles(root);

for (const file of files) {
  const content = readFileSync(file, 'utf8');

  if (!content.endsWith('\n') || /[\t ]+$/m.test(content))
    throw new Error(`Whitespace: ${relative(root, file)}`);

  if (content.split(/\r?\n/).length - 1 > 1000)
    throw new Error(`File exceeds 1,000 lines: ${relative(root, file)}`);
}

run(process.execPath, [
  join(dependenciesRoot, 'typescript/bin/tsc'),
  '--project',
  'tsconfig.json',
]);

run(process.execPath, [
  join(dependenciesRoot, 'oxlint/bin/oxlint'),
  '--deny-warnings',
  'tools',
  'tests',
  'types',
  'apps/host/Resources/music.js',
]);

run(process.execPath, [
  join(dependenciesRoot, 'prettier/bin/prettier.cjs'),
  '--check',
  ...files.filter((file) => formatExtensions.test(file)),
]);

const bash =
  process.env['CADENZA_BASH'] ??
  (process.platform === 'win32'
    ? 'C:/Program Files/Git/bin/bash.exe'
    : '/bin/bash');

if (!existsSync(bash))
  throw new Error(
    'Set CADENZA_BASH to an installed Bash executable; no tool will be downloaded.',
  );

for (const file of files.filter(
  (path) =>
    path.endsWith('.sh') ||
    path.endsWith('/gradlew') ||
    path.endsWith('\\gradlew') ||
    path.includes('.githooks'),
)) {
  run(bash, ['-n', file]);
}

if (process.platform === 'win32') {
  const scripts = files.filter((path) => path.endsWith('.ps1'));
  const encoded = Buffer.from(JSON.stringify(scripts)).toString('base64');
  const parse = `$cadenzaFiles = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${encoded}')) | ConvertFrom-Json; foreach ($cadenzaFile in $cadenzaFiles) { $cadenzaTokens = $null; $cadenzaErrors = $null; $null = [Management.Automation.Language.Parser]::ParseFile($cadenzaFile, [ref]$cadenzaTokens, [ref]$cadenzaErrors); if ($cadenzaErrors.Count) { $cadenzaErrors | Write-Error; exit 1 } }`;

  run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', parse]);
}

if (!staticOnly) run(process.execPath, ['tools/test.mjs']);

const actionlintName =
  process.platform === 'win32' ? 'actionlint.exe' : 'actionlint';

const actionlintCandidates = [
  join(root, '.tools', 'actionlint-1.7.12', actionlintName),
  ...(sharedRepositoryRoot
    ? [
        join(
          sharedRepositoryRoot,
          '.tools',
          'actionlint-1.7.12',
          actionlintName,
        ),
      ]
    : []),
];

const workflowLint =
  process.env['CADENZA_ACTIONLINT'] ??
  actionlintCandidates.find((candidate) => existsSync(candidate)) ??
  actionlintCandidates[0] ??
  actionlintName;

if (!existsSync(workflowLint))
  throw new Error(
    'Install verified actionlint 1.7.12 or set CADENZA_ACTIONLINT; see docs/BUILDING.md. No tool was downloaded.',
  );

run(workflowLint, [
  '.github/workflows/checking.yml',
  '.github/workflows/build.yml',
]);

if (process.argv.includes('--portable')) {
  process.stdout.write(
    `${staticOnly ? 'Portable static checks' : 'Portable checks'} passed. Native compile, lint, format, integration, and accessibility checks remain required.\n`,
  );
} else {
  run(process.execPath, ['tools/native-check.mjs']);
}
