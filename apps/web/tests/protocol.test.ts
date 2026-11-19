import { describe, expect, test } from 'bun:test';
import { decodeHostMessage } from '../app/lib/protocol/decode';
import { encodeArtworkGet, encodeMotionGet } from '../app/lib/protocol/encode';
import type { JsonObject } from '../app/lib/protocol/json';
import type { SongIdentity } from '../app/lib/protocol/types';
import {
  encodeClock,
  encodeCommand,
  encodeHello,
  encodePair,
  encodeRemoteConfigure,
  encodeSearch,
  encodeSearchSuggest,
  encodeSongPrepare,
  encodeBrowseGet,
  encodeOperationCancel,
} from '../app/lib/protocol/encode';

const remoteId = '3f1c2a2e-7b6d-4c1e-9a1f-2d3e4f5a6b7c';
const epoch = '6e4f9a10-1111-4222-8333-444455556666';
const occurrenceId = '0a0b0c0d-1111-4222-8333-444455556666';

const song = {
  source: 'catalog',
  id: '1440857781',
  title: 'Breathe Deeper',
  artist: 'Tame Impala',
  album: 'The Slow Rush',
  duration_ms: 372000,
  artwork_url: 'https://example.com/art.jpg',
};

const snapshot = {
  host_id: remoteId,
  host_epoch: epoch,
  revision: 18,
  sequence: 4,
  host_time_ms: 90000,
  allow_cross_remote_edits: false,
  playing: true,
  volume: 40,
  shuffle: true,
  repeat: 'all',
  current: {
    occurrence_id: occurrenceId,
    requester_name: 'Mia',
    song,
    position_ms: 126000,
    sampled_at_host_ms: 89000,
  },
  queue: [
    {
      id: 'entry-1',
      requester_name: 'Alex',
      song: { ...song, id: '2', title: 'Borderline' },
      estimated_wait_ms: 360000,
    },
  ],
  quality: 'unknown',
  synchronized: true,
  observation_gap: false,
};

function wire(message: JsonObject): string {
  return JSON.stringify({ version: 1, ...message });
}

describe('artwork frames', () => {
  test('a preview and a chunk decode with their variant and integrity fields', () => {
    expect(
      decodeHostMessage(
        JSON.stringify({
          version: 1,
          type: 'artwork',
          request_id: remoteId,
          artwork_url: 'https://example.com/a.jpg',
          artwork_data_base64: '/9j/',
          variant: 'preview',
        }),
      ),
    ).toMatchObject({ type: 'artwork', variant: 'preview' });

    expect(
      decodeHostMessage(
        JSON.stringify({
          version: 1,
          type: 'artwork.chunk',
          request_id: remoteId,
          artwork_url: 'https://example.com/a.jpg',
          chunk_index: 2,
          chunk_count: 5,
          total_bytes: 4000,
          sha256: 'ab',
          data_base64: 'AAAA',
        }),
      ),
    ).toMatchObject({
      type: 'artwork.chunk',
      index: 2,
      count: 5,
      totalBytes: 4000,
    });
  });

  test('an artwork frame without a variant is the full image', () => {
    expect(
      decodeHostMessage(
        JSON.stringify({
          version: 1,
          type: 'artwork',
          request_id: remoteId,
          artwork_url: 'https://example.com/a.jpg',
          artwork_data_base64: '/9j/',
        }),
      ),
    ).toMatchObject({ type: 'artwork', variant: 'full' });
  });

  test('a progressive request is marked, and a plain one is unchanged', () => {
    const url = 'https://example.com/a.jpg';
    const plain = { previewOnly: false };

    expect(
      JSON.parse(
        encodeArtworkGet(remoteId, url, { ...plain, progressive: true }),
      ),
    ).toEqual({
      version: 1,
      type: 'artwork.get',
      request_id: remoteId,
      artwork_url: url,
      progressive: true,
    });
    expect(
      JSON.parse(
        encodeArtworkGet(remoteId, url, { ...plain, progressive: false }),
      ),
    ).not.toHaveProperty('progressive');
  });

  test('a preview-only request names no full image, and a motion request names its occurrence', () => {
    const url = 'https://example.com/a.jpg';

    expect(
      JSON.parse(
        encodeArtworkGet(remoteId, url, {
          progressive: true,
          previewOnly: true,
        }),
      ),
    ).toMatchObject({ preview_only: true });
    expect(JSON.parse(encodeMotionGet(remoteId, occurrenceId))).toEqual({
      version: 1,
      type: 'motion.get',
      request_id: remoteId,
      occurrence_id: occurrenceId,
    });
  });

  test('a refused motion request is decoded with its request and occurrence', () => {
    expect(
      decodeHostMessage(
        JSON.stringify({
          version: 1,
          type: 'motion.unavailable',
          request_id: remoteId,
          occurrence_id: occurrenceId,
        }),
      ),
    ).toEqual({
      type: 'motion.unavailable',
      requestId: remoteId,
      occurrenceId,
    });
  });
});

