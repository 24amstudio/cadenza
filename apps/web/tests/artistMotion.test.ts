import { describe, expect, test } from 'bun:test';
import {
  ArtistMotion,
  type ArtistMotionMessage,
} from '../app/lib/host/artistMotion';
import { decodeHostMessage } from '../app/lib/protocol/decode';

const requestId = '3f1c2a2e-7b6d-4c1e-9a1f-2d3e4f5a6b7c';
const video = new Uint8Array([1, 2, 3, 4, 5, 6]);

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new Uint8Array(bytes));

  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');
}

function base64(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('base64');
}

async function chunksOf(
  bytes: Uint8Array,
  sha256: string,
): Promise<ArtistMotionMessage[]> {
  const half = Math.ceil(bytes.length / 2);

  return [
    {
      type: 'artist.motion.chunk',
      requestId,
      index: 0,
      count: 2,
      totalBytes: bytes.length,
      sha256,
      dataBase64: base64(bytes.slice(0, half)),
    },
    {
      type: 'artist.motion.chunk',
      requestId,
      index: 1,
      count: 2,
      totalBytes: bytes.length,
      sha256,
      dataBase64: base64(bytes.slice(half)),
    },
  ];
}

describe('artist motion requests', () => {
  test('a header resolves to its video once every chunk arrives with a matching digest', async () => {
    const sent: string[] = [];

    const artistMotion = new ArtistMotion(
      (text) => {
        sent.push(text);

        return true;
      },
      () => requestId,
    );

    const pending = artistMotion.request('Payung Teduh');

    expect(JSON.parse(sent[0] ?? '{}')).toMatchObject({
      type: 'artist.motion.get',
      request_id: requestId,
      artist_name: 'Payung Teduh',
    });

    for (const chunk of await chunksOf(video, await sha256Hex(video))) {
      artistMotion.receive(chunk);
    }

    expect(await pending).toEqual(video);
  });

  test('a video that fails its digest is refused rather than shown', async () => {
    const artistMotion = new ArtistMotion(
      () => true,
      () => requestId,
    );

    const pending = artistMotion.request('Payung Teduh');
    const wrongDigest = await sha256Hex(new Uint8Array([9, 9]));

    for (const chunk of await chunksOf(video, wrongDigest)) {
      artistMotion.receive(chunk);
    }

    expect(await pending).toBeNull();
  });

  test('a Host with no video, or a link that is down, leaves the header on its artwork', async () => {
    const unavailable = new ArtistMotion(
      () => true,
      () => requestId,
    );

    const refused = unavailable.request('Unknown Artist');

    unavailable.receive({ type: 'artist.motion.unavailable', requestId });

    expect(await refused).toBeNull();
    expect(
      await new ArtistMotion(
        () => false,
        () => requestId,
      ).request('Payung Teduh'),
    ).toBeNull();
  });

  test('a host frame decodes into the artist motion message the transfer expects', async () => {
    const [chunk] = await chunksOf(video, await sha256Hex(video));

    expect(
      decodeHostMessage(
        JSON.stringify({
          version: 1,
          type: 'artist.motion.chunk',
          request_id: requestId,
          chunk_index: 0,
          chunk_count: 2,
          total_bytes: video.length,
          sha256: chunk?.type === 'artist.motion.chunk' ? chunk.sha256 : '',
          data_base64:
            chunk?.type === 'artist.motion.chunk' ? chunk.dataBase64 : '',
        }),
      ),
    ).toMatchObject({
      type: 'artist.motion.chunk',
      requestId,
      index: 0,
      count: 2,
    });
    expect(
      decodeHostMessage(
        JSON.stringify({
          version: 1,
          type: 'artist.motion.unavailable',
          request_id: requestId,
        }),
      ),
    ).toEqual({ type: 'artist.motion.unavailable', requestId });
  });
});
