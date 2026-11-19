import { describe, expect, test } from 'bun:test';
import {
  BluetoothFrameReader,
  bluetoothChunks,
  maximumBluetoothFrameBytes,
  stalledBluetoothFrameMs,
  withDeadline,
  writeFrameChunks,
  type BluetoothFrameWriter,
} from '../app/lib/host/bluetooth';

function joined(chunks: Uint8Array[]): Uint8Array {
  const bytes = new Uint8Array(
    chunks.reduce((sum, chunk) => sum + chunk.length, 0),
  );

  let offset = 0;

  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }

  return bytes;
}

describe('Bluetooth framing', () => {
  test('writes a 4-byte big-endian length, then the UTF-8 bytes, in 20-byte values', () => {
    const chunks = bluetoothChunks('{"type":"hello"}');

    expect(chunks.every((chunk) => chunk.length <= 20)).toBe(true);
    expect(Array.from(joined(chunks).subarray(0, 4))).toEqual([0, 0, 0, 16]);
    expect(new TextDecoder().decode(joined(chunks).subarray(4))).toBe(
      '{"type":"hello"}',
    );
  });

  test('reassembles a message split at every byte, including inside a multibyte character', () => {
    const message = '{"name":"Café ✓"}';
    const bytes = joined(bluetoothChunks(message));

    for (let split = 1; split < bytes.length; split += 1) {
      const reader = new BluetoothFrameReader();

      expect(reader.append(bytes.subarray(0, split))).toEqual([]);
      expect(reader.append(bytes.subarray(split))).toEqual([message]);
    }
  });

  test('delivers messages that arrive in one notification in order', () => {
    const first = '{"type":"state"}';
    const second = '{"type":"heartbeat"}';

    const combined = joined([
      ...bluetoothChunks(first),
      ...bluetoothChunks(second),
    ]);

    const reader = new BluetoothFrameReader();

    expect(reader.append(combined)).toEqual([first, second]);
  });

  test('refuses a declared length above the protocol limit', () => {
    const header = new Uint8Array(4);

    new DataView(header.buffer).setUint32(0, maximumBluetoothFrameBytes + 1);

    expect(() => new BluetoothFrameReader().append(header)).toThrow(
      'invalid Bluetooth frame',
    );
  });

  test('refuses a message whose bytes are not valid UTF-8', () => {
    const payload = new Uint8Array([0xff, 0xfe, 0xfd]);
    const framed = new Uint8Array(4 + payload.length);

    new DataView(framed.buffer).setUint32(0, payload.length);
    framed.set(payload, 4);

    expect(() => new BluetoothFrameReader().append(framed)).toThrow();
  });

  test('frames match the Host and Remote golden bytes', () => {
    // The Host (Swift) and Remote (Kotlin) codec tests assert the same bytes.
    expect(bluetoothChunks('hello').map((chunk) => [...chunk])).toEqual([
      [0, 0, 0, 5, 104, 101, 108, 108, 111],
    ]);
    expect(
      bluetoothChunks('x'.repeat(36)).map((chunk) => chunk.length),
    ).toEqual([20, 20]);
  });

  test('drops a message that stops growing, then reads the next one cleanly', () => {
    let now = 0;
    const reader = new BluetoothFrameReader(() => now);
    const lost = bluetoothChunks('x'.repeat(100));

    // The first fragments arrive and the rest never does.
    expect(reader.append(lost[0] ?? new Uint8Array())).toEqual([]);
    expect(reader.append(lost[1] ?? new Uint8Array())).toEqual([]);

    now += stalledBluetoothFrameMs + 1;

    const next = joined(bluetoothChunks('{"type":"state"}'));

    expect(() => reader.append(next)).toThrow('stalled');
    expect(reader.append(next)).toEqual(['{"type":"state"}']);
  });

  test('a slow but steady message is not a stall', () => {
    let now = 0;
    const reader = new BluetoothFrameReader(() => now);
    const received: string[] = [];

    for (const chunk of bluetoothChunks('y'.repeat(300))) {
      now += stalledBluetoothFrameMs - 1;
      received.push(...reader.append(chunk));
    }

    expect(received).toEqual(['y'.repeat(300)]);
  });

  test('will not frame an outgoing message beyond the protocol limit', () => {
    const tooLarge = 'x'.repeat(maximumBluetoothFrameBytes + 1);

    expect(() => bluetoothChunks(tooLarge)).toThrow('too large');
  });
});

function recordingWriter(writeWithoutResponse: boolean) {
  const calls: string[] = [];

  const writer: BluetoothFrameWriter = {
    properties: { writeWithoutResponse },
    writeValueWithResponse: async () => {
      calls.push('response');
    },
    writeValueWithoutResponse: async () => {
      calls.push('no-response');
    },
  };

  return { writer, calls };
}

describe('Bluetooth frame writes', () => {
  test('acknowledges only the last chunk of a frame', async () => {
    const chunks = bluetoothChunks(
      '{"type":"command","padding":"' + 'x'.repeat(80) + '"}',
    );

    const { writer, calls } = recordingWriter(true);

    await writeFrameChunks(writer, chunks);

    expect(calls).toEqual([
      ...Array.from({ length: chunks.length - 1 }, () => 'no-response'),
      'response',
    ]);
  });

  test('keeps every chunk acknowledged when the Host characteristic has no write without response', async () => {
    const chunks = bluetoothChunks('{"type":"clock"}');
    const { writer, calls } = recordingWriter(false);

    await writeFrameChunks(writer, chunks);

    expect(calls).toEqual(chunks.map(() => 'response'));
  });
});

describe('Bluetooth deadlines', () => {
  test('abandons an attempt that never answers and says so', async () => {
    let abandoned = false;

    await expect(
      withDeadline(new Promise<never>(() => undefined), 5, () => {
        abandoned = true;
      }),
    ).rejects.toThrow('did not answer');
    expect(abandoned).toBe(true);
  });

  test('passes a timely result through without abandoning anything', async () => {
    let abandoned = false;

    expect(
      await withDeadline(Promise.resolve(7), 1_000, () => {
        abandoned = true;
      }),
    ).toBe(7);
    expect(abandoned).toBe(false);
  });
});
