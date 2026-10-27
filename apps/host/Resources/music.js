// Fixed JXA entry point. Peer data is passed as arguments, never as code.

/** @template T @param {() => T} action @param {T} fallback @returns {T} */
function readValue(action, fallback) {
  try {
    return action();
  } catch {
    return fallback;
  }
}

/** @param {MusicTrack} track */
function describeTrack(track) {
  const persistent = String(
    readValue(() => track.persistentID(), ''),
  ).toUpperCase();

  const duration = Number(readValue(() => track.duration(), 0));
  const title = String(readValue(() => track.name(), ''));
  const artist = String(readValue(() => track.artist(), ''));
  const album = String(readValue(() => track.album(), ''));

  return {
    source: /^[0-9A-F]{16}$/.test(persistent) ? 'library' : 'unknown',
    id: /^[0-9A-F]{16}$/.test(persistent)
      ? persistent
      : opaqueIdentity([title, artist, album, duration]),
    title,
    artist,
    album,
    duration_ms: duration > 0 ? Math.round(duration * 1000) : null,
  };
}

/** @param {(string | number)[]} values */
function opaqueIdentity(values) {
  const text = JSON.stringify(values);
  let hash = 2166136261;

  for (let index = 0; index < text.length; index++) {
    hash = Math.imul(hash ^ text.charCodeAt(index), 16777619);
  }

  return 'native-' + (hash >>> 0).toString(16);
}

/** @param {MusicApplication} music @param {string} persistent */
function libraryTrack(music, persistent) {
  if (!/^[0-9A-F]{16}$/.test(persistent))
    throw new Error('Invalid library identity');

  const library = music.libraryPlaylists[0];

  if (!library) throw new Error('The music library is unavailable');

  const tracks = library.tracks.whose({ persistentID: persistent });
  const track = tracks[0];

  if (tracks.length !== 1 || !track)
    throw new Error('The library track is unavailable');

  return track;
}

/** @param {MusicApplication} music */
function readStatus(music) {
  const state = String(music.playerState());

  return JSON.stringify({
    playing: state === 'playing',
    state,
    volume: Number(music.soundVolume()),
    position_ms: Math.max(
      0,
      Math.round(Number(readValue(() => music.playerPosition(), 0)) * 1000),
    ),
    song: readValue(() => describeTrack(music.currentTrack()), null),
  });
}

/** @param {MusicApplication} music @param {string} query */
function searchLibrary(music, query) {
  const library = music.libraryPlaylists[0];

  if (!library) throw new Error('The music library is unavailable');

  const found = music.search(library, { for: query, only: 'songs' });
  const songs = [];

  for (let index = 0; index < Math.min(found.length, 40); index++) {
    const track = found[index];

    if (!track) continue;

    const song = describeTrack(track);

    if (song.source === 'library') songs.push(song);
  }

  return JSON.stringify(songs);
}

/** @param {MusicApplication} music @param {string[]} argv */
function controlMusic(music, argv) {
  const action = argv[0];

  if (action === 'pause') music.pause();
  else if (action === 'resume') music.play();
  else if (action === 'skip') music.nextTrack();
  else if (action === 'previous') music.previousTrack();
  else if (action === 'stop') music.stop();
  else if (action === 'seek') {
    const position = argv[1] ?? '';

    if (
      !/^[0-9]{1,16}$/.test(position) ||
      !Number.isSafeInteger(Number(position))
    ) {
      throw new Error('Invalid position');
    }

    music.playerPosition = Number(position) / 1000;
  } else if (action === 'volume') {
    const volume = Number(argv[1]);

    if (!Number.isInteger(volume) || volume < 0 || volume > 100) {
      throw new Error('Invalid volume');
    }

    music.soundVolume = volume;
  } else throw new Error('Unknown Music action');

  return JSON.stringify({ dispatched: true });
}

/** @param {string[]} argv @returns {string} */
function handleRun(argv) {
  const music = Application('Music');

  if (!music.running()) throw new Error('Open Music on this Mac first');

  const action = argv[0];

  if (action === 'status') return readStatus(music);

  if (action === 'search') return searchLibrary(music, argv[1] ?? '');

  if (action === 'resolve' || action === 'reveal') {
    const track = libraryTrack(music, argv[1] ?? '');

    if (action === 'reveal') music.reveal(track);

    return JSON.stringify(describeTrack(track));
  }

  return controlMusic(music, argv);
}

globalThis.run = handleRun;
