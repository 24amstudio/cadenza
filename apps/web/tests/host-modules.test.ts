import { describe, expect, test } from 'bun:test';
import { artworkDataUrl } from '../app/lib/host/artwork';
import { bestClockEstimate } from '../app/lib/host/clock';
import {
  createCredentialStore,
  parseStoredCredential,
  type StoredCredential,
} from '../app/lib/host/credentials';
import { readInvitationSecret } from '../app/lib/host/pairing';
import { randomUuid } from '../app/lib/host/ids';
import {
  defaultRemoteName,
  isValidRemoteName,
  socketUrlFor,
} from '../app/lib/host/endpoint';
import {
  activeLineIndex,
  activeWordIndex,
  lyricsLevel,
} from '../app/lib/lyrics';
import {
  formatClock,
  formatWait,
  positionAt,
  progressRatio,
} from '../app/lib/playback';
import type { CurrentPlayback, LyricDocument } from '../app/lib/protocol/types';

// Builds the same bytes Cadenza Host writes into its QR fragment, so the parser is checked against the real layout.
function invitationFragment(secret: string, version = 3): string {
  const host = Buffer.from('192.168.1.20', 'utf8');
  const port = Buffer.from([0x0b, 0x0b]);
  const secretBytes = Buffer.from(secret, 'utf8');

  const bytes = Buffer.concat([
    Buffer.from([0x43, 0x44, 0x5a, 0x50, version, host.length]),
    host,
    port,
    Buffer.from([secretBytes.length]),
    secretBytes,
  ]);

  const encoded = bytes.toString('base64url');

  return `#CDZP:${encoded}`;
}

const secret = 'S'.repeat(43);

describe('pairing invitation', () => {
  test('reads the one-use secret from a Host QR fragment', () => {
    expect(readInvitationSecret(invitationFragment(secret))).toBe(secret);
  });

  test('ignores fragments that are not Cadenza invitations', () => {
    expect(readInvitationSecret('')).toBeNull();
    expect(readInvitationSecret('#section-2')).toBeNull();
    expect(readInvitationSecret('#CDZP:not base64!')).toBeNull();
  });

  test('refuses the superseded invitation layout', () => {
    expect(readInvitationSecret(invitationFragment(secret, 2))).toBeNull();
  });

  test('refuses truncated invitations', () => {
    const complete = invitationFragment(secret);
    expect(
      readInvitationSecret(complete.slice(0, complete.length - 20)),
    ).toBeNull();
  });

  test('refuses invitations with bytes after the secret', () => {
    const complete = Buffer.from(
      invitationFragment(secret).slice('#CDZP:'.length),
      'base64url',
    );

    const extended = Buffer.concat([complete, Buffer.from([0x00])]);
    expect(
      readInvitationSecret(`#CDZP:${extended.toString('base64url')}`),
    ).toBeNull();
  });
});

describe('clock estimate', () => {
  test('uses the probe with the shortest round trip', () => {
    // Host clock is 1000 ms ahead of the browser.
    const slow = {
      sentAtRemoteMs: 0,
      receivedAtRemoteMs: 400,
      receivedAtHostMs: 1200,
      sentAtHostMs: 1200,
    };

    const fast = {
      sentAtRemoteMs: 500,
      receivedAtRemoteMs: 510,
      receivedAtHostMs: 1505,
      sentAtHostMs: 1505,
    };

    expect(bestClockEstimate([slow, fast])).toEqual({
      offsetMs: 1000,
      roundTripMs: 10,
    });
  });

  test('returns null when there are no usable probes', () => {
    expect(bestClockEstimate([])).toBeNull();
  });
});

describe('playback position', () => {
  const current: CurrentPlayback = {
    occurrenceId: 'occurrence',
    entryId: null,
    requesterName: 'Mia',
    song: {
      source: 'catalog',
      id: '1',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      durationMs: 200_000,
      artworkUrl: null,
    },
    positionMs: 30_000,
    sampledAtHostMs: 5_000,
  };

  test('advances while playing and holds while paused', () => {
    expect(positionAt(current, true, 7_500)).toBe(32_500);
    expect(positionAt(current, false, 7_500)).toBe(30_000);
  });

  test('never runs past the song duration or before the sample', () => {
    expect(positionAt(current, true, 1_000_000)).toBe(200_000);
    expect(positionAt(current, true, 1_000)).toBe(30_000);
  });

  test('formats clock values and waits for display', () => {
    expect(formatClock(65_900)).toBe('1:05');
    expect(formatClock(3_725_000)).toBe('1:02:05');
    expect(progressRatio(50, 200)).toBe(0.25);
    expect(progressRatio(50, null)).toBe(0);
    expect(formatWait(null)).toBe('Waiting');
    expect(formatWait(20_000)).toBe('Next');
    expect(formatWait(6 * 60_000)).toBe('In 6 min');
  });
});

