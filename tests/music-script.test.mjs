import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(
  new URL('../apps/host/Resources/music.js', import.meta.url),
  'utf8',
);

/** @param {string} [persistentId] @param {{ trackClass?: string, inLibrary?: boolean, lateApply?: number, duration?: number | null, artist?: string, mediaKind?: string }} [options] */
function nativeBoundary(
  persistentId = 'AB1234567890CDEF',
  {
    trackClass = 'sharedTrack',
    inLibrary = true,
    lateApply = 0,
    // null is the value Music returns as "missing value", as a radio station reports it.
    duration = 183.125,
    artist = 'Example artist',
    mediaKind = '',
  } = {},
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

  let favorited = false;
  /** @type {{ playlist: string, id: string }[]} */
  const duplicates = [];
  /** @type {MusicPlaylist[]} */
  const createdPlaylists = [];

  const track = {
    persistentID: () => persistentId,
    class: () => trackClass,
    duration: () => duration,
    name: () => 'A "quoted"\nsong ||| title',
    artist: () => artist,
    album: () => 'Example album',
    kind: () => 'Apple Music AAC audio file',
    mediaKind: () => mediaKind,
    location: () => '/Users/example/Music/clip.mp4',
    play: () => {
      playing = true;
    },
    /** @returns {() => boolean} */
    get favorited() {
      return () => favorited;
    },
    set favorited(/** @type {boolean} */ value) {
      favorited = value;
    },
    duplicate: (/** @type {{ to: MusicPlaylist }} */ spec) => {
      duplicates.push({ playlist: spec.to.name(), id: persistentId });
    },
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
    mediaKind: () => [mediaKind],
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
    whose: (/** @type {{ persistentID?: string, name?: string }} */ value) => {
      if (value.name === undefined) {
        return value.persistentID === playlistId ? [roadTrip] : [];
      }

      return createdPlaylists.filter(
        (playlist) => playlist.name() === value.name,
      );
    },
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
    make: (/** @type {{ withProperties: { name: string } }} */ spec) => {
      const playlist = {
        name: () => spec.withProperties.name,
        tracks: playlistTracks,
      };

      createdPlaylists.push(playlist);

      return playlist;
    },
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

  return {
    invoke,
    query: () => query,
    favorited: () => favorited,
    duplicates: () => duplicates,
    playlists: () => createdPlaylists.map((playlist) => playlist.name()),
  };
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

test('a music video is labelled as a video and a song is labelled as a song', () => {
  const video = nativeBoundary('AB1234567890CDEF', {
    mediaKind: 'music video',
  }).invoke(['search', 'akad']);

  const song = nativeBoundary().invoke(['search', 'akad']);

  assert.equal(video[0].media_type, 'musicVideo');
  assert.equal(song[0].media_type, 'song');
});

test('a music video that Music plays as a URL track with a length is not live radio', () => {
  // Music reported this shape for a live catalog video: class "urlTrack", a finite duration, media kind "music video".
  const status = nativeBoundary('2AA0E2DB2E7FD4EC', {
    trackClass: 'urlTrack',
    inLibrary: false,
    duration: 180.2,
    mediaKind: 'music video',
  }).invoke(['status']);

  assert.equal(status.song.is_live_radio, false);
  assert.equal(status.song.media_type, 'musicVideo');
  assert.equal(status.song.duration_ms, 180200);
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

test('a bare radio stream is live with no length, and a station keeps the metadata it reports', () => {
  const bare = nativeBoundary('958A4478EDBDEEF8', {
    trackClass: 'urlTrack',
    inLibrary: false,
    duration: null,
    artist: '',
  }).invoke(['status']);

  assert.equal(bare.song.is_live_radio, true);
  assert.equal(bare.song.duration_ms, null);
  assert.equal(bare.song.artist, '');
  assert.equal(bare.position_ms, 1250);

  const station = nativeBoundary('958A4478EDBDEEF8', {
    trackClass: 'urlTrack',
    inLibrary: false,
    duration: null,
  }).invoke(['status']);

  assert.equal(station.song.is_live_radio, true);
  assert.equal(station.song.title, 'A "quoted"\nsong ||| title');
  assert.equal(station.song.artist, 'Example artist');
});

test('a track whose length is not a finite number is live, and a song with a length is not', () => {
  const nonFinite = nativeBoundary('958A4478EDBDEEF8', {
    trackClass: 'sharedTrack',
    duration: Number.NaN,
  }).invoke(['status']);

  assert.equal(nonFinite.song.is_live_radio, true);
  assert.equal(nonFinite.song.duration_ms, null);

  const song = nativeBoundary().invoke(['status']);

  assert.equal(song.song.is_live_radio, false);
  assert.equal(song.song.duration_ms, 183125);
});

test('a favorite is set on the library track only from a boolean value', () => {
  const boundary = nativeBoundary();

  boundary.invoke(['favorite', 'AB1234567890CDEF', 'true']);
  assert.equal(boundary.favorited(), true);
  assert.throws(
    () => boundary.invoke(['favorite', 'AB1234567890CDEF', 'yes']),
    /Invalid favorite setting/,
  );
  assert.throws(
    () => boundary.invoke(['favorite', 'not-an-identity', 'true']),
    /Invalid library identity/,
  );
});

test('Host tracks join one playlist that is created the first time and reused after', () => {
  const boundary = nativeBoundary();

  assert.equal(
    boundary.invoke(['playlist-add', 'Cadenza Host', 'AB1234567890CDEF']).added,
    1,
  );
  assert.equal(
    boundary.invoke(['playlist-add', 'Cadenza Host', 'AB1234567890CDEF']).added,
    1,
  );
  assert.deepEqual(boundary.playlists(), ['Cadenza Host']);
  assert.deepEqual(boundary.duplicates(), [
    { playlist: 'Cadenza Host', id: 'AB1234567890CDEF' },
    { playlist: 'Cadenza Host', id: 'AB1234567890CDEF' },
  ]);
});

test('a playlist write with no tracks, a bad name, or a bad identity changes nothing in Music', () => {
  const boundary = nativeBoundary();

  assert.throws(
    () => boundary.invoke(['playlist-add', 'Cadenza Host']),
    /Invalid track count/,
  );
  assert.throws(
    () => boundary.invoke(['playlist-add', '', 'AB1234567890CDEF']),
    /Invalid library name/,
  );
  assert.throws(
    () => boundary.invoke(['playlist-add', 'Cadenza Host', 'not-an-identity']),
    /Invalid library identity/,
  );
  assert.deepEqual(boundary.playlists(), []);
  assert.deepEqual(boundary.duplicates(), []);
});

test('library music videos report media_type in track sets, start with play-video, and expose local path only for file tracks', () => {
  const fileVideo = nativeBoundary('AB1234567890CDEF', {
    trackClass: 'fileTrack',
    mediaKind: 'music video',
  });

  const streamVideo = nativeBoundary('AB1234567890CDEF', {
    trackClass: 'urlTrack',
    mediaKind: 'music video',
  });

  const playlist = fileVideo.invoke(['playlist', '0123456789ABCDEF']);

  assert.equal(playlist.songs[0].media_type, 'musicVideo');
  assert.equal(
    fileVideo.invoke(['play-video', 'AB1234567890CDEF']).media_type,
    'musicVideo',
  );
  assert.equal(
    fileVideo.invoke(['video-path', 'AB1234567890CDEF']).path,
    '/Users/example/Music/clip.mp4',
  );
  assert.equal(streamVideo.invoke(['video-path', 'AB1234567890CDEF']).path, '');
});
