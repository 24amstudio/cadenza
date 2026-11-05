import { describe, expect, test } from 'bun:test';
import {
  BluetoothFrameReader,
  bluetoothChunks,
  maximumBluetoothFrameBytes,
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

  test('will not frame an outgoing message beyond the protocol limit', () => {
    const tooLarge = 'x'.repeat(maximumBluetoothFrameBytes + 1);

    expect(() => bluetoothChunks(tooLarge)).toThrow('too large');
  });
});
