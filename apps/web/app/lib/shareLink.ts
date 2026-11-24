const IDENTIFIER = /^[A-Za-z0-9._-]{1,64}$/;

function identifier(value: string | null | undefined): string | null {
  return value && IDENTIFIER.test(value) ? value : null;
}

/**
 * The catalog song a shared Apple Music link names, or null. A song link names its song, and an album link names one
 * only with `?i=`. Playlists and albums without a track name no single song, so they are refused rather than guessed.
 */
export function sharedSongId(shared: string): string | null {
  const url = shared
    .trim()
    .split(/\s+/)
    .find((part) => part.startsWith('https://music.apple.com/'));

  if (url === undefined) return null;

  let parsed: URL;

  try {
    parsed = new URL(url);
  } catch {
    return null;
  }

  if (parsed.protocol !== 'https:' || parsed.hostname !== 'music.apple.com') {
    return null;
  }

  const segments = parsed.pathname
    .split('/')
    .filter((segment) => segment.length > 0);

  const kind = segments.findIndex(
    (segment) =>
      segment === 'song' || segment === 'album' || segment === 'playlist',
  );

  if (kind < 0) return null;

  const named = segments[kind];

  if (named === 'song') return identifier(segments.at(-1));

  if (named === 'album') return identifier(parsed.searchParams.get('i'));

  return null;
}
