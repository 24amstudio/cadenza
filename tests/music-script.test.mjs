import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { runInNewContext } from 'node:vm';

const source = readFileSync(
  new URL('../apps/host/Resources/music.js', import.meta.url),
  'utf8',
);

/** @param {string} [persistentId] */
function nativeBoundary(persistentId = 'AB1234567890CDEF') {
  let volume = 50;
  let position = 1.25;
  let playing = true;
  let query = '';

  const track = {
    persistentID: () => persistentId,
    duration: () => 183.125,
    name: () => 'A "quoted"\nsong ||| title',
    artist: () => 'Example artist',
    album: () => 'Example album',
  };

  /** @type {MusicApplication} */
  const music = {
    running: () => true,
    playerState: () => (playing ? 'playing' : 'paused'),
    currentTrack: () => track,
    libraryPlaylists: [
      {
        tracks: Object.assign([track], {
          whose: (/** @type {{ persistentID: string }} */ value) =>
            value.persistentID === track.persistentID() ? [track] : [],
        }),
      },
    ],
    search: (_library, value) => {
      query = value.for;

      return [track];
    },
    reveal: () => {},
    play: () => {
      playing = true;
    },
    pause: () => {
      playing = false;
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
  };

  // Application is the explicit external macOS automation boundary.
  const context = { Application: () => music, argumentsForTest: [] };

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
