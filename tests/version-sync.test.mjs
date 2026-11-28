import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

/** @param {string} path */
function read(path) {
  return readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
}

/** @param {string} name */
function versionProperty(name) {
  return read('shared/version.properties')
    .match(new RegExp(`^${name}=(.+)$`, 'm'))?.[1]
    ?.trim();
}

test('the Host bundle, the web Remote, and the changelog head agree with shared/version.properties', () => {
  const name = versionProperty('VERSION_NAME');
  const build = versionProperty('VERSION_CODE');
  const plist = read('apps/host/Resources/Info.plist');
  const latest = JSON.parse(read('shared/changelog.json')).releases[0];

  assert.equal(
    plist.match(/CFBundleShortVersionString<\/key><string>([^<]+)</)?.[1],
    name,
  );
  assert.equal(
    plist.match(/CFBundleVersion<\/key><string>([^<]+)</)?.[1],
    build,
  );
  assert.equal(JSON.parse(read('apps/web/package.json')).version, name);
  assert.equal(latest.version, name);
  assert.equal(String(latest.build), build);
});

test('the checked-in release is 0.4.6, the release this change set ships', () => {
  assert.equal(versionProperty('VERSION_NAME'), '0.4.6');
  assert.ok(Number(versionProperty('VERSION_CODE')) > 14);
});
