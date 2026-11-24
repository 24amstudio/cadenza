#!/usr/bin/env node
// Builds the release notes and the signed comparison fields for a Production release.
// CI runs `previous-tag` to find the last published release, then `write` before signing.
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

/**
 * @typedef {{ sha: string, subject: string, files: string[] }} Commit
 * @typedef {{ tag_name: string, draft: boolean, prerelease: boolean }} Release
 * @typedef {{
 *   repository: string,
 *   runNumber: string,
 *   shortSha: string,
 *   tag: string,
 *   previousTag: string,
 *   shortstat: string,
 *   generatedBody: string,
 *   commits: Commit[],
 * }} ReleaseNotesInput
 */

export const releaseTagPattern =
  /^v[0-9]+\.[0-9]+\.[0-9]+(_[0-9]{8}\.[0-9]+-[0-9a-f]{12})?$/;

// Matches ReleaseValidation.releaseNotesLimit in apps/host, which is measured in UTF-8 bytes.
export const releaseNotesByteLimit = 16_384;

const commitsPerArea = 50;
const otherArea = 'Other & Documentation';
const areas = ['apps/host', 'apps/remote', 'shared', 'tools'];

const repositoryPattern =
  /^[A-Za-z0-9][A-Za-z0-9_.-]{0,38}\/[A-Za-z0-9_.-]{1,100}$/;

const shaPattern = /^[0-9a-f]{40}$/;

/**
 * @param {string} repository
 * @param {string} previousTag
 * @param {string} tag
 * @returns {string}
 */
export function compareUrl(repository, previousTag, tag) {
  return `https://github.com/${repository}/compare/${previousTag}...${tag}`;
}

/**
 * @param {string} file
 * @returns {string}
 */
function areaOf(file) {
  return (
    areas.find((area) => file === area || file.startsWith(`${area}/`)) ??
    otherArea
  );
}

/**
 * A commit touching several areas is listed under each of them.
 * @param {Commit[]} commits
 * @returns {Map<string, Commit[]>}
 */
export function groupCommits(commits) {
  /** @type {Map<string, Commit[]>} */
  const groups = new Map([...areas, otherArea].map((area) => [area, []]));

  for (const commit of commits) {
    for (const area of new Set(commit.files.map(areaOf))) {
      groups.get(area)?.push(commit);
    }
  }

  return groups;
}

/**
 * Parses `git log --format=%x1e%h%x1f%s --name-only` output.
 * @param {string} output
 * @returns {Commit[]}
 */
export function parseGitLog(output) {
  return output
    .split('\x1e')
    .map((record) => record.trim())
    .filter(Boolean)
    .map((record) => {
      const [header = '', ...files] = record.split('\n');
      const [sha = '', subject = ''] = header.split('\x1f');

      return { sha, subject, files: files.filter(Boolean) };
    });
}

/**
 * @param {string} area
 * @param {Commit[]} commits
 * @returns {string[]}
 */
function commitSection(area, commits) {
  const lines = [`### ${area}`];

  if (commits.length === 0) return [...lines, '- No commits.'];

  for (const commit of commits.slice(0, commitsPerArea)) {
    lines.push(`- ${commit.sha} ${commit.subject}`);
  }

  if (commits.length > commitsPerArea) {
    lines.push(`- ${commits.length - commitsPerArea} more commits.`);
  }

  return lines;
}

/**
 * @param {string} text
 * @returns {boolean}
 */
function withinByteLimit(text) {
  return Buffer.byteLength(text, 'utf8') <= releaseNotesByteLimit;
}

/**
 * Drops trailing lines until the notes fit the signed manifest, and says so when that happens.
 * @param {string} text
 * @returns {string}
 */
export function fitNotes(text) {
  if (withinByteLimit(text)) return text;

  const notice =
    '_The release notes were shortened to fit the signed manifest._';

  const lines = text.split('\n');

  while (
    lines.length > 0 &&
    !withinByteLimit([...lines, '', notice].join('\n'))
  ) {
    lines.pop();
  }

  return [...lines, '', notice].join('\n');
}

/**
 * @param {ReleaseNotesInput} input
 * @returns {string}
 */
export function buildReleaseNotes({
  repository,
  runNumber,
  shortSha,
  tag,
  previousTag,
  shortstat,
  generatedBody,
  commits,
}) {
  const lines = [
    `Automated Production build ${runNumber} from \`${shortSha}\`.`,
  ];

  if (previousTag) {
    lines.push(
      '',
      `## Changes since ${previousTag}`,
      '',
      shortstat || 'No file changes.',
      '',
      `Compare: ${compareUrl(repository, previousTag, tag)}`,
    );
  } else {
    lines.push(
      '',
      'No earlier published release was found, so no comparison is available.',
    );
  }

  if (generatedBody) {
    lines.push(
      '',
      '## Pull requests and contributors',
      '',
      generatedBody.trim(),
    );
  }

  if (previousTag) {
    lines.push('', '## Commits by area');

    for (const [area, group] of groupCommits(commits)) {
      lines.push('', ...commitSection(area, group));
    }
  }

  return fitNotes(lines.join('\n'));
}

