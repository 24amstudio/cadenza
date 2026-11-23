// Fixed JXA entry point. Peer data is passed as arguments, never as code.

/** @template T @param {() => T} action @param {T} fallback @returns {T} */
function readValue(action, fallback) {
  try {
    return action();
  } catch {
    return fallback;
  }
}

/**
 * A streamed catalog song reports a persistent ID too, but only as a urlTrack that the library does not hold, so
 * resolving it in the library fails. Library tracks are file or shared tracks, or a urlTrack the library lists.
 * @param {MusicTrack} track @param {MusicApplication | undefined} music @param {string} persistent
 */
function inLibrary(track, music, persistent) {
  if (!/^[0-9A-F]{16}$/.test(persistent)) return false;

  if (String(readValue(() => track.class(), '')) !== 'urlTrack') return true;

  const library = music?.libraryPlaylists[0];

  return Boolean(
    library &&
    readValue(
      () => library.tracks.whose({ persistentID: persistent }).length === 1,
      false,
    ),
  );
}

/** @param {MusicTrack} track @param {MusicApplication} [music] */
function describeTrack(track, music) {
  const persistent = String(
    readValue(() => track.persistentID(), ''),
  ).toUpperCase();

  const library = inLibrary(track, music, persistent);
  const duration = Number(readValue(() => track.duration(), 0));
  const title = String(readValue(() => track.name(), ''));
  const artist = String(readValue(() => track.artist(), ''));
  const album = String(readValue(() => track.album(), ''));

  return {
    source: library ? 'library' : 'unknown',
    id: library ? persistent : opaqueIdentity([title, artist, album, duration]),
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

  if (tracks.length === 1 && track) return track;

  // Apple Music songs in a playlist are not always in the library itself, but Music can still reveal them there.
  const playlists = music.userPlaylists;
  const ids = readValue(() => playlists.persistentID(), []);

  for (let index = 0; index < Math.min(ids.length, 200); index++) {
    const found = readValue(
      () => playlists[index]?.tracks.whose({ persistentID: persistent }),
      [],
    );

    if (found?.length === 1 && found[0]) return found[0];
  }

  throw new Error('The library track is unavailable');
}

/** @param {MusicApplication} music */
function describeStatus(music) {
  const state = String(music.playerState());

  return {
    playing: state === 'playing',
    state,
    volume: Number(music.soundVolume()),
    position_ms: Math.max(
      0,
      Math.round(Number(readValue(() => music.playerPosition(), 0)) * 1000),
    ),
    // Read straight after the position, so the Host can date the position to this moment rather than to process exit.
    read_at_ms: Date.now(),
    shuffle: readValue(() => Boolean(music.shuffleEnabled()), false),
    repeat: readRepeat(music),
    song: readValue(() => describeTrack(music.currentTrack(), music), null),
    // The file kind of the current track, such as "Apple Music AAC audio file". It names the codec when Music shows no tier badge.
    file_kind: readValue(() => String(music.currentTrack().kind()), null),
  };
}

/** @param {MusicApplication} music */
function readStatus(music) {
  return JSON.stringify(describeStatus(music));
}

/** @param {MusicApplication} music */
function readRepeat(music) {
  const mode = String(readValue(() => music.songRepeat(), 'off'));

  return mode === 'one' || mode === 'all' ? mode : 'off';
}

/** @param {MusicApplication} music @param {string} query */
function searchLibrary(music, query) {
  const library = music.libraryPlaylists[0];

  if (!library) throw new Error('The music library is unavailable');

  // Music's search fields have no "songs" value. "all" returns tracks, and the loop below keeps library songs only.
  const found = music.search(library, { for: query, only: 'all' });
  const songs = [];

  for (let index = 0; index < Math.min(found.length, 40); index++) {
    const track = found[index];

    if (!track) continue;

    const song = describeTrack(track, music);

    if (song.source === 'library') songs.push(song);
  }

  return JSON.stringify(songs);
}

/** @param {string} value @param {number} limit */
function requireText(value, limit) {
  if (value.length === 0 || value.length > limit)
    throw new Error('Invalid library name');

  return value;
}

/**
 * Describes a whole track set with one Apple event per property.
 * @param {MusicTrackSet} tracks @param {number} limit
 */
function describeTrackSet(tracks, limit) {
  const ids = readValue(() => tracks.persistentID(), []);
  const names = readValue(() => tracks.name(), []);
  const artists = readValue(() => tracks.artist(), []);
  const albums = readValue(() => tracks.album(), []);
  const durations = readValue(() => tracks.duration(), []);
  const discs = readValue(() => tracks.discNumber(), []);
  const numbers = readValue(() => tracks.trackNumber(), []);
  const rows = [];

  for (let index = 0; index < ids.length; index++) {
    const id = String(ids[index]).toUpperCase();

    if (!/^[0-9A-F]{16}$/.test(id) || !names[index]) continue;

    rows.push({
      disc: Number(discs[index] ?? 0),
      track: Number(numbers[index] ?? 0),
      index,
      id,
    });
  }

  rows.sort(
    (left, right) =>
      left.disc - right.disc ||
      left.track - right.track ||
      left.index - right.index,
  );

  const songs = [];

  for (const { index, id } of rows.slice(0, limit)) {
    const duration = Number(durations[index] ?? 0);

    songs.push({
      source: 'library',
      id,
      title: String(names[index]),
      artist: String(artists[index] ?? ''),
      album: String(albums[index] ?? ''),
      duration_ms: duration > 0 ? Math.round(duration * 1000) : null,
    });
  }

  return songs;
}

/** @param {MusicApplication} music */
function listPlaylists(music) {
  const playlists = music.userPlaylists;
  const names = readValue(() => playlists.name(), []);
  const ids = readValue(() => playlists.persistentID(), []);
  const classes = readValue(() => playlists.class(), []);
  const kinds = readValue(() => playlists.specialKind(), []);
  const found = [];

  for (let index = 0; index < ids.length && found.length < 200; index++) {
    // The library itself, Podcasts and other built-in lists have a special kind. Folders hold other playlists.
    if (kinds[index] !== 'none' || classes[index] !== 'userPlaylist') continue;

    const playlist = playlists[index];

    found.push({
      id: String(ids[index]).toUpperCase(),
      name: String(names[index] ?? ''),
      count: playlist ? Number(readValue(() => playlist.tracks.length, 0)) : 0,
    });
  }

  return JSON.stringify(found);
}

/** @param {MusicApplication} music @param {string} persistent */
function readPlaylist(music, persistent) {
  if (!/^[0-9A-F]{16}$/.test(persistent))
    throw new Error('Invalid playlist identity');

  const matches = music.userPlaylists.whose({ persistentID: persistent });
  const playlist = matches[0];

  if (matches.length !== 1 || !playlist)
    throw new Error('The playlist is unavailable');

  return JSON.stringify({
    name: String(playlist.name()),
    total: Number(readValue(() => playlist.tracks.length, 0)),
    songs: describeTrackSet(playlist.tracks, 100),
  });
}

/** @param {MusicApplication} music */
function libraryTrackQuery(music) {
  const library = music.libraryPlaylists[0];

  if (!library) throw new Error('The music library is unavailable');

  // The same collection as libraryTrack uses, filtered by name instead of identity.
  return /** @type {MusicTrackQuery} */ (
    /** @type {unknown} */ (library.tracks)
  );
}

/** @param {MusicApplication} music @param {string} album @param {string} artist */
function readAlbumTracks(music, album, artist) {
  const songs = describeTrackSet(
    libraryTrackQuery(music).whose({ album: requireText(album, 500) }),
    1000,
  );

  const wanted = artist.toLowerCase();
  const byArtist = songs.filter((song) => song.artist.toLowerCase() === wanted);

  // A compilation has many artists, so the album's other tracks are kept when none of them is the song's artist.
  return JSON.stringify((byArtist.length > 0 ? byArtist : songs).slice(0, 100));
}

/** @param {MusicApplication} music @param {string} artist */
function readArtistTracks(music, artist) {
  return JSON.stringify(
    describeTrackSet(
      libraryTrackQuery(music).whose({ artist: requireText(artist, 500) }),
      100,
    ),
  );
}

/** @param {MusicApplication} music @param {string} position */
function seekMusic(music, position) {
  if (
    !/^[0-9]{1,16}$/.test(position) ||
    !Number.isSafeInteger(Number(position))
  ) {
    throw new Error('Invalid position');
  }

  music.playerPosition = Number(position) / 1000;
}

/** @param {MusicApplication} music @param {string | undefined} value */
function setVolume(music, value) {
  const volume = Number(value);

  if (!Number.isInteger(volume) || volume < 0 || volume > 100) {
    throw new Error('Invalid volume');
  }

  music.soundVolume = volume;
}

/** @param {MusicApplication} music @param {string | undefined} value */
function setShuffle(music, value) {
  if (value !== 'true' && value !== 'false')
    throw new Error('Invalid shuffle setting');

  music.shuffleEnabled = value === 'true';
}

/** @param {MusicApplication} music @param {string | undefined} value */
function setRepeat(music, value) {
  if (value !== 'off' && value !== 'one' && value !== 'all')
    throw new Error('Invalid repeat mode');

  music.songRepeat = value;
}

/** @param {MusicApplication} music @param {string[]} argv */
// About 800 ms of settling at most, which covers Music's usual delay between a script returning and its state changing.
const SETTLE_POLLS = 16;
const SETTLE_INTERVAL_SECONDS = 0.05;

function controlMusic(music, argv) {
  const action = argv[0];

  if (action === 'pause') music.pause();
  else if (action === 'resume') music.play();
  else if (action === 'skip') music.nextTrack();
  else if (action === 'previous') music.previousTrack();
  else if (action === 'stop') music.stop();
  else if (action === 'seek') seekMusic(music, argv[1] ?? '');
  else if (action === 'volume') setVolume(music, argv[1]);
  else if (action === 'shuffle') setShuffle(music, argv[1]);
  else if (action === 'repeat') setRepeat(music, argv[1]);
  else throw new Error('Unknown Music action');

  // Music applies play and pause a moment after the script returns. Settling here keeps the Host from launching a second
  // script to confirm the action. A state that never settles is still returned, and the Host confirms it from there.
  const expectedPlaying = action === 'pause' ? false : action === 'resume' ? true : null;
  const status =
    expectedPlaying === null
      ? readValue(() => describeStatus(music), null)
      : settlePlayback(music, expectedPlaying);
  return JSON.stringify({ dispatched: true, status });
}

/** @param {MusicApplication} music @param {boolean} expectedPlaying */
function settlePlayback(music, expectedPlaying) {
  let status = readValue(() => describeStatus(music), null);
  for (let poll = 0; poll < SETTLE_POLLS && status && status.playing !== expectedPlaying; poll += 1) {
    delay(SETTLE_INTERVAL_SECONDS);
    status = readValue(() => describeStatus(music), null);
  }
  return status;
}

/** @param {string[]} argv @returns {string} */
function handleRun(argv) {
  const music = Application('Music');

  if (!music.running()) {
    music.launch();
    delay(1);
  }

  const action = argv[0];

  if (action === 'status') return readStatus(music);

  if (action === 'search') return searchLibrary(music, argv[1] ?? '');

  if (action === 'playlists') return listPlaylists(music);

  if (action === 'playlist') return readPlaylist(music, argv[1] ?? '');

  if (action === 'album-tracks')
    return readAlbumTracks(music, argv[1] ?? '', argv[2] ?? '');

  if (action === 'artist-tracks') return readArtistTracks(music, argv[1] ?? '');

  if (action === 'resolve' || action === 'reveal') {
    const track = libraryTrack(music, argv[1] ?? '');

    if (action === 'reveal') music.reveal(track);

    return JSON.stringify(describeTrack(track, music));
  }

  return controlMusic(music, argv);
}

globalThis.run = handleRun;
