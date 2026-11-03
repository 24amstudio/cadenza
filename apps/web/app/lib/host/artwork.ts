// The Host returns artwork as base64 bytes without a media type. Only common image formats are shown; anything else is
// treated as unavailable so the page never renders unexpected content.
const signatures: [prefix: string, mediaType: string][] = [
  ['/9j/', 'image/jpeg'],
  ['iVBORw0KGgo', 'image/png'],
  ['UklGR', 'image/webp'],
  ['R0lGOD', 'image/gif'],
];

export function artworkDataUrl(dataBase64: string): string | null {
  for (const [prefix, mediaType] of signatures) {
    if (dataBase64.startsWith(prefix)) {
      return `data:${mediaType};base64,${dataBase64}`;
    }
  }

  return null;
}
