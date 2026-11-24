import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(
  new URL('../apps/host/Resources/music.js', import.meta.url),
  'utf8',
);

/** @param {string} [persistentId] @param {{ trackClass?: string, inLibrary?: boolean, lateApply?: number }} [options] */
function nativeBoundary(
  persistentId = 'AB1234567890CDEF',
  { trackClass = 'sharedTrack', inLibrary = true, lateApply = 0 } = {},
) {
  let volume = 50;
  let position = 1.25;
  let playing = true;
  // Music applies play and pause some reads after its script returns, as it does on a busy Mac.
  /** @type {boolean | null} */
  let pendingPlaying = null;
  let readsUntilApplied = 0;

  const applyLatePlaybackChange = (/** @type {boolean} */ next) => {
    if (lateApply > 0) {
      pendingPlaying = next;
      readsUntilApplied = lateApply;
    } else {
      playing = next;
    }
  };

  let shuffle = false;
  let repeat = 'off';
  let query = '';

  const track = {
    persistentID: () => persistentId,
    class: () => trackClass,
    duration: () => 183.125,
    name: () => 'A "quoted"\nsong ||| title',
    artist: () => 'Example artist',
    album: () => 'Example album',
    kind: () => 'Apple Music AAC audio file',
  };

  const playlistId = '0123456789ABCDEF';

  const playlistTracks = {
    length: 1,
    persistentID: () => [persistentId],
    class: () => [trackClass],
    name: () => [track.name()],
    artist: () => [track.artist()],
    album: () => [track.album()],
    kind: () => [track.kind()],
    duration: () => [track.duration()],
    discNumber: () => [1],
    trackNumber: () => [1],
    whose: (/** @type {{ persistentID: string }} */ value) =>
      value.persistentID === persistentId ? [track] : [],
  };

  const roadTrip = { name: () => 'Road trip', tracks: playlistTracks };

  // The built-in "Music" list mirrors the library and must never be offered as a playlist.
  const userPlaylists = Object.assign([roadTrip, roadTrip], {
    name: () => ['Road trip', 'Music'],
    persistentID: () => [playlistId, 'FEDCBA9876543210'],
    class: () => ['userPlaylist', 'userPlaylist'],
    specialKind: () => ['none', 'Music'],
    whose: (/** @type {{ persistentID: string }} */ value) =>
      value.persistentID === playlistId ? [roadTrip] : [],
  });

  /** @type {MusicApplication} */
  const music = {
    running: () => true,
    launch: () => {},
    playerState: () => {
      if (pendingPlaying !== null && --readsUntilApplied <= 0) {
        playing = pendingPlaying;
        pendingPlaying = null;
      }

      return playing ? 'playing' : 'paused';
    },
    currentTrack: () => track,
    libraryPlaylists: [
      {
        tracks: Object.assign(inLibrary ? [track] : [], {
          whose: (/** @type {{ persistentID: string }} */ value) =>
            inLibrary && value.persistentID === track.persistentID()
              ? [track]
              : [],
        }),
      },
    ],
    userPlaylists,
    search: (_library, value) => {
      // Music's scripting dictionary defines these search fields; any other value fails to convert.
      const searchFields = [
        'albums',
        'all',
        'artists',
        'composers',
        'displayed',
        'names',
      ];

      if (!searchFields.includes(value.only))
        throw new Error("Can't convert types.");
      query = value.for;

      return [track];
    },
    reveal: () => {},
    play: () => {
      applyLatePlaybackChange(true);
    },
    pause: () => {
      applyLatePlaybackChange(false);
    },
    nextTrack: () => {
      position = 0;
    },
    previousTrack: () => {
      position = 0;
    },
    stop: () => {
      playing = false;
    },
    /** @returns {() => number} */
    get soundVolume() {
      return () => volume;
    },
    set soundVolume(/** @type {number} */ value) {
      volume = value;
    },
    /** @returns {() => number} */
    get playerPosition() {
      return () => position;
    },
    set playerPosition(/** @type {number} */ value) {
      position = value;
    },
    /** @returns {() => boolean} */
    get shuffleEnabled() {
      return () => shuffle;
    },
    set shuffleEnabled(/** @type {boolean} */ value) {
      shuffle = value;
    },
    /** @returns {() => string} */
    get songRepeat() {
      return () => repeat;
    },
    set songRepeat(/** @type {string} */ value) {
      repeat = value;
    },
  };

  // Application is the explicit external macOS automation boundary.
  const context = {
    Application: () => music,
    argumentsForTest: [],
    delay: () => {},
  };

  runInNewContext(source, context);

  /** @param {string[]} arguments_ */
  function invoke(arguments_) {
    Object.assign(context, { argumentsForTest: arguments_ });

    return JSON.parse(runInNewContext('run(argumentsForTest)', context));
  }

  return { invoke, query: () => query };
}

test('the owned Music script preserves punctuation and converts native seconds to whole milliseconds', () => {
  const boundary = nativeBoundary();
  const status = boundary.invoke(['status']);

  assert.equal(status.song.title, 'A "quoted"\nsong ||| title');
  assert.equal(status.song.duration_ms, 183125);
  assert.equal(status.position_ms, 1250);
  assert.equal(status.playing, true);
  boundary.invoke(['pause']);
  assert.equal(boundary.invoke(['status']).playing, false);
  boundary.invoke(['resume']);
  assert.equal(boundary.invoke(['status']).playing, true);
});