describe('lyrics', () => {
  function document(lines: LyricDocument['lines']): LyricDocument {
    return {
      occurrenceId: 'occurrence',
      revision: 'rev',
      translationSource: 'none',
      source: 'apple_music',
      lines,
      issue: null,
    };
  }

  const timedLine = {
    id: 'a',
    text: 'first line',
    startMs: 1_000,
    endMs: 2_000,
    translation: null,
    words: [
      { text: 'first ', startMs: 1_000, endMs: 1_400 },
      { text: 'line', startMs: 1_400, endMs: 2_000 },
    ],
  };

  test('classifies lyrics into the four levels', () => {
    expect(lyricsLevel(null)).toBe(0);
    expect(lyricsLevel(document([]))).toBe(0);
    expect(
      lyricsLevel(
        document([{ ...timedLine, startMs: 0, endMs: 0, words: [] }]),
      ),
    ).toBe(1);
    expect(lyricsLevel(document([{ ...timedLine, words: [] }]))).toBe(2);
    expect(lyricsLevel(document([timedLine]))).toBe(3);
  });

  test('follows the last line that has started and the last word that has started', () => {
    const lines = [
      timedLine,
      { ...timedLine, id: 'b', startMs: 3_000, endMs: 4_000 },
    ];

    expect(activeLineIndex(lines, 500)).toBe(-1);
    expect(activeLineIndex(lines, 1_500)).toBe(0);
    expect(activeLineIndex(lines, 3_500)).toBe(1);
    expect(activeWordIndex(timedLine, 1_450)).toBe(1);
    expect(activeWordIndex(timedLine, 900)).toBe(-1);
  });
});

describe('credentials', () => {
  const credential: StoredCredential = {
    remoteId: '3f1c2a2e-7b6d-4c1e-9a1f-2d3e4f5a6b7c',
    token: 'T'.repeat(43),
    name: 'Mac',
    lastCreditSequence: 2,
  };

  test('accepts a stored credential and rejects malformed ones', () => {
    expect(parseStoredCredential(JSON.stringify(credential))).toEqual(
      credential,
    );
    expect(
      parseStoredCredential(
        JSON.stringify({ ...credential, remoteId: 'nope' }),
      ),
    ).toBeNull();
    expect(
      parseStoredCredential(JSON.stringify({ ...credential, token: 'short' })),
    ).toBeNull();
    expect(parseStoredCredential('{broken')).toBeNull();
  });

  test('keeps the session paired in memory when storage is unavailable', () => {
    const failing = {
      getItem: () => {
        throw new Error('denied');
      },
      setItem: () => {
        throw new Error('denied');
      },
      removeItem: () => {
        throw new Error('denied');
      },
    };

    const store = createCredentialStore(failing);

    store.write(credential);
    expect(store.read()).toEqual(credential);
    store.clear();
    expect(store.read()).toBeNull();
  });
});

describe('artwork and endpoint', () => {
  test('shows only recognised image formats', () => {
    expect(artworkDataUrl('/9j/4AAQ')).toBe('data:image/jpeg;base64,/9j/4AAQ');
    expect(artworkDataUrl('iVBORw0KGgo=')).toBe(
      'data:image/png;base64,iVBORw0KGgo=',
    );
    expect(artworkDataUrl('PHN2Zz4=')).toBeNull();
  });

  test('derives a same-origin WebSocket URL without the invitation fragment', () => {
    expect(socketUrlFor('https://192.168.1.20:43129/#CDZP:abc')).toBe(
      'wss://192.168.1.20:43129/v1/socket',
    );
    expect(socketUrlFor('http://localhost:3000/')).toBe(
      'ws://localhost:3000/v1/socket',
    );
  });

  test('validates Remote names and builds a readable default', () => {
    expect(isValidRemoteName('  Desk  ')).toBe(true);
    expect(isValidRemoteName('')).toBe(false);
    expect(isValidRemoteName('x'.repeat(81))).toBe(false);
    expect(isValidRemoteName('bad\nname')).toBe(false);
    expect(
      defaultRemoteName('Mozilla/5.0 (Macintosh; Intel Mac OS X 15_0)'),
    ).toBe('Web browser on Mac');
    expect(defaultRemoteName('Mozilla/5.0 (iPhone; CPU iPhone OS 18_0)')).toBe(
      'Web browser on iPhone',
    );
  });
});

describe('identifiers', () => {
  test('creates lowercase version 4 UUIDs without relying on a secure context', () => {
    const uuid = randomUuid();

    expect(uuid).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
    );
    expect(randomUuid()).not.toBe(uuid);
  });
});
