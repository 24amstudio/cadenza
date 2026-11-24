/**
 * Starts the next song's cover early, so it is on screen when its song begins. The Host's thermal budget comes first:
 * under constrained or survival pressure the cover waits, and optional fetching stops.
 */
export function prefetchNextCover(
  artwork: { prefetch(url: string): void },
  albums: { shown(url: string): string },
  url: string | null | undefined,
  budget: string | null | undefined,
): void {
  if (!url || budget === 'constrained' || budget === 'survival') return;

  artwork.prefetch(albums.shown(url));
}
