import type { BrowseKind, BrowseRequest } from './protocol/types';

// What the UI opens: the page of an album, artist or playlist. `title` is only a heading to show while the page loads.
export interface BrowseTarget {
  request: BrowseRequest;
  title?: string;
}

// One entry per page. A request that names a song is a different key from the same page opened by its ID, which is
// why a result is also stored under the ID the Host resolved.
export function browseKey(request: BrowseRequest): string {
  if (request.id !== undefined) return `${request.kind}:${request.id}`;

  if (request.song !== undefined) {
    return `${request.kind}:song:${request.song.source}:${request.song.id}`;
  }

  return request.kind;
}

// Playlists change while Music is used, so they are kept briefly. Albums and artists change rarely.
const playlistTtlMs = 60_000;
const catalogTtlMs = 5 * 60_000;

export function browseTtlMs(kind: BrowseKind): number {
  return kind === 'album' || kind === 'artist' ? catalogTtlMs : playlistTtlMs;
}

export function describeBrowseFailure(
  errorCode: string,
  message: string,
): string {
  switch (errorCode) {
    case 'not_found':
      return 'Cadenza Host could not find that in Music.';
    case 'catalog_unavailable':
      return 'Apple Music is not reachable from Cadenza Host right now.';
    case 'timeout':
      return 'Cadenza Host took too long to answer.';
    case 'unavailable':
      return 'Cadenza Host is not connected.';
    default:
      return message === ''
        ? 'Cadenza Host could not load this page.'
        : message;
  }
}
