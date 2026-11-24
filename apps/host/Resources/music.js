// Fixed JXA entry point. Peer data is passed as arguments, never as code.

/** @template T @param {() => T} action @param {T} fallback @returns {T} */
function readValue(action, fallback) {
  try {
    return action();
  } catch {
    return fallback;
  }
}

/** Music answers error -1728 for a property a track does not have, so every track read goes through these guards. @param {() => unknown} action @returns {string} */
function safeString(action) {
  const value = readValue(action, null);

  return value === null || value === undefined ? '' : String(value);
}

/** @param {() => unknown} action @returns {number | null} */
function safeFiniteNumber(action) {
  const value = readValue(action, null);
  const number = value === null || value === undefined ? NaN : Number(value);

  return Number.isFinite(number) ? number : null;
}

/** @template T @param {() => T[]} action @returns {T[]} */
function safeArray(action) {
  const value = readValue(action, []);

  return Array.isArray(value) ? value : [];
}

/**
 * JXA reports a radio stream as a urlTrack. The AppleScript name "URL track" is accepted too, so either spelling
 * classifies the same way.
 * @param {string} trackClass
 */
function isStreamClass(trackClass) {
  return trackClass === 'urlTrack' || trackClass === 'URL track';
}

/**
 * A streamed catalog song reports a persistent ID too, but only as a urlTrack that the library does not hold, so
 * resolving it in the library fails. Library tracks are file or shared tracks, or a urlTrack the library lists.
 * @param {string} trackClass @param {MusicApplication | undefined} music @param {string} persistent
 */
function inLibrary(trackClass, music, persistent) {
  if (!/^[0-9A-F]{16}$/.test(persistent)) return false;

  if (!isStreamClass(trackClass)) return true;

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
  const persistent = safeString(() => track.persistentID()).toUpperCase();
  const trackClass = safeString(() => track.class());
  const library = inLibrary(trackClass, music, persistent);
  const duration = safeFiniteNumber(() => track.duration());
  const seconds = duration !== null && duration > 0 ? duration : null;
  const title = safeString(() => track.name());
  const artist = safeString(() => track.artist());
  const album = safeString(() => track.album());

  return {
    source: library ? 'library' : 'unknown',
    id: library
      ? persistent
      : opaqueIdentity([title, artist, album, seconds ?? 0]),
    title,
    artist,
    album,
    duration_ms: seconds === null ? null : Math.round(seconds * 1000),
    // A stream, or a track with no finite positive length, is live radio. The Host skips timing that needs a length.
    is_live_radio: isStreamClass(trackClass) || seconds === null,
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
      Math.round((safeFiniteNumber(() => music.playerPosition()) ?? 0) * 1000),
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
  const ids = safeArray(() => tracks.persistentID());
  const names = safeArray(() => tracks.name());
  const artists = safeArray(() => tracks.artist());
  const albums = safeArray(() => tracks.album());
  const durations = safeArray(() => tracks.duration());
  const discs = safeArray(() => tracks.discNumber());
  const numbers = safeArray(() => tracks.trackNumber());
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

// Library write-back changes only what the user named: one favorite flag, or tracks added to one playlist.
const PLAYLIST_TRACK_LIMIT = 200;

/** @param {MusicApplication} music @param {string} persistent @param {string | undefined} value */
function setFavorite(music, persistent, value) {
  if (value !== 'true' && value !== 'false')
    throw new Error('Invalid favorite setting');

  libraryTrack(music, persistent).favorited = value === 'true';
}

/** The user's playlist with this name, created the first time it is needed. @param {MusicApplication} music @param {string} name */
function hostPlaylist(music, name) {
  const title = requireText(name, 100);
  const existing = music.userPlaylists.whose({ name: title });

  if (existing.length > 0 && existing[0]) return existing[0];

  return music.make({ new: 'userPlaylist', withProperties: { name: title } });
}

/** @param {MusicApplication} music @param {string} name @param {string[]} identities */
function addToPlaylist(music, name, identities) {
  if (identities.length === 0 || identities.length > PLAYLIST_TRACK_LIMIT)
    throw new Error('Invalid track count');

  // Every track is resolved before the playlist exists, so a bad identity never leaves an empty playlist behind.
  const tracks = identities.map((persistent) =>
    libraryTrack(music, persistent),
  );

  const playlist = hostPlaylist(music, name);

  for (const track of tracks) {
    track.duplicate({ to: playlist });
  }

  return tracks.length;
}

// About 800 ms of settling at most, which covers Music's usual delay between a script returning and its state changing.
const SETTLE_POLLS = 16;
const SETTLE_INTERVAL_SECONDS = 0.05;

/** @param {MusicApplication} music @param {string[]} argv */
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
  const expectedPlaying =
    action === 'pause' ? false : action === 'resume' ? true : null;

  const status =
    expectedPlaying === null
      ? readValue(() => describeStatus(music), null)
      : settlePlayback(music, expectedPlaying);

  return JSON.stringify({ dispatched: true, status });
}

/** @param {MusicApplication} music @param {boolean} expectedPlaying */
function settlePlayback(music, expectedPlaying) {
  let status = readValue(() => describeStatus(music), null);

  for (
    let poll = 0;
    poll < SETTLE_POLLS && status && status.playing !== expectedPlaying;
    poll += 1
  ) {
    delay(SETTLE_INTERVAL_SECONDS);
    status = readValue(() => describeStatus(music), null);
  }

  return status;
}

/** The library write-back actions. Any other action returns null. @param {MusicApplication} music @param {string[]} argv @returns {string | null} */
function writeLibrary(music, argv) {
  const action = argv[0];

  if (action === 'favorite') {
    setFavorite(music, argv[1] ?? '', argv[2]);

    return JSON.stringify({ favorited: argv[2] === 'true' });
  }

  if (action === 'playlist-add') {
    const added = addToPlaylist(music, argv[1] ?? '', argv.slice(2));

    return JSON.stringify({ added });
  }

  return null;
}

/** @param {string[]} argv @returns {string} */
function handleRun(argv) {
  const music = Application('Music');

  if (!music.running()) {
    music.launch();
    delay(1);
  }

  const action = argv[0];

  const written = writeLibrary(music, argv);

  if (written !== null) return written;

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