describe('decodeHostMessage', () => {
  test('decodes a state snapshot into camelCase domain values', () => {
    const message = decodeHostMessage(wire({ type: 'state', snapshot }));

    expect(message).toMatchObject({
      type: 'state',
      snapshot: {
        revision: 18,
        playing: true,
        volume: 40,
        shuffle: true,
        repeat: 'all',
        current: {
          occurrenceId,
          positionMs: 126000,
          sampledAtHostMs: 89000,
          song: { title: 'Breathe Deeper', durationMs: 372000 },
        },
        queue: [{ id: 'entry-1', estimatedWaitMs: 360000 }],
      },
    });
  });

  test('a state carries the song cover, so the title and the cover arrive together', () => {
    const message = decodeHostMessage(
      wire({
        type: 'state',
        snapshot: {
          ...snapshot,
          current: { ...snapshot.current, artwork_preview: '/9j/4AAQ' },
        },
      }),
    );

    expect(message).toMatchObject({
      type: 'state',
      snapshot: { current: { artworkPreview: '/9j/4AAQ' } },
    });
  });

  test('rejects a snapshot without the playback modes', () => {
    const { shuffle: _shuffle, ...withoutShuffle } = snapshot;
    const { repeat: _repeat, ...withoutRepeat } = snapshot;

    for (const broken of [
      withoutShuffle,
      withoutRepeat,
      { ...snapshot, repeat: 'forever' },
    ]) {
      expect(
        decodeHostMessage(wire({ type: 'state', snapshot: broken })),
      ).toBeNull();
    }
  });

  test('rejects the whole snapshot when one queue entry is malformed', () => {
    const broken = { ...snapshot, queue: [{ id: 'entry-1' }] };

    expect(
      decodeHostMessage(wire({ type: 'state', snapshot: broken })),
    ).toBeNull();
  });

  test('rejects counters that are negative or outside the protocol range', () => {
    const negative = { ...snapshot, revision: -1 };
    const oversized = { ...snapshot, revision: Number.MAX_SAFE_INTEGER + 1 };

    expect(
      decodeHostMessage(wire({ type: 'state', snapshot: negative })),
    ).toBeNull();
    expect(
      decodeHostMessage(wire({ type: 'state', snapshot: oversized })),
    ).toBeNull();
  });

  test('decodes a welcome and keeps the token only when the Host sends one', () => {
    const welcome = {
      host_id: remoteId,
      host_name: 'Living room Mac',
      host_epoch: epoch,
      remote_id: remoteId,
      token: 'x'.repeat(40),
      host_time_ms: 1000,
      capabilities: ['artwork.host-cache', 'lyrics.lrclib'],
    };

    expect(decodeHostMessage(wire({ type: 'welcome', welcome }))).toMatchObject(
      {
        type: 'welcome',
        welcome: { hostName: 'Living room Mac', token: 'x'.repeat(40) },
      },
    );
    const withoutToken = { ...welcome, token: null };
    expect(
      decodeHostMessage(wire({ type: 'welcome', welcome: withoutToken })),
    ).toMatchObject({
      welcome: { token: null },
    });
  });

  test('decodes command results and rejects unknown outcomes', () => {
    const result = {
      command_id: occurrenceId,
      host_epoch: epoch,
      outcome: 'rejected',
      revision: 18,
      error_code: 'stale_revision',
    };

    expect(
      decodeHostMessage(wire({ type: 'command.result', ...result })),
    ).toMatchObject({
      result: { outcome: 'rejected', errorCode: 'stale_revision' },
    });
    expect(
      decodeHostMessage(
        wire({ type: 'command.result', ...result, outcome: 'maybe' }),
      ),
    ).toBeNull();
  });

  test('ignores messages the web client does not handle and invalid JSON', () => {
    expect(
      decodeHostMessage(wire({ type: 'session.status', status: {} })),
    ).toBeNull();
    expect(decodeHostMessage('{not json')).toBeNull();
    expect(decodeHostMessage('[1,2,3]')).toBeNull();
  });

  test('decodes timed lyrics with word timing', () => {
    const lyrics = {
      occurrence_id: occurrenceId,
      revision: 'rev-1',
      translation_source: 'none',
      source: 'apple_music',
      lines: [
        {
          id: 'line-1',
          text: 'I was doing fine',
          start_ms: 1000,
          end_ms: 3000,
          words: [{ text: 'I ', start_ms: 1000, end_ms: 1400 }],
        },
      ],
    };

    expect(
      decodeHostMessage(wire({ type: 'lyrics', request_id: remoteId, lyrics })),
    ).toMatchObject({
      type: 'lyrics',
      lyrics: {
        lines: [{ startMs: 1000, words: [{ text: 'I ', endMs: 1400 }] }],
      },
    });
  });

  test('a lyric line placed at the end is right-aligned, and any other value is the start', () => {
    const line = (align: string | null) => ({
      id: 'line',
      text: 'Hello',
      start_ms: 0,
      end_ms: 1000,
      words: [],
      align,
    });

    const decoded = decodeHostMessage(
      wire({
        type: 'lyrics',
        request_id: remoteId,
        lyrics: {
          occurrence_id: occurrenceId,
          revision: 'rev-1',
          translation_source: 'none',
          source: 'lrclib',
          lines: [line('end'), line('start'), line(null), line('middle')],
        },
      }),
    );

    expect(decoded).toMatchObject({
      type: 'lyrics',
      lyrics: {
        lines: [
          { align: 'end' },
          { align: 'start' },
          { align: 'start' },
          { align: 'start' },
        ],
      },
    });
  });

  test('decodes a clock reply used for Host-time estimates', () => {
    const clock = {
      sent_at_remote_ms: 10,
      received_at_host_ms: 5010,
      sent_at_host_ms: 5011,
    };

    expect(
      decodeHostMessage(wire({ type: 'clock', request_id: remoteId, clock })),
    ).toMatchObject({
      type: 'clock',
      sample: {
        sentAtRemoteMs: 10,
        receivedAtHostMs: 5010,
        sentAtHostMs: 5011,
      },
    });
  });
});

