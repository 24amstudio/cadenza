import assert from 'node:assert/strict';
import test from 'node:test';
import { Ajv2020 } from 'ajv/dist/2020.js';
import common from '../shared/protocol/v1/common.schema.json' with { type: 'json' };
import state from '../shared/protocol/v1/state.schema.json' with { type: 'json' };
import session from '../shared/protocol/v1/session.schema.json' with { type: 'json' };
import command from '../shared/protocol/v1/command.schema.json' with { type: 'json' };

const ajv = new Ajv2020({ strict: true, allErrors: true });

ajv.addSchema(common);

ajv.addSchema(state);

const validateSession = ajv.compile(session);
const validateCommand = ajv.compile(command);
const uuid = '00000000-0000-4000-8000-000000000001';

test('capability-negotiated heartbeats and Remote preferences require their complete bounded payload', () => {
  assert.equal(
    validateSession({ version: 1, type: 'heartbeat', host_epoch: uuid }),
    true,
  );
  assert.equal(validateSession({ version: 1, type: 'heartbeat' }), false);
  assert.equal(
    validateSession({
      version: 1,
      type: 'remote.configure',
      request_id: uuid,
      name: 'Bedroom tablet',
      heartbeat: true,
    }),
    true,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'remote.configure',
      request_id: uuid,
      name: '',
      heartbeat: true,
    }),
    false,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'remote.configure',
      request_id: uuid,
      name: 'Tablet',
      heartbeat: 'true',
    }),
    false,
  );
});

test('status lookup carries a command ID without a mutation or caller-supplied identity', () => {
  const request = {
    version: 1,
    type: 'command.status',
    command_id: uuid,
    request_id: uuid,
  };

  assert.equal(validateSession(request), true);
  assert.equal(validateSession({ version: 1, type: 'command.status' }), false);
  assert.equal(validateSession({ ...request, requested_by: uuid }), false);
  assert.equal(
    validateSession({
      version: 1,
      type: 'search',
      request_id: uuid,
      query: 'song',
      scope: 'library',
    }),
    true,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'search',
      request_id: uuid,
      query: 'song',
      scope: 'all_accounts',
    }),
    false,
  );
});

test('Play Now requires a song identity and an explicit current-occurrence guard', () => {
  const base = {
    version: 1,
    type: 'command',
    command_id: uuid,
    host_epoch: uuid,
    expires_at_host_ms: 900,
    expected_revision: 0,
  };

  const song = { source: 'catalog', id: '100' };
  assert.equal(
    validateCommand({
      ...base,
      action: { kind: 'queue.play_now', song, occurrence_id: uuid },
    }),
    true,
  );
  assert.equal(
    validateCommand({
      ...base,
      action: { kind: 'queue.play_now', song, occurrence_id: null },
    }),
    true,
  );
  assert.equal(
    validateCommand({ ...base, action: { kind: 'queue.play_now', song } }),
    false,
  );
  assert.equal(
    validateCommand({
      ...base,
      action: { kind: 'queue.play_now', song, occurrence_id: 'anything' },
    }),
    false,
  );
});

test('state preserves unknown quality and durations without presenting invented formats', () => {
  const snapshot = {
    host_id: uuid,
    host_epoch: uuid,
    revision: 0,
    sequence: 1,
    host_time_ms: 500,
    allow_cross_remote_edits: false,
    playing: false,
    volume: 50,
    queue: [],
    quality: 'unknown',
    synchronized: false,
    observation_gap: false,
  };

  assert.equal(validateSession({ version: 1, type: 'state', snapshot }), true);
  assert.equal(
    validateSession({
      version: 1,
      type: 'state',
      snapshot: { ...snapshot, quality: 'available_in_album' },
    }),
    false,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'state',
      snapshot: { ...snapshot, total_remaining_ms: -1 },
    }),
    false,
  );
});

test('Host artwork requests require bounded URL payloads and cached responses', () => {
  const request = {
    version: 1,
    type: 'artwork.get',
    request_id: uuid,
    artwork_url: 'https://is1-ssl.mzstatic.com/image/thumb/Music/example.jpg',
  };

  assert.equal(validateSession(request), true);
  assert.equal(
    validateSession({ ...request, artwork_url: 'not a URL' }),
    false,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'artwork',
      request_id: uuid,
      artwork_url: request.artwork_url,
      artwork_data_base64: 'a'.repeat(700_000),
    }),
    true,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'artwork',
      request_id: uuid,
      artwork_url: request.artwork_url,
      artwork_data_base64: 'a'.repeat(700_001),
    }),
    false,
  );
});

test('lyric state carries a validated Host provider source', () => {
  const document = {
    occurrence_id: uuid,
    revision: uuid,
    translation_source: 'original',
    source: 'lrclib',
    lines: [
      { id: 'line-1', text: 'Hello', start_ms: 0, end_ms: 1000, words: [] },
    ],
  };

  assert.equal(
    validateSession({ version: 1, type: 'lyrics', lyrics: document }),
    true,
  );
});

test('host update frames accept only the check and install actions', () => {
  assert.equal(
    validateSession({
      version: 1,
      type: 'host.update',
      request_id: uuid,
      update_action: 'check',
    }),
    true,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'host.update',
      request_id: uuid,
      update_action: 'install',
    }),
    true,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'host.update',
      request_id: uuid,
      update_action: 'download',
    }),
    false,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'host.update',
      update_action: 'check',
    }),
    false,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'host.update.status',
      request_id: uuid,
      update_state: 'ready',
      update_version: '0.0.4',
    }),
    true,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'host.update.status',
      request_id: uuid,
      update_state: 'rebooting',
    }),
    false,
  );
});
