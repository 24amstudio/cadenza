// Reassembles the full artwork image from the chunks the Host sends over Bluetooth. Every chunk carries the SHA-256 of the
// whole file, so a corrupted transfer is never shown.
export const maximumArtworkChunks = 4_096;
export const maximumArtworkBytes = 8 * 1_048_576;

export class ArtworkAssembly {
  private readonly parts: (Uint8Array | undefined)[];
  private received = 0;

  constructor(
    readonly count: number,
    readonly totalBytes: number,
    readonly sha256: string,
  ) {
    this.parts = new Array<Uint8Array | undefined>(count);
  }

  static accepts(count: number, totalBytes: number): boolean {
    return (
      count >= 1 &&
      count <= maximumArtworkChunks &&
      totalBytes >= 1 &&
      totalBytes <= maximumArtworkBytes
    );
  }

  // Returns the whole file once every chunk has arrived, and null until then. A repeated chunk is ignored.
  add(index: number, bytes: Uint8Array): Uint8Array | null {
    if (index < 0 || index >= this.count || this.parts[index] !== undefined) {
      return null;
    }

    this.parts[index] = bytes;
    this.received += 1;

    if (this.received < this.count) return null;

    const file = new Uint8Array(this.totalBytes);
    let offset = 0;

    for (const part of this.parts) {
      if (part === undefined || offset + part.length > this.totalBytes) {
        return null;
      }

      file.set(part, offset);
      offset += part.length;
    }

    return offset === this.totalBytes ? file : null;
  }
}

export async function digestMatches(
  bytes: Uint8Array,
  expectedHex: string,
): Promise<boolean> {
  // A copy gives the digest a buffer of the exact type it accepts.
  const digest = await crypto.subtle.digest('SHA-256', new Uint8Array(bytes));

  const hex = Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');

  return hex === expectedHex.toLowerCase();
}

export function base64ToBytes(text: string): Uint8Array {
  const binary = atob(text);

  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

export function bytesToBase64(bytes: Uint8Array): string {
  // Built in slices, because spreading a large array into one call exceeds the engine's argument limit.
  let binary = '';

  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }

  return btoa(binary);
}