describe('outgoing frames', () => {
  test('command frames carry exactly the keys the Host accepts for each action', () => {
    const base = {
      commandId: remoteId,
      hostEpoch: epoch,
      expiresAtHostMs: 9000,
      expectedRevision: 18,
    };

    const pause = JSON.parse(
      encodeCommand({
        ...base,
        action: { kind: 'playback.pause', occurrenceId },
      }),
    );

    expect(Object.keys(pause).sort()).toEqual(
      [
        'action',
        'command_id',
        'expected_revision',
        'expires_at_host_ms',
        'host_epoch',
        'type',
        'version',
      ].sort(),
    );
    expect(pause.action).toEqual({
      kind: 'playback.pause',
      occurrence_id: occurrenceId,
    });

    const seek = JSON.parse(
      encodeCommand({
        ...base,
        action: { kind: 'playback.seek', occurrenceId, positionMs: 4200 },
      }),
    );

    expect(seek.action).toEqual({
      kind: 'playback.seek',
      occurrence_id: occurrenceId,
      position_ms: 4200,
    });

    const volume = JSON.parse(
      encodeCommand({
        ...base,
        action: { kind: 'playback.volume', percent: 65 },
      }),
    );

    expect(volume.action).toEqual({ kind: 'playback.volume', percent: 65 });
  });

  test('pairing and hello frames use the snake_case contract', () => {
    expect(
      JSON.parse(
        encodePair({ secret: 's'.repeat(40) }, 'Mac', 'cadenza-web 1'),
      ),
    ).toEqual({
      version: 1,
      type: 'pair',
      pair: {
        secret: 's'.repeat(40),
        name: 'Mac',
        remote_version: 'cadenza-web 1',
        heartbeat: true,
      },
    });

    // Bluetooth pairing proves itself with the Host's PIN and never sends the QR secret.
    expect(
      JSON.parse(encodePair({ pin: '4821' }, 'Desk', 'cadenza-web 1')),
    ).toEqual({
      version: 1,
      type: 'pair',
      pair: {
        pin: '4821',
        name: 'Desk',
        remote_version: 'cadenza-web 1',
        heartbeat: true,
      },
    });

    const hello = JSON.parse(
      encodeHello({
        remoteId,
        token: 't'.repeat(40),
        lastCreditSequence: 3,
        name: 'Mac',
        remoteVersion: 'cadenza-web 1',
      }),
    );

    expect(hello.auth).toEqual({
      remote_id: remoteId,
      token: 't'.repeat(40),
      last_credit_sequence: 3,
      name: 'Mac',
      remote_version: 'cadenza-web 1',
      heartbeat: true,
    });
  });

  test('rename and clock frames are complete', () => {
    expect(JSON.parse(encodeRemoteConfigure(remoteId, 'Desk'))).toEqual({
      version: 1,
      type: 'remote.configure',
      request_id: remoteId,
      name: 'Desk',
      heartbeat: true,
    });
    expect(JSON.parse(encodeClock(remoteId, 12))).toEqual({
      version: 1,
      type: 'clock',
      request_id: remoteId,
      clock: { sent_at_remote_ms: 12 },
    });
  });

  test('clock probes send integer milliseconds, as the Host requires', () => {
    const frame = JSON.parse(encodeClock(remoteId, 1234.56));

    expect(frame.clock.sent_at_remote_ms).toBe(1235);
    expect(Number.isInteger(frame.clock.sent_at_remote_ms)).toBe(true);
  });
});

