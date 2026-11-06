import { describe, expect, test } from 'bun:test';
import { artworkStatus } from '../app/lib/host/artwork';
import {
  ArtworkAssembly,
  base64ToBytes,
  bytesToBase64,
  digestMatches,
} from '../app/lib/host/artworkAssembly';

describe('artwork display state', () => {
  test('waits while bytes are on their way, and tells a missing image from an unavailable one', () => {
    const known = { loaded: 'data:image/jpeg;base64,/9j/', missing: null };

    expect(artworkStatus(null, known)).toBe('empty');
    expect(artworkStatus('pending', known)).toBe('loading');
    expect(artworkStatus('loaded', known)).toBe('ready');
    expect(artworkStatus('missing', known)).toBe('unavailable');
  });
});

const file = Uint8Array.from(
  { length: 2_500 },
  (_, index) => (index * 37) % 256,
);

function chunks(bytes: Uint8Array, size: number): Uint8Array[] {
  const parts: Uint8Array[] = [];

  for (let offset = 0; offset < bytes.length; offset += size) {
    parts.push(bytes.subarray(offset, offset + size));
  }

  return parts;
}

describe('artwork reassembly', () => {
  test('rebuilds the file from chunks that arrive out of order', () => {
    const parts = chunks(file, 1_000);
    const assembly = new ArtworkAssembly(parts.length, file.length, 'ab');
    let result: Uint8Array | null = null;

    for (const index of [2, 0, 1]) {
      result = assembly.add(index, parts[index]!);
    }

    expect(result).toEqual(file);
  });

  test('stays incomplete until every chunk is present, and ignores a repeated chunk', () => {
    const parts = chunks(file, 1_000);
    const assembly = new ArtworkAssembly(parts.length, file.length, 'ab');
    expect(assembly.add(0, parts[0]!)).toBeNull();
    expect(assembly.add(0, parts[0]!)).toBeNull();
    expect(assembly.add(1, parts[1]!)).toBeNull();
  });

  test('refuses sizes that do not fit the protocol limits', () => {
    expect(ArtworkAssembly.accepts(0, 10)).toBe(false);
    expect(ArtworkAssembly.accepts(5, 0)).toBe(false);
    expect(ArtworkAssembly.accepts(4_097, 10)).toBe(false);
    expect(ArtworkAssembly.accepts(3, 2_500)).toBe(true);
  });
});

describe('artwork integrity and encoding', () => {
  test('a digest matches only the file it describes', async () => {
    const digest = Array.from(
      new Uint8Array(await crypto.subtle.digest('SHA-256', file)),
      (byte) => byte.toString(16).padStart(2, '0'),
    ).join('');

    expect(await digestMatches(file, digest)).toBe(true);
    expect(await digestMatches(file.slice(1), digest)).toBe(false);
  });

  test('base64 round-trips every byte value, including bytes above 0x7f', () => {
    const everyByte = Uint8Array.from(
      { length: 512 },
      (_, index) => index % 256,
    );

    expect(base64ToBytes(bytesToBase64(everyByte))).toEqual(everyByte);
  });
});
