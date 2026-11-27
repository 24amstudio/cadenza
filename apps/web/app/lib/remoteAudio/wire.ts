// Binary frames on the Wi-Fi Remote audio socket. `shared/protocol/README.md` defines the layouts, and
// `shared/protocol/examples/remote-audio-frames.json` holds the bytes that the Host and this decoder must agree on.
// Header integers are big-endian. LPCM samples are little-endian.
//
// Host clock values are microseconds. They fit in a double exactly for more than 280 years of uptime, so they are
// plain numbers here.

export const audioType = 0x01;
export const flushType = 0x02;
export const pingType = 0x04;
export const pongType = 0x05;

const audioHeaderBytes = 26;
const flushBytes = 5;
const pingBytes = 17;
const pongBytes = 25;

export type StreamFlag = 'pure_full_range' | 'crossover_hpf_mains';

export interface RemoteAudioFrame {
  flag: StreamFlag;
  channels: number;
  bitDepth: 16 | 32;
  sequenceNumber: number;
  hostCaptureTimeUs: number;
  targetPlayoutHostUs: number;
  frameCount: number;
  /** Planar channels: one Float32Array per channel, each `frameCount` long, with samples in the range -1 to 1. */
  channelSamples: Float32Array[];
}

export interface RemoteAudioPing {
  pingSequence: number;
  t1HostSendUs: number;
}

/** Decodes an AUDIO_FRAME. Returns null unless the header, the payload length, and each value match the contract. */
export function decodeAudioFrame(bytes: ArrayBuffer): RemoteAudioFrame | null {
  if (bytes.byteLength < audioHeaderBytes) return null;

  const view = new DataView(bytes);

  if (view.getUint8(0) !== audioType) return null;

  const flagValue = view.getUint8(1);
  const channels = view.getUint8(2);
  const bitDepth = view.getUint8(3);
  const frameCount = view.getUint16(24);

  const flag: StreamFlag | null =
    flagValue === 0
      ? 'pure_full_range'
      : flagValue === 1
        ? 'crossover_hpf_mains'
        : null;

  if (flag === null || channels < 1 || channels > 2) return null;

  if (bitDepth !== 16 && bitDepth !== 32) return null;

  const bytesPerSample = bitDepth / 8;

  if (
    bytes.byteLength - audioHeaderBytes !==
    frameCount * channels * bytesPerSample
  ) {
    return null;
  }

  // Samples are interleaved on the wire, so each channel is read with its stride.
  const channelSamples: Float32Array[] = [];

  for (let channel = 0; channel < channels; channel += 1) {
    const plane = new Float32Array(frameCount);

    for (let frame = 0; frame < frameCount; frame += 1) {
      const offset =
        audioHeaderBytes + (frame * channels + channel) * bytesPerSample;

      plane[frame] =
        bitDepth === 32
          ? view.getFloat32(offset, true)
          : view.getInt16(offset, true) / 32768;
    }

    channelSamples.push(plane);
  }

  return {
    flag,
    channels,
    bitDepth,
    sequenceNumber: view.getUint32(4),
    hostCaptureTimeUs: readUint64(view, 8),
    targetPlayoutHostUs: readUint64(view, 16),
    frameCount,
    channelSamples,
  };
}

/** Decodes a FLUSH_STREAM and returns its generation, or null for any other frame. */
export function decodeFlush(bytes: ArrayBuffer): number | null {
  if (bytes.byteLength !== flushBytes) return null;

  const view = new DataView(bytes);

  return view.getUint8(0) === flushType ? view.getUint32(1) : null;
}

/** Decodes a CLOCK_PING, which the Remote answers with a pong. */
export function decodePing(bytes: ArrayBuffer): RemoteAudioPing | null {
  if (bytes.byteLength !== pingBytes) return null;

  const view = new DataView(bytes);

  if (view.getUint8(0) !== pingType) return null;

  return {
    pingSequence: readUint64(view, 1),
    t1HostSendUs: readUint64(view, 9),
  };
}

/** Encodes the CLOCK_PONG that carries the Host's send time and the Remote's receive and send times, in microseconds. */
export function encodePong(
  t1HostSendUs: number,
  t2RemoteRecvUs: number,
  t3RemoteSendUs: number,
): ArrayBuffer {
  const buffer = new ArrayBuffer(pongBytes);
  const view = new DataView(buffer);

  view.setUint8(0, pongType);
  writeUint64(view, 1, t1HostSendUs);
  writeUint64(view, 9, t2RemoteRecvUs);
  writeUint64(view, 17, t3RemoteSendUs);

  return buffer;
}

function readUint64(view: DataView, offset: number): number {
  return Number(view.getBigUint64(offset));
}

function writeUint64(view: DataView, offset: number, value: number): void {
  view.setBigUint64(offset, BigInt(Math.round(value)));
}
