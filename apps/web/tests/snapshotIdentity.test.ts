import { expect, test } from 'bun:test';
import { reuseUnchanged } from '../app/lib/snapshotIdentity';
import type { Snapshot, Song } from '../app/lib/protocol/types';

const song: Song = {
  source: 'catalog',
  id: '1',
  title: 'Borderline',
  artist: 'Tame Impala',
  album: 'The Slow Rush',
  durationMs: 1000,
  artworkUrl: null,
};

function snapshot(positionMs: number, queueWait: number | null): Snapshot {
  return {
    hostId: 'h',
    hostEpoch: 'e',
    revision: 1,
    sequence: 1,
    playing: true,
    volume: 50,
    shuffle: false,
    repeat: 'off',
    current: {
      occurrenceId: 'o',
      entryId: null,
      requesterName: 'Mia',
      song: { ...song },
      positionMs,
      sampledAtHostMs: 0,
    },
    queue: [
      {
        id: 'q',
        requesterName: 'Alex',
        song: { ...song },
        estimatedWaitMs: queueWait,
      },
    ],
    totalRemainingMs: null,
    quality: 'unknown',
    autoPlay: [],
    synchronized: true,
    issue: null,
    audioOutputs: [],
    hostBudget: null,
    cast: null,
  };
}

test('a state frame that moves only the position keeps the same song and queue objects', () => {
  const previous = snapshot(0, 5);
  const next = snapshot(250, 5);
  const merged = reuseUnchanged(previous, next);

  expect(merged.current?.positionMs).toBe(250);
  expect(merged.current?.song).toBe(previous.current?.song);
  expect(merged.queue).toBe(previous.queue);
});

test('a changed queue or song is taken as the new one', () => {
  const previous = snapshot(0, 5);
  const next = snapshot(0, 9);
  const changedSong = snapshot(0, 5);

  if (changedSong.current !== null) {
    changedSong.current.song = { ...song, title: 'Breathe Deeper' };
  }

  expect(reuseUnchanged(previous, next).queue).toBe(next.queue);
  expect(reuseUnchanged(previous, changedSong).current?.song.title).toBe(
    'Breathe Deeper',
  );
  expect(reuseUnchanged(null, next)).toBe(next);
});