/**
 * @param {string[]} args
 * @returns {string}
 */
function git(args) {
  return execFileSync('git', args, {
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  }).trim();
}

/**
 * @param {string[]} args
 * @returns {string}
 */
function gh(args) {
  return execFileSync('gh', args, {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
}

/**
 * @param {string[]} args
 * @param {string} name
 * @returns {string | undefined}
 */
function option(args, name) {
  const index = args.indexOf(`--${name}`);

  return index === -1 ? undefined : args[index + 1];
}

/**
 * @param {string[]} args
 * @param {string} name
 * @param {RegExp} [pattern]
 * @returns {string}
 */
function requireOption(args, name, pattern) {
  const value = option(args, name);

  if (!value || (pattern && !pattern.test(value))) {
    throw new Error(`--${name} is missing or invalid.`);
  }

  return value;
}

/**
 * The newest published release that is not the one being built.
 * @param {Release[]} releases
 * @param {string} currentTag
 * @returns {string}
 */
export function previousPublishedTag(releases, currentTag) {
  const release = releases.find(
    (candidate) =>
      candidate.draft === false &&
      candidate.prerelease === false &&
      candidate.tag_name !== currentTag &&
      releaseTagPattern.test(candidate.tag_name),
  );

  return release?.tag_name ?? '';
}

/**
 * @param {string[]} args
 */
function previousTagCommand(args) {
  const repository = requireOption(args, 'repository', repositoryPattern);
  const currentTag = requireOption(args, 'current-tag', releaseTagPattern);
  /** @type {Release[]} */

  const releases = JSON.parse(
    gh(['api', `repos/${repository}/releases?per_page=20`]),
  );

  process.stdout.write(previousPublishedTag(releases, currentTag));
}

/**
 * @param {string[]} args
 */
function writeCommand(args) {
  const repository = requireOption(args, 'repository', repositoryPattern);
  const sha = requireOption(args, 'sha', shaPattern);
  const tag = requireOption(args, 'tag', releaseTagPattern);
  const runNumber = requireOption(args, 'run-number', /^[0-9]+$/);
  const outDirectory = requireOption(args, 'out-dir');
  const previousTag = option(args, 'previous-tag') ?? '';

  if (previousTag && !releaseTagPattern.test(previousTag)) {
    throw new Error('--previous-tag is invalid.');
  }

  const range = previousTag ? `${previousTag}..${sha}` : undefined;
  const shortSha = git(['rev-parse', '--short=12', sha]);
  const shortstat = range ? git(['diff', '--shortstat', range]) : '';

  const commits = range
    ? parseGitLog(
        git([
          'log',
          '--no-merges',
          '--name-only',
          '--format=%x1e%h%x1f%s',
          range,
        ]),
      )
    : [];

  const generateArgs = [
    'api',
    '-X',
    'POST',
    `repos/${repository}/releases/generate-notes`,
    '-f',
    `tag_name=${tag}`,
    '-f',
    `target_commitish=${sha}`,
  ];

  if (previousTag) generateArgs.push('-f', `previous_tag_name=${previousTag}`);
  const generatedBody = JSON.parse(gh(generateArgs)).body ?? '';

  const notes = buildReleaseNotes({
    repository,
    runNumber,
    shortSha,
    tag,
    previousTag,
    shortstat,
    generatedBody,
    commits,
  });

  mkdirSync(outDirectory, { recursive: true });
  writeFileSync(join(outDirectory, 'release-notes.md'), `${notes}\n`);

  const context = {
    previousTag: previousTag || null,
    compareUrl: previousTag ? compareUrl(repository, previousTag, tag) : null,
    releaseNotes: notes,
  };

  writeFileSync(
    join(outDirectory, 'release-context.json'),
    `${JSON.stringify(context, null, 2)}\n`,
  );
  process.stdout.write(`Release notes written to ${outDirectory}\n`);
}

/**
 * @param {string[]} argv
 */
function main(argv) {
  const [command, ...args] = argv;

  if (command === 'previous-tag') return previousTagCommand(args);

  if (command === 'write') return writeCommand(args);
  throw new Error(
    'Usage: release-notes.mjs previous-tag --repository R --current-tag T | write --repository R --sha S --tag T --run-number N --out-dir D [--previous-tag P]',
  );
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  main(process.argv.slice(2));
}