test('Music search passes a query as data and rejects injected identities or unknown actions', () => {
  const boundary = nativeBoundary();
  const query = '"; do shell script "anything';
  const results = boundary.invoke(['search', query]);

  assert.equal(boundary.query(), query);
  assert.equal(results[0].id, 'AB1234567890CDEF');
  assert.throws(
    () => boundary.invoke(['reveal', query]),
    /Invalid library identity/,
  );
  assert.throws(
    () => boundary.invoke(['execute', query]),
    /Unknown Music action/,
  );
});

test('invalid volume and seek input cannot mutate Music through the script boundary', () => {
  const boundary = nativeBoundary();

  boundary.invoke(['volume', '73']);
  assert.equal(boundary.invoke(['status']).volume, 73);
  assert.throws(() => boundary.invoke(['volume', '101']), /Invalid volume/);
  assert.equal(boundary.invoke(['status']).volume, 73);
  assert.throws(
    () => boundary.invoke(['seek', '12; anything']),
    /Invalid position/,
  );
  assert.throws(
    () => boundary.invoke(['seek', '9007199254740992']),
    /Invalid position/,
  );
  assert.equal(boundary.invoke(['status']).position_ms, 1250);
  boundary.invoke(['seek', '90250']);
  assert.equal(boundary.invoke(['status']).position_ms, 90250);
});

test('a stream without a library identity remains displayable without becoming a catalog or library request', () => {
  const boundary = nativeBoundary('');
  const song = boundary.invoke(['status']).song;

  assert.equal(song.source, 'unknown');
  assert.match(song.id, /^native-[0-9a-f]+$/);
  assert.equal(boundary.invoke(['status']).song.id, song.id);
});

test('a streamed catalog song that the library does not hold is not labelled as a library track', () => {
  const streamed = nativeBoundary('958A4478EDBDEEF8', {
    trackClass: 'urlTrack',
    inLibrary: false,
  });

  const song = streamed.invoke(['status']).song;

  assert.equal(song.source, 'unknown');
  assert.match(song.id, /^native-[0-9a-f]+$/);

  const kept = nativeBoundary('958A4478EDBDEEF8', { trackClass: 'urlTrack' });

  assert.equal(kept.invoke(['status']).song.source, 'library');
  assert.equal(kept.invoke(['status']).song.id, '958A4478EDBDEEF8');
});

test('playlists list only user playlists, and their songs resolve even when the library lacks them', () => {
  const boundary = nativeBoundary('AB1234567890CDEF', { inLibrary: false });

  assert.deepEqual(boundary.invoke(['playlists']), [
    { id: '0123456789ABCDEF', name: 'Road trip', count: 1 },
  ]);

  const playlist = boundary.invoke(['playlist', '0123456789ABCDEF']);

  assert.equal(playlist.total, 1);
  assert.equal(playlist.songs[0].id, 'AB1234567890CDEF');
  assert.equal(playlist.songs[0].duration_ms, 183125);
  assert.equal(
    boundary.invoke(['resolve', 'AB1234567890CDEF']).title,
    'A "quoted"\nsong ||| title',
  );
  assert.throws(
    () => boundary.invoke(['playlist', '"; do shell script "x']),
    /Invalid playlist identity/,
  );
  assert.throws(
    () => boundary.invoke(['playlist', 'FFFFFFFFFFFFFFFF']),
    /The playlist is unavailable/,
  );
});

test('shuffle and repeat are read in the status and set only to known values', () => {
  const boundary = nativeBoundary();

  assert.equal(boundary.invoke(['status']).shuffle, false);
  assert.equal(boundary.invoke(['status']).repeat, 'off');

  boundary.invoke(['shuffle', 'true']);
  boundary.invoke(['repeat', 'one']);
  assert.equal(boundary.invoke(['status']).shuffle, true);
  assert.equal(boundary.invoke(['status']).repeat, 'one');
  boundary.invoke(['repeat', 'all']);
  assert.equal(boundary.invoke(['status']).repeat, 'all');
  boundary.invoke(['shuffle', 'false']);
  boundary.invoke(['repeat', 'off']);
  assert.equal(boundary.invoke(['status']).shuffle, false);
  assert.equal(boundary.invoke(['status']).repeat, 'off');

  assert.throws(
    () => boundary.invoke(['shuffle', 'yes']),
    /Invalid shuffle setting/,
  );
  assert.throws(
    () => boundary.invoke(['repeat', 'sometimes']),
    /Invalid repeat mode/,
  );
  assert.equal(boundary.invoke(['status']).repeat, 'off');
});

test('a control action waits inside its own script until Music shows the new state', () => {
  const boundary = nativeBoundary('AB1234567890CDEF', { lateApply: 2 });
  const paused = boundary.invoke(['pause']);

  assert.equal(paused.status.playing, false);
  assert.equal(paused.status.state, 'paused');
});

test('a control action replies with the state it left, so the Host can confirm it without another launch', () => {
  const boundary = nativeBoundary();
  const paused = boundary.invoke(['pause']);

  assert.equal(paused.dispatched, true);
  assert.equal(paused.status.playing, false);
  assert.equal(paused.status.state, 'paused');
  assert.equal(boundary.invoke(['volume', '20']).status.volume, 20);
  assert.equal(boundary.invoke(['shuffle', 'true']).status.shuffle, true);
});
