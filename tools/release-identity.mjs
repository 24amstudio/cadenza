import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const sha = process.argv[process.argv.indexOf('--sha') + 1] ?? '';
const build = process.argv[process.argv.indexOf('--build') + 1] ?? '';

if (
  !/^[0-9a-f]{40}$/.test(sha ?? '') ||
  !/^\d+$/.test(build ?? '') ||
  Number(build) < 1
)
  throw new Error('A full commit SHA and positive build number are required.');

const properties = readFileSync(
  new URL('../shared/version.properties', import.meta.url),
  'utf8',
);

const baseVersion = properties.match(/^VERSION_NAME=([^\r\n]+)$/m)?.[1];
const baseBuild = Number(properties.match(/^VERSION_CODE=([^\r\n]+)$/m)?.[1]);

if (
  !/^[0-9]+\.[0-9]+\.[0-9]+$/.test(baseVersion ?? '') ||
  !Number.isSafeInteger(baseBuild) ||
  baseBuild < 1
)
  throw new Error(
    'shared/version.properties contains an invalid version or build number.',
  );

/** @param {string[]} args */
const git = (args) => execFileSync('git', args, { encoding: 'utf8' }).trim();
const date = git(['show', '-s', '--format=%cd', '--date=format:%Y%m%d', sha]);
const shortSha = git(['rev-parse', '--short=12', sha]);

if (!/^\d{8}$/.test(date) || !/^[0-9a-f]{12}$/.test(shortSha))
  throw new Error('Git returned an invalid release identity.');

const resolvedBuild = Math.max(Number(build), baseBuild + 1);
const version = `${baseVersion}_${date}.${resolvedBuild}-${shortSha}`;
const title = `Cadenza ${baseVersion}_${date}.${resolvedBuild} (${shortSha})`;

process.stdout.write(
  `CADENZA_RELEASE_VERSION=${version}\nCADENZA_RELEASE_TITLE=${title}\nCADENZA_RELEASE_TAG=v${version}\nCADENZA_BUILD_NUMBER=${resolvedBuild}\n`,
);
