import { describe, expect, test } from 'bun:test';
import type { HostChange } from '../app/lib/host/client';
import {
  FakeSocket,
  MemoryCredentials,
  harness,
  occurrenceId,
  remoteId,
  socketAt,
  token,
  welcome,
} from './support/hostClient';

describe('HostClient motion', () => {
  const motionCapabilities = ['artwork.host-cache', 'motion.host-cache'];
  const artworkUrl = 'https://example.com/album.jpg';
  const nextOccurrenceId = '1b2c3d4e-1111-4222-8333-444455556666';

  const video = Uint8Array.from({ length: 2_500 }, (_, index) =>
    index < 8
      ? [0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70][index]!
      : (index * 13) % 256,
  );

  test('asks for the playing song with its artwork, so its motion video can replace the full image', () => {
    const { client, sockets } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, motionCapabilities));

    client.requestArtwork(artworkUrl, {
      kind: 'full',
      occurrenceId,
    });

    expect(
      socketAt(sockets, 0).framesOfType('artwork.get').at(-1),
    ).toMatchObject({
      artwork_url: artworkUrl,
      motion: true,
      occurrence_id: occurrenceId,
    });
  });

  test('shows the preview first, then the verified motion video under the same request', async () => {
    const { client, sockets, changes } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, motionCapabilities));
    client.requestArtwork(artworkUrl, {
      kind: 'full',
      occurrenceId,
    });

    const requestId = String(
      socketAt(sockets, 0).framesOfType('artwork.get').at(-1)?.request_id,
    );

    const preview = Buffer.from([0xff, 0xd8, 0xff, 0xe0]).toString('base64');

    socketAt(sockets, 0).receive({
      type: 'artwork',
      request_id: requestId,
      artwork_url: artworkUrl,
      artwork_data_base64: preview,
      variant: 'preview',
    });

    expect(changes).toContainEqual({
      kind: 'artwork',
      artworkUrl,
      dataUrl: `data:image/jpeg;base64,${preview}`,
      full: false,
    });

    await sendMotion(
      socketAt(sockets, 0),
      requestId,
      video,
      await sha256Hex(video),
    );
    await waitForMotion(changes);

    expect(latestMotion(changes)).toMatchObject({ artworkUrl });
    expect(latestMotion(changes)?.video).toEqual(video);
  });

  test('never shows a video whose bytes fail the digest', async () => {
    const { client, sockets, changes } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, motionCapabilities));
    client.requestArtwork(artworkUrl, {
      kind: 'full',
      occurrenceId,
    });

    const requestId = String(
      socketAt(sockets, 0).framesOfType('artwork.get').at(-1)?.request_id,
    );

    const otherDigest = await sha256Hex(video.slice(1));

    await sendMotion(socketAt(sockets, 0), requestId, video, otherDigest);
    await waitForMotion(changes);

    expect(latestMotion(changes)?.video).toBeNull();
  });

  test('a preview-only request asks for the small image alone', () => {
    const { client, sockets } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, motionCapabilities));

    client.requestArtwork(artworkUrl, { kind: 'preview' });

    const request = socketAt(sockets, 0).framesOfType('artwork.get').at(-1);
    expect(request).toMatchObject({
      artwork_url: artworkUrl,
      progressive: true,
      preview_only: true,
    });
    expect(request).not.toHaveProperty('motion');
  });

  test('does not ask for motion the Host did not advertise', () => {
    const { client, sockets } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, ['artwork.host-cache']));

    client.requestArtwork(artworkUrl, {
      kind: 'full',
      occurrenceId,
    });

    expect(
      socketAt(sockets, 0).framesOfType('artwork.get').at(-1),
    ).not.toHaveProperty('motion');
  });

  test('asks for motion over Bluetooth, the only transport the web page has', () => {
    const credentials = new MemoryCredentials();
    credentials.value = {
      remoteId,
      token,
      name: 'Desk',
      lastCreditSequence: 0,
    };
    const { client } = harness(credentials);
    const link = new FakeSocket();

    client.startBluetooth(false);
    client.connectOverBluetooth(link);
    link.receive(welcome(null, motionCapabilities));
    client.requestArtwork(artworkUrl, {
      kind: 'full',
      occurrenceId,
    });

    expect(link.framesOfType('artwork.get').at(-1)).toMatchObject({
      motion: true,
      occurrence_id: occurrenceId,
    });
  });

  test('a song change abandons the old full image, and its late chunks are ignored', async () => {
    const { client, sockets, changes } = harness();
    client.start('S'.repeat(43));
    socketAt(sockets, 0).open();
    socketAt(sockets, 0).receive(welcome(token, motionCapabilities));
    client.requestArtwork(artworkUrl, { kind: 'full', occurrenceId });

    const requestId = String(
      socketAt(sockets, 0).framesOfType('artwork.get').at(-1)?.request_id,
    );

    client.cancelFullArtwork(occurrenceId);
    expect(socketAt(sockets, 0).framesOfType('artwork.cancel')).toHaveLength(0);

    client.cancelFullArtwork(nextOccurrenceId);
    expect(socketAt(sockets, 0).framesOfType('artwork.cancel')).toMatchObject([
      { type: 'artwork.cancel', request_id: requestId },
    ]);

    await sendMotion(
      socketAt(sockets, 0),
      requestId,
      video,
      await sha256Hex(video),
    );
    await new Promise((resolve) => setTimeout(resolve, 50));

    expect(latestMotion(changes)).toBeUndefined();
  });
});

// Sends the video as motion chunks in reverse order, the way the Host's chunks may arrive over a busy link.
async function sendMotion(
  socket: FakeSocket,
  requestId: string,
  file: Uint8Array,
  sha256: string,
): Promise<void> {
  const chunkSize = 1_000;
  const count = Math.ceil(file.length / chunkSize);

  for (let index = count - 1; index >= 0; index -= 1) {
    socket.receive({
      type: 'motion.chunk',
      request_id: requestId,
      occurrence_id: occurrenceId,
      chunk_index: index,
      chunk_count: count,
      total_bytes: file.length,
      sha256,
      data_base64: Buffer.from(
        file.subarray(index * chunkSize, (index + 1) * chunkSize),
      ).toString('base64'),
    });
  }
}

async function sha256Hex(bytes: Uint8Array<ArrayBuffer>): Promise<string> {
  return Array.from(
    new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
    (byte) => byte.toString(16).padStart(2, '0'),
  ).join('');
}

// Verification is asynchronous, so the result arrives a moment after the last chunk.
async function waitForMotion(changes: HostChange[]): Promise<void> {
  for (
    let attempt = 0;
    attempt < 400 && latestMotion(changes) === undefined;
    attempt += 1
  ) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

function latestMotion(
  changes: HostChange[],
): Extract<HostChange, { kind: 'motion' }> | undefined {
  return changes
    .filter(
      (change): change is Extract<HostChange, { kind: 'motion' }> =>
        change.kind === 'motion',
    )
    .at(-1);
}
