import assert from 'node:assert/strict';
import test from 'node:test';
import { Ajv2020 } from 'ajv/dist/2020.js';
import common from '../shared/protocol/v1/common.schema.json' with { type: 'json' };
import state from '../shared/protocol/v1/state.schema.json' with { type: 'json' };
import media from '../shared/protocol/v1/media.schema.json' with { type: 'json' };
import browse from '../shared/protocol/v1/browse.schema.json' with { type: 'json' };
import session from '../shared/protocol/v1/session.schema.json' with { type: 'json' };
import command from '../shared/protocol/v1/command.schema.json' with { type: 'json' };

const ajv = new Ajv2020({ strict: true, allErrors: true });

ajv.addSchema(common);

ajv.addSchema(state);

ajv.addSchema(media);

ajv.addSchema(browse);

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
    shuffle: false,
    repeat: 'off',
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
  assert.equal(
    validateSession({
      version: 1,
      type: 'state',
      snapshot: { ...snapshot, repeat: 'forever' },
    }),
    false,
  );
  const { shuffle: _shuffle, ...withoutShuffle } = snapshot;
  assert.equal(
    validateSession({ version: 1, type: 'state', snapshot: withoutShuffle }),
    false,
  );
});

test('browse requests name exactly one source and results stay within their bounds', () => {
  /** @param {Record<string, unknown>} browse */
  const request = (browse) => ({
    version: 1,
    type: 'browse.get',
    request_id: uuid,
    browse,
  });

  const song = { source: 'library', id: 'AB1234567890CDEF' };

  assert.equal(validateSession(request({ kind: 'playlists' })), true);
  assert.equal(
    validateSession(request({ kind: 'playlist', id: 'AB1234567890CDEF' })),
    true,
  );
  assert.equal(
    validateSession(request({ kind: 'artist', id: '159260351' })),
    true,
  );
  assert.equal(validateSession(request({ kind: 'album', song })), true);
  assert.equal(validateSession(request({ kind: 'playlist' })), false);
  assert.equal(validateSession(request({ kind: 'playlists', id: '1' })), false);
  assert.equal(
    validateSession(request({ kind: 'album', id: '1', song })),
    false,
  );
  assert.equal(validateSession(request({ kind: 'album' })), false);
  assert.equal(
    validateSession(request({ kind: 'artist', id: '1; drop' })),
    false,
  );

  const result = {
    version: 1,
    type: 'browse.result',
    request_id: uuid,
    browse: {
      kind: 'artist',
      id: '159260351',
      title: 'Artist',
      detail: 'Pop',
      sections: [
        {
          id: 'top_songs',
          title: 'Top Songs',
          items: [
            {
              type: 'song',
              song: {
                source: 'catalog',
                id: '1',
                title: 'Song',
                artist: 'Artist',
                album: 'Album',
              },
            },
          ],
        },
        {
          id: 'albums',
          title: 'Albums',
          items: [
            {
              type: 'album',
              id: '2',
              title: 'Album',
              artwork_url: 'https://is1-ssl.mzstatic.com/image/thumb/a.jpg',
            },
          ],
        },
      ],
    },
  };

  assert.equal(
    validateSession(result),
    true,
    JSON.stringify(validateSession.errors),
  );
  assert.equal(
    validateSession({
      ...result,
      browse: {
        ...result.browse,
        sections: Array.from({ length: 9 }, (_, index) => ({
          id: `s${index}`,
          title: 'Section',
          items: [],
        })),
      },
    }),
    false,
  );
  assert.equal(
    validateSession({
      ...result,
      browse: {
        ...result.browse,
        sections: [
          {
            id: 'albums',
            title: 'Albums',
            items: [
              {
                type: 'album',
                id: '2',
                title: 'Album',
                artwork_url: 'https://example.com/a.jpg',
              },
            ],
          },
        ],
      },
    }),
    false,
  );
});

test('lyric lines may be placed at the end only by an explicit alignment', () => {
  const line = {
    id: 'l1',
    text: 'Hello',
    start_ms: 0,
    end_ms: 1000,
    words: [],
  };

  /** @param {Record<string, unknown>[]} lines */
  const lyrics = (lines) => ({
    version: 1,
    type: 'lyrics',
    request_id: uuid,
    lyrics: {
      occurrence_id: uuid,
      revision: uuid,
      translation_source: 'none',
      source: 'apple_music',
      lines,
    },
  });

  assert.equal(validateSession(lyrics([line])), true);
  assert.equal(validateSession(lyrics([{ ...line, align: 'end' }])), true);
  assert.equal(validateSession(lyrics([{ ...line, align: 'middle' }])), false);
});

test('Sing state is bounded and exposes failure without carrying audio', () => {
  const snapshot = {
    host_id: uuid,
    host_epoch: uuid,
    revision: 0,
    sequence: 1,
    host_time_ms: 500,
    allow_cross_remote_edits: false,
    playing: true,
    volume: 50,
    shuffle: true,
    repeat: 'all',
    queue: [],
    quality: 'unknown',
    synchronized: true,
    observation_gap: false,
    sing: {
      status: 'failed',
      vocal_percent: 0,
      latency_ms: 120,
      backend: 'coreml',
      issue: 'Audio capture permission is required.',
    },
  };

  assert.equal(validateSession({ version: 1, type: 'state', snapshot }), true);
  assert.equal(
    validateSession({
      version: 1,
      type: 'state',
      snapshot: { ...snapshot, sing: { ...snapshot.sing, vocal_percent: 101 } },
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

test('search suggestions use the search query bound and answer with terms and songs', () => {
  assert.equal(
    validateSession({
      version: 1,
      type: 'search.suggest',
      request_id: uuid,
      query: 'akad',
    }),
    true,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'search.suggest',
      request_id: uuid,
      query: 'x'.repeat(201),
    }),
    false,
  );
  assert.equal(
    validateSession({ version: 1, type: 'search.suggest', query: 'akad' }),
    false,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'search.suggestions',
      request_id: uuid,
      terms: ['Breathe', 'Breathe Deeper'],
      songs: [],
    }),
    true,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'search.suggestions',
      request_id: uuid,
      songs: [],
    }),
    false,
  );
});

test('song metadata rides only on song.prepare and uses the song field bounds', () => {
  const song = { source: 'library', id: '0123456789ABCDEF' };

  const metadata = {
    source: 'library',
    id: '0123456789ABCDEF',
    title: 'Saved song',
    artist: 'Artist',
    album: 'Album',
    duration_ms: null,
    artwork_url: null,
  };

  assert.equal(
    validateSession({
      version: 1,
      type: 'song.prepare',
      request_id: uuid,
      song,
      song_metadata: metadata,
    }),
    true,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'song.ready',
      request_id: uuid,
      song,
      song_metadata: metadata,
    }),
    false,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'song.prepare',
      request_id: uuid,
      song,
      song_metadata: { ...metadata, source: 'unknown' },
    }),
    false,
  );
});

test('an error frame may name the request or command it refuses, and must give its code', () => {
  assert.equal(
    validateSession({
      version: 1,
      type: 'error',
      command_id: uuid,
      error_code: 'invalid_command',
      message: 'The command contains unexpected or missing fields.',
    }),
    true,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'error',
      request_id: uuid,
      error_code: 'busy',
    }),
    true,
  );
  assert.equal(
    validateSession({ version: 1, type: 'error', command_id: uuid }),
    false,
  );
  assert.equal(
    validateSession({
      version: 1,
      type: 'error',
      command_id: 'not-an-id',
      error_code: 'invalid_command',
    }),
    false,
  );
});
