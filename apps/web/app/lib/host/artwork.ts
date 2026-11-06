// The Host returns artwork as base64 bytes without a media type. Only common image formats are shown; anything else is
// treated as unavailable so the page never renders unexpected content.
const signatures: [prefix: string, mediaType: string][] = [
  ['/9j/', 'image/jpeg'],
  ['iVBORw0KGgo', 'image/png'],
  ['UklGR', 'image/webp'],
  ['R0lGOD', 'image/gif'],
];

export type ArtworkStatus = 'empty' | 'loading' | 'ready' | 'unavailable';

// Waiting for the Host is a different state from a Host that has no artwork, so a placeholder can animate only while
// bytes are still on their way.
export function artworkStatus(
  url: string | null,
  known: Record<string, string | null>,
): ArtworkStatus {
  if (url === null) return 'empty';

  const dataUrl: string | null | undefined = known[url];

  if (dataUrl === undefined) return 'loading';

  return dataUrl === null ? 'unavailable' : 'ready';
}

export function artworkDataUrl(dataBase64: string): string | null {
  for (const [prefix, mediaType] of signatures) {
    if (dataBase64.startsWith(prefix)) {
      return `data:${mediaType};base64,${dataBase64}`;
    }
  }

  return null;
}