describe('search, preparation, and request frames', () => {
  const identity: SongIdentity = { source: 'catalog', id: '1440857781' };

  test('a search frame carries exactly the request, query, and scope keys', () => {
    expect(JSON.parse(encodeSearch(remoteId, 'Breathe', 'library'))).toEqual({
      version: 1,
      type: 'search',
      request_id: remoteId,
      query: 'Breathe',
      scope: 'library',
    });
    expect(
      Object.keys(JSON.parse(encodeSearchSuggest(remoteId, 'Bre'))),
    ).toEqual(['version', 'type', 'request_id', 'query']);
  });

  test('a preparation frame names the song by source and ID only', () => {
    expect(JSON.parse(encodeSongPrepare(remoteId, identity))).toEqual({
      version: 1,
      type: 'song.prepare',
      request_id: remoteId,
      song: { source: 'catalog', id: '1440857781' },
    });
  });

  test('a preparation frame may carry the details of the same song', () => {
    expect(
      JSON.parse(
        encodeSongPrepare(remoteId, identity, {
          title: 'Breathe Deeper',
          artist: 'Tame Impala',
          album: 'The Slow Rush',
          durationMs: null,
        }),
      ),
    ).toEqual({
      version: 1,
      type: 'song.prepare',
      request_id: remoteId,
      song: { source: 'catalog', id: '1440857781' },
      song_metadata: {
        source: 'catalog',
        id: '1440857781',
        title: 'Breathe Deeper',
        artist: 'Tame Impala',
        album: 'The Slow Rush',
        duration_ms: null,
      },
    });
  });

  test('queue requests send the song identity and nothing else', () => {
    const base = {
      commandId: remoteId,
      hostEpoch: epoch,
      expiresAtHostMs: 9000,
      expectedRevision: 18,
    };

    const enqueue = JSON.parse(
      encodeCommand({
        ...base,
        action: { kind: 'queue.enqueue', song: identity },
      }),
    );

    const playNext = JSON.parse(
      encodeCommand({
        ...base,
        action: {
          kind: 'queue.play_next',
          song: { source: 'library', id: '0123456789ABCDEF' },
        },
      }),
    );

    expect(enqueue.action).toEqual({
      kind: 'queue.enqueue',
      song: { source: 'catalog', id: '1440857781' },
    });
    expect(playNext.action).toEqual({
      kind: 'queue.play_next',
      song: { source: 'library', id: '0123456789ABCDEF' },
    });
  });

  test('a search result decodes into the song shape the Host sends', () => {
    expect(
      decodeHostMessage(
        wire({
          type: 'search.result',
          request_id: remoteId,
          songs: [song],
        }),
      ),
    ).toEqual({
      type: 'search.result',
      requestId: remoteId,
      songs: [
        {
          source: 'catalog',
          id: '1440857781',
          title: 'Breathe Deeper',
          artist: 'Tame Impala',
          album: 'The Slow Rush',
          durationMs: 372000,
          artworkUrl: 'https://example.com/art.jpg',
        },
      ],
    });
  });

  test('suggestions keep their terms, and a reply without terms is rejected', () => {
    expect(
      decodeHostMessage(
        wire({
          type: 'search.suggestions',
          request_id: remoteId,
          terms: ['Breathe', 'Breathe Deeper'],
          songs: [],
        }),
      ),
    ).toEqual({
      type: 'search.suggestions',
      requestId: remoteId,
      suggestions: { terms: ['Breathe', 'Breathe Deeper'], songs: [] },
    });
    expect(
      decodeHostMessage(
        wire({ type: 'search.suggestions', request_id: remoteId, songs: [] }),
      ),
    ).toBeNull();
  });

  test('a preparation answer is recognised by its request ID', () => {
    expect(
      decodeHostMessage(wire({ type: 'song.ready', request_id: remoteId })),
    ).toEqual({ type: 'song.ready', requestId: remoteId });
  });
});

