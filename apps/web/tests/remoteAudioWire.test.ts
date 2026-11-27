import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import {
  decodeAudioFrame,
  decodeFlush,
  decodePing,
  encodePong,
} from '../app/lib/remoteAudio/wire';

// SAFETY: the fixture is the shared contract, and the fields below must exist in it for these tests to pass.
const fixture = JSON.parse(
  readFileSync(
    new URL(
      '../../../shared/protocol/examples/remote-audio-frames.json',
      import.meta.url,
    ),
    'utf8',
  ),
) as {
  audioFrame: { hex: string };
  flush: { hex: string };
  ping: { hex: string };
  pong: { hex: string };
};

function bytesOf(hex: string): ArrayBuffer {
  const bytes = new Uint8Array(hex.length / 2);

  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }

  return bytes.buffer;
}

describe('remote audio wire', () => {
  test('decodes the shared audio frame into planar samples and exact timing', () => {
    const frame = decodeAudioFrame(bytesOf(fixture.audioFrame.hex));

    expect(frame).not.toBeNull();
    expect(frame?.flag).toBe('crossover_hpf_mains');
    expect(frame?.sequenceNumber).toBe(42);
    expect(frame?.hostCaptureTimeUs).toBe(1_000_000_123_456);
    expect(frame?.targetPlayoutHostUs).toBe(1_000_028_123_456);
    expect(frame?.frameCount).toBe(2);
    // The fixture's int16 samples are 1000, -1000, 2000, -2000, interleaved L R.
    expect(Array.from(frame?.channelSamples[0] ?? [])).toEqual([
      1000 / 32768,
      2000 / 32768,
    ]);
    expect(Array.from(frame?.channelSamples[1] ?? [])).toEqual([
      -1000 / 32768,
      -2000 / 32768,
    ]);
  });

  test('refuses a frame whose payload does not match its header, or an unknown flag', () => {
    const bytes = bytesOf(fixture.audioFrame.hex);
    const truncated = bytes.slice(0, bytes.byteLength - 2);
    const unknownFlag = new Uint8Array(bytes.slice(0));

    unknownFlag[1] = 2;

    expect(decodeAudioFrame(truncated)).toBeNull();
    expect(decodeAudioFrame(unknownFlag.buffer)).toBeNull();
  });

  test('decodes the flush generation and the ping, and rejects other types', () => {
    expect(decodeFlush(bytesOf(fixture.flush.hex))).toBe(7);
    expect(decodeFlush(bytesOf(fixture.ping.hex))).toBeNull();
    expect(decodePing(bytesOf(fixture.ping.hex))).toEqual({
      pingSequence: 3,
      t1HostSendUs: 1_000_000_123_456,
    });
  });

  test('encodes the pong to the shared fixture bytes', () => {
    const pong = encodePong(
      1_000_000_123_456,
      5_000_000_250_000,
      5_000_000_260_000,
    );

    const expected = fixture.pong.hex;

    const actual = Array.from(new Uint8Array(pong))
      .map((byte) => byte.toString(16).padStart(2, '0'))
      .join('');

    expect(actual).toBe(expected);
  });
});
