import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildReleaseNotes,
  compareUrl,
  groupCommits,
  parseGitLog,
  previousPublishedTag,
  releaseNotesByteLimit,
  releaseTagPattern,
} from '../tools/release-notes.mjs';

const repository = '24amstudio/cadenza';
const previous = 'v0.3.3_20261123.466-b5b9fe643ce4';
const current = 'v0.3.4_20261124.467-1f2e3d4c5b6a';

test('release tags accept published forms and refuse branch names', () => {
  assert.match(previous, releaseTagPattern);
  assert.match('v0.3.4', releaseTagPattern);
  assert.doesNotMatch('feat/cadenza-v0-3-4', releaseTagPattern);
  assert.doesNotMatch('v0.3.4_2026-1f2e3d4c5b6a', releaseTagPattern);
});

test('git log output becomes commits with the files they touched', () => {
  const log =
    '\x1eabc123\x1fAdd host thing\n\napps/host/Sources/A.swift\nshared/x.json\n' +
    '\x1edef456\x1fDocs only\n\nREADME.md\n';

  assert.deepEqual(parseGitLog(log), [
    {
      sha: 'abc123',
      subject: 'Add host thing',
      files: ['apps/host/Sources/A.swift', 'shared/x.json'],
    },
    { sha: 'def456', subject: 'Docs only', files: ['README.md'] },
  ]);
});

test('a commit touching two areas is listed under both, and other files fall under documentation', () => {
  const groups = groupCommits([
    {
      sha: 'a',
      subject: 'Both',
      files: ['apps/host/Sources/A.swift', 'shared/x.json'],
    },
    { sha: 'b', subject: 'Web only', files: ['apps/web/app/x.vue'] },
  ]);

  assert.deepEqual(
    (groups.get('apps/host') ?? []).map((commit) => commit.sha),
    ['a'],
  );
  assert.deepEqual(
    (groups.get('shared') ?? []).map((commit) => commit.sha),
    ['a'],
  );
  assert.deepEqual(
    (groups.get('Other & Documentation') ?? []).map((commit) => commit.sha),
    ['b'],
  );
});

test('notes compare the release with the previous one and list its changes', () => {
  const notes = buildReleaseNotes({
    repository,
    runNumber: '467',
    shortSha: '1f2e3d4c5b6a',
    tag: current,
    previousTag: previous,
    shortstat: ' 3 files changed, 40 insertions(+), 2 deletions(-)',
    generatedBody: 'What is new: #70 Add lock-screen artwork',
    commits: [
      {
        sha: 'abc123',
        subject: 'Add host thing',
        files: ['apps/host/A.swift'],
      },
    ],
  });

  assert.match(notes, /^Automated Production build 467 from `1f2e3d4c5b6a`\./);
  assert.ok(
    notes.includes(`Compare: ${compareUrl(repository, previous, current)}`),
  );
  assert.ok(
    notes.includes('3 files changed, 40 insertions(+), 2 deletions(-)'),
  );
  assert.ok(notes.includes('What is new: #70 Add lock-screen artwork'));
  assert.ok(notes.includes('- abc123 Add host thing'));
});

test('without an earlier published release no comparison is invented', () => {
  const notes = buildReleaseNotes({
    repository,
    runNumber: '1',
    shortSha: '1f2e3d4c5b6a',
    tag: current,
    previousTag: '',
    shortstat: '',
    generatedBody: '',
    commits: [],
  });

  assert.ok(notes.includes('no comparison is available'));
  assert.equal(notes.includes('Compare:'), false);
  assert.equal(notes.includes('Commits by area'), false);
});

test('oversized notes are shortened to the signed byte limit and say so', () => {
  const notes = buildReleaseNotes({
    repository,
    runNumber: '9',
    shortSha: '1f2e3d4c5b6a',
    tag: current,
    previousTag: previous,
    shortstat: '300 files changed',
    generatedBody:
      'A long generated contributor line that GitHub may return.\n'.repeat(
        1_000,
      ),
    commits: [],
  });

  assert.ok(Buffer.byteLength(notes, 'utf8') <= releaseNotesByteLimit);
  assert.ok(notes.includes('shortened to fit the signed manifest'));
  assert.ok(notes.startsWith('Automated Production build 9'));
});

test('the previous release skips drafts, prereleases, and the current tag', () => {
  const releases = [
    { tag_name: current, draft: false, prerelease: false },
    {
      tag_name: 'v0.3.4_20261125.1-aaaaaaaaaaaa',
      draft: true,
      prerelease: false,
    },
    { tag_name: 'v0.3.4-beta', draft: false, prerelease: true },
    { tag_name: previous, draft: false, prerelease: false },
  ];

  assert.equal(previousPublishedTag(releases, current), previous);
  assert.equal(previousPublishedTag([], current), '');
});
