// Plays the stage's audio. Fragmented MP4 codecs (AC-3 and AAC) go to a MediaSource buffer in sequence mode. Raw PCM goes
// to an AudioWorklet over its message port. SharedArrayBuffer is not used, because the Host serves no cross-origin
// isolation headers. A flush empties both paths, and a new generation starts with a fresh init segment.

import { decodeStageFrame, type StageFrame } from './stageProtocol';

const MAX_QUEUED_FRAGMENTS = 64;
const TRIM_MARGIN_S = 2;

/** The MSE type for each fragmented codec. PCM (codec 3) has no container and goes to the worklet. */
export function stageMime(codec: number): string | null {
  switch (codec) {
    case 1:
      return 'audio/mp4; codecs="ac-3"';
    case 2:
      return 'audio/mp4; codecs="flac"';
    case 4:
      return 'audio/mp4; codecs="mp4a.40.2"';
    default:
      return null;
  }
}

/** The codecs this browser can decode, reported in the profile. PCM always works when an AudioContext exists. */
export function supportedStageCodecs(): string[] {
  const codecs: string[] = [];

  if ('MediaSource' in globalThis) {
    if (MediaSource.isTypeSupported(stageMime(4) ?? '')) codecs.push('aac');

    if (MediaSource.isTypeSupported(stageMime(1) ?? '')) codecs.push('ac-3');
  }

  if ('AudioContext' in globalThis) codecs.push('pcm');

  return codecs;
}

interface Track {
  codec: number;
  channels: number;
  mediaSource: MediaSource;
  buffer: SourceBuffer | null;
  url: string;
  queue: ArrayBuffer[];
}

export class StageAudioEngine {
  private context: AudioContext | null = null;
  private worklet: AudioWorkletNode | null = null;
  private track: Track | null = null;
  private generation = -1;
  private readonly media: HTMLAudioElement | null;

  constructor(private readonly onError: (message: string) => void = () => {}) {
    this.media =
      'document' in globalThis ? document.createElement('audio') : null;

    if (this.media) this.media.autoplay = true;
  }

  /** Called from a user gesture, because browsers refuse to start audio otherwise. */
  async unlock(): Promise<void> {
    if (!('AudioContext' in globalThis)) return;
    this.context ??= new AudioContext({ latencyHint: 'interactive' });

    if (this.context.state !== 'running') await this.context.resume();

    if (!this.worklet) {
      await this.context.audioWorklet.addModule('/stage-lpcm-worklet.js');
      this.worklet = new AudioWorkletNode(this.context, 'cadenza-lpcm', {
        outputChannelCount: [2],
      });
      this.worklet.connect(this.context.destination);
    }
  }

  /** The sink's own latency, which the clock uses to line lyrics up with the sound. */
  outputLatencyMs(): number {
    const latency = this.context
      ? this.context.outputLatency || this.context.baseLatency
      : 0;

    return Math.round(latency * 1_000);
  }

  handleBinary(bytes: Uint8Array): void {
    let frame: StageFrame;

    try {
      frame = decodeStageFrame(bytes);
    } catch {
      return;
    }

    if (frame.type === 'FLUSH_STREAM') {
      this.flush(frame.generationSeq);

      return;
    }

    if (frame.type === 'INIT_SEGMENT') {
      this.initialise(frame.codec, frame.channels, frame.payload);

      return;
    }

    if (frame.type === 'AUDIO_FRAME')
      this.audio(frame.codec, frame.channels, frame.payload);
  }

  flush(generation: number): void {
    this.generation = generation;
    this.worklet?.port.postMessage({ type: 'flush' });
    const track = this.track;

    if (!track) return;
    track.queue.length = 0;

    const buffer = track.buffer;

    if (!buffer) return;

    try {
      if (buffer.updating) buffer.abort();

      if (buffer.buffered.length > 0)
        buffer.remove(0, Number.POSITIVE_INFINITY);
    } catch {
      this.reset();
    }
  }

  close(): void {
    this.reset();
    void this.context?.close();
    this.context = null;
    this.worklet = null;
  }

  private initialise(
    codec: number,
    channels: number,
    payload: Uint8Array,
  ): void {
    if (codec === 3) return;
    const mime = stageMime(codec);

    if (
      !mime ||
      !('MediaSource' in globalThis) ||
      !MediaSource.isTypeSupported(mime)
    ) {
      this.onError('This TV cannot play the stage audio codec.');

      return;
    }

    if (this.track?.codec !== codec || this.track.channels !== channels)
      this.reset();

    if (!this.track) {
      const mediaSource = new MediaSource();
      const url = URL.createObjectURL(mediaSource);
      mediaSource.addEventListener('sourceopen', () => {
        if (
          this.track?.mediaSource !== mediaSource ||
          mediaSource.sourceBuffers.length > 0
        )
          return;
        const buffer = mediaSource.addSourceBuffer(mime);
        buffer.mode = 'sequence';
        buffer.addEventListener('updateend', () => {
          this.trim();
          this.drain();
        });

        if (this.track?.mediaSource === mediaSource) this.track.buffer = buffer;
        this.drain();
      });
      this.media?.setAttribute('src', url);
      void this.media?.play().catch(() => {});
      this.track = {
        codec,
        channels,
        mediaSource,
        buffer: null,
        url,
        queue: [],
      };
    }

    // SAFETY: slice() copies the bytes into a buffer that no other view shares.
    this.track.queue.push(payload.slice().buffer as ArrayBuffer);
    this.drain();
  }

  private audio(codec: number, channels: number, payload: Uint8Array): void {
    if (codec === 3) {
      this.pcm(channels, payload);

      return;
    }

    const track = this.track;

    if (!track || track.codec !== codec) return;
    // SAFETY: slice() copies the bytes into a buffer that no other view shares.
    track.queue.push(payload.slice().buffer as ArrayBuffer);

    // A stalled buffer must not grow without bound. The oldest audio is the least useful, so it goes first.
    if (track.queue.length > MAX_QUEUED_FRAGMENTS)
      track.queue.splice(0, track.queue.length - MAX_QUEUED_FRAGMENTS);
    this.drain();
  }

  private pcm(channels: number, payload: Uint8Array): void {
    if (!this.worklet) return;

    const samples = new Float32Array(
      payload.buffer.slice(
        payload.byteOffset,
        payload.byteOffset + payload.byteLength,
      ),
    );

    this.worklet.port.postMessage({ type: 'pcm', channels, samples }, [
      samples.buffer,
    ]);
  }

  private drain(): void {
    const track = this.track;

    if (
      !track?.buffer ||
      track.buffer.updating ||
      track.mediaSource.readyState !== 'open'
    )
      return;
    const next = track.queue.shift();

    if (!next) return;

    try {
      track.buffer.appendBuffer(next);
    } catch {
      this.reset();
    }
  }

  /** Removes played audio, keeping a short margin behind the playhead so the buffer never starves. */
  private trim(): void {
    const track = this.track;
    const media = this.media;

    if (!track?.buffer || track.buffer.updating || !media) return;
    const keepFrom = media.currentTime - TRIM_MARGIN_S;

    if (keepFrom <= 0) return;

    const start =
      track.buffer.buffered.length > 0 ? track.buffer.buffered.start(0) : 0;

    if (keepFrom > start) {
      try {
        track.buffer.remove(start, keepFrom);
      } catch {
        this.reset();
      }
    }
  }

  private reset(): void {
    const track = this.track;
    this.track = null;

    if (!track) return;
    URL.revokeObjectURL(track.url);
    this.media?.removeAttribute('src');
  }
}