describe('browse frames', () => {
  test('encodes a request by song identity or by ID, with no keys the Host does not accept', () => {
    expect(
      JSON.parse(
        encodeBrowseGet('r1', {
          kind: 'artist',
          song: { source: 'library', id: 'ABCDEF0123456789' },
        }),
      ),
    ).toEqual({
      version: 1,
      type: 'browse.get',
      request_id: 'r1',
      browse: {
        kind: 'artist',
        song: { source: 'library', id: 'ABCDEF0123456789' },
      },
    });
    expect(
      JSON.parse(encodeBrowseGet('r2', { kind: 'playlists' })).browse,
    ).toEqual({ kind: 'playlists' });
    expect(JSON.parse(encodeOperationCancel('r1'))).toEqual({
      version: 1,
      type: 'operation.cancel',
      request_id: 'r1',
    });
  });

  test('decodes songs and collections in sections', () => {
    const message = decodeHostMessage(
      wire({
        type: 'browse.result',
        request_id: 'r1',
        browse: {
          kind: 'artist',
          id: '1',
          title: 'Tame Impala',
          detail: 'Psychedelic',
          sections: [
            {
              id: 'top_songs',
              title: 'Top Songs',
              items: [{ type: 'song', song }],
            },
            {
              id: 'albums',
              title: 'Albums',
              items: [
                { type: 'album', id: '9', title: 'Currents', subtitle: '2015' },
              ],
            },
          ],
        },
      }),
    );

    expect(message).toMatchObject({
      type: 'browse.result',
      requestId: 'r1',
      browse: {
        kind: 'artist',
        title: 'Tame Impala',
        subtitle: null,
        detail: 'Psychedelic',
        sections: [
          {
            id: 'top_songs',
            items: [{ type: 'song', song: { title: 'Breathe Deeper' } }],
          },
          {
            items: [
              { type: 'album', id: '9', subtitle: '2015', artworkUrl: null },
            ],
          },
        ],
      },
    });
  });

  test('rejects a page with an unknown kind or a malformed item', () => {
    const page = (browse: JsonObject) =>
      decodeHostMessage(
        wire({ type: 'browse.result', request_id: 'r1', browse }),
      );

    expect(
      page({ kind: 'genre', id: '1', title: 'x', sections: [] }),
    ).toBeNull();
    expect(
      page({
        kind: 'album',
        id: '1',
        title: 'x',
        sections: [
          { id: 's', title: 's', items: [{ type: 'album', title: 'no id' }] },
        ],
      }),
    ).toBeNull();
  });
});

describe('playback mode commands', () => {
  test('encode the shuffle flag and the repeat mode', () => {
    const envelope = {
      commandId: 'c1',
      hostEpoch: epoch,
      expiresAtHostMs: 5,
      expectedRevision: 1,
    };

    expect(
      JSON.parse(
        encodeCommand({
          ...envelope,
          action: { kind: 'playback.shuffle', enabled: true },
        }),
      ).action,
    ).toEqual({ kind: 'playback.shuffle', enabled: true });
    expect(
      JSON.parse(
        encodeCommand({
          ...envelope,
          action: { kind: 'playback.repeat', mode: 'one' },
        }),
      ).action,
    ).toEqual({ kind: 'playback.repeat', mode: 'one' });
  });
});
