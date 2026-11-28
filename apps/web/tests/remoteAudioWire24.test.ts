import { describe, expect, test } from 'bun:test';
import { decodeAudioFrame } from '../app/lib/remoteAudio/wire';

function twentyFourBitFrame(samples: number[]): ArrayBuffer {
  const header = new Uint8Array(26);
  const view = new DataView(header.buffer);
  header[0] = 0x01; // AUDIO_FRAME
  header[1] = 0; // pure full range
  header[2] = 2; // channels
  header[3] = 24; // bit depth
  view.setUint16(24, 2); // frame count
  const payload = new Uint8Array(samples.length * 3);
  samples.forEach((value, index) => {
    const bits = value & 0xff_ffff;
    payload[index * 3] = bits & 0xff;
    payload[index * 3 + 1] = (bits >> 8) & 0xff;
    payload[index * 3 + 2] = (bits >> 16) & 0xff;
  });
  const frame = new Uint8Array(26 + payload.length);
  frame.set(header, 0);
  frame.set(payload, 26);

  return frame.buffer;
}

describe('24-bit audio frames', () => {
  test('decodes little-endian samples, with the sign taken from bit 23', () => {
    const frame = decodeAudioFrame(
      twentyFourBitFrame([0x40_0000, -8_388_607, 0, 8_388_607]),
    );

    expect(frame?.bitDepth).toBe(24);
    expect(frame?.frameCount).toBe(2);
    expect(frame?.channelSamples[0]?.[0]).toBeCloseTo(0.5, 6);
    expect(frame?.channelSamples[0]?.[1]).toBeCloseTo(0, 6);
    expect(frame?.channelSamples[1]?.[0]).toBeCloseTo(-1, 6);
    expect(frame?.channelSamples[1]?.[1]).toBeCloseTo(1, 6);
  });

  test('refuses a 24-bit frame whose payload length does not match its header', () => {
    const frame = new Uint8Array(twentyFourBitFrame([0, 0, 0, 0]));
    const truncated = frame.slice(0, frame.length - 1).buffer;

    expect(decodeAudioFrame(truncated)).toBeNull();
  });
});
