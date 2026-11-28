import {
  commandMessage,
  parseSetupMessage,
  streamConfigMessage,
  type RemoteAudioHostSetup,
  type RemoteAudioRoomStatus,
  type RemoteAudioSettings,
} from './config';
import { nextSequence, sequenceStep } from './sequence';
import type { ClockFix } from './clockMap';
import { playoutFrame, type OutputClockSample } from './timeline';
import { dropoutWindowCount, jitterMs, rttWindowSamples } from './linkHealth';
import {
  booleanField,
  isJsonObject,
  numberField,
  parseJson,
  stringField,
} from '../protocol/json';
import {
  audioType,
  decodeAudioFrame,
  decodeFlush,
  decodePing,
  encodePong,
  flushType,
  pingType,
} from './wire';

export const remoteAudioSampleRate = 48_000;

const maximumLongTaskMs = 10_000;

const socketOpen = 1;

export interface RemoteAudioStatus {
  state: 'idle' | 'connecting' | 'streaming' | 'failed';
  socketOpen: boolean;
  linkHealthy: boolean;
  calibrationState: string;
  clockDriftPpm: number;
  droppedStaleFrames60s: number;
  playoutDroppedFrames: number;
  networkJitterMs: number | null;
  dropoutMs60s: number;
  transmitting: boolean;
  networkRttMs: number | null;
  processingRttMs: number | null;
  quality: string | null;
  qualityReason: string;
  message: string;
  setup: RemoteAudioHostSetup | null;
  roomStatus: RemoteAudioRoomStatus;
}

export interface RemoteAudioCredentials {
  clientId: string;
  token: string;
}

export interface RemoteAudioOutput {
  baseLatencyMs: number;
  outputLatencyMs: number;
  userAgent: string;
}

export interface SocketLike {
  readonly readyState: number;
  binaryType: BinaryType;
  onopen: (() => void) | null;
  onmessage: ((event: { data: unknown }) => void) | null;
  onclose: (() => void) | null;
  onerror: (() => void) | null;
  send(data: string | ArrayBuffer | ArrayBufferView): void;
  close(): void;
}

export type FramePortMessage =
  | { type: 'target'; frames: number }
  | { type: 'flush' }
  | {
      type: 'frame';
      startFrame: number;
      left: Float32Array;
      right: Float32Array;
    };

export interface FramePort {
  postMessage(message: FramePortMessage, transfer?: Transferable[]): void;
}

export interface RemoteAudioSocketDeps {
  connect(url: string): SocketLike;
  port: FramePort;
  now(): number;
  emit(patch: Partial<RemoteAudioStatus>): void;
}

export interface PlayoutCounts {
  dropped: number;
  concealed: number;
  underrun: number;
}

export class RemoteAudioSocketCore {
  #deps: RemoteAudioSocketDeps;
  #credentials: RemoteAudioCredentials | null = null;
  #output: RemoteAudioOutput | null = null;
  #socket: SocketLike | null = null;
  #fix: ClockFix | null = null;
  #clock: OutputClockSample | null = null;
  #expectedSequence: number | null = null;
  #frameCount = 512;
  #latestSettings: RemoteAudioSettings | null = null;
  #droppedFrames = 0;
  #windowUnderrunFrames = 0;
  #windowConcealedFrames = 0;
  #windowLongTaskMs = 0;
  #windowDroppedFrames = 0;
  #rttSamples: number[] = [];
  #dropoutFrames: number[] = [];

  constructor(deps: RemoteAudioSocketDeps) {
    this.#deps = deps;
  }

  start(
    url: string,
    credentials: RemoteAudioCredentials,
    output: RemoteAudioOutput,
  ): void {
    this.#credentials = credentials;
    this.#output = output;
    this.#droppedFrames = 0;
    this.#windowUnderrunFrames = 0;
    this.#windowConcealedFrames = 0;
    this.#windowLongTaskMs = 0;
    this.#windowDroppedFrames = 0;
    this.#rttSamples = [];
    this.#dropoutFrames = [];
    this.#deps.emit({
      state: 'connecting',
      message: 'Connecting to the Host',
      playoutDroppedFrames: 0,
      socketOpen: false,
    });

    const socket = this.#deps.connect(url);
    const isCurrent = () => this.#socket === socket;

    socket.binaryType = 'arraybuffer';
    socket.onopen = () => {
      if (!isCurrent()) return;

      this.#handshake();
      this.#sendLatestConfig();
      this.#deps.emit({ socketOpen: true });
    };

    socket.onmessage = (event) => {
      if (!isCurrent()) return;

      if (event.data instanceof ArrayBuffer) this.receive(event.data);
      else this.receive(String(event.data));
    };

    socket.onclose = () => {
      if (isCurrent()) {
        this.#deps.emit({
          state: 'failed',
          message: 'The audio socket closed',
          socketOpen: false,
        });
      }
    };

    socket.onerror = () => {
      if (isCurrent()) {
        this.#deps.emit({
          state: 'failed',
          message: 'The audio socket failed',
          socketOpen: false,
        });
      }
    };

    this.#socket = socket;
  }

  sendConfig(settings: RemoteAudioSettings): void {
    this.#latestSettings = settings;

    if (this.#isOpen()) this.#sendLatestConfig();
  }

  sendCommand(action: 'new_environment'): boolean {
    if (!this.#isOpen() || this.#socket === null) return false;

    this.#socket.send(commandMessage(action));

    return true;
  }

  setOutputClock(sample: OutputClockSample): void {
    this.#clock = sample;
  }

  addLongTaskMs(ms: number): void {
    this.#windowLongTaskMs += ms;
  }

  receivePlayoutCounts(counts: PlayoutCounts): void {
    this.#droppedFrames += counts.dropped;
    this.#windowConcealedFrames += counts.concealed;
    this.#windowUnderrunFrames += counts.underrun;
    this.#windowDroppedFrames += counts.dropped;

    if (counts.dropped > 0) {
      console.warn(
        `Cadenza Remote dropped ${counts.dropped} audio frames that the playout could not place (${this.#droppedFrames} since this stream started).`,
      );
    }

    this.#deps.emit({ playoutDroppedFrames: this.#droppedFrames });
  }

  stop(): void {
    const socket = this.#socket;

    this.#socket = null;
    socket?.close();
    this.#fix = null;
    this.#clock = null;
    this.#expectedSequence = null;
    this.#deps.emit({ state: 'idle', message: '', socketOpen: false });
  }

  receive(data: string | ArrayBuffer): void {
    if (!(data instanceof ArrayBuffer)) {
      this.#receiveSync(data);

      return;
    }

    const type = new Uint8Array(data)[0];

    if (type === audioType) this.#receiveAudio(data);
    else if (type === pingType) this.#answerPing(data);
    else if (type === flushType) this.#flush(data);
  }

  #isOpen(): boolean {
    return this.#socket !== null && this.#socket.readyState === socketOpen;
  }

  #sendLatestConfig(): void {
    if (
      this.#socket === null ||
      this.#latestSettings === null ||
      this.#credentials === null
    )
      return;

    this.#socket.send(
      streamConfigMessage(this.#latestSettings, this.#credentials.clientId),
    );
  }

  #handshake(): void {
    if (
      this.#socket === null ||
      this.#credentials === null ||
      this.#output === null
    )
      return;

    this.#socket.send(
      JSON.stringify({
        version: 1,
        type: 'REMOTE_AUDIO_HANDSHAKE',
        clientId: this.#credentials.clientId,
        token: this.#credentials.token,
        transport: 'wifi_lan',
        sampleRate: remoteAudioSampleRate,
        baseLatencyMs: this.#output.baseLatencyMs,
        outputLatencyMs: this.#output.outputLatencyMs,
        userAgent: this.#output.userAgent,
      }),
    );
  }

  #receiveSync(text: string): void {
    const message = parseJson(text);

    if (message === null || !isJsonObject(message)) return;

    const type = stringField(message, 'type');

    if (type === 'REMOTE_AUDIO_SETUP') {
      const setup = parseSetupMessage(text);

      if (setup !== null)
        this.#deps.emit({ setup, roomStatus: setup.roomStatus });

      return;
    }

    if (type !== 'REMOTE_AUDIO_SYNC') return;

    const clockOffsetUs = numberField(message, 'clockOffsetUs');
    const clockDriftPpm = numberField(message, 'clockDriftPpm') ?? 0;

    if (clockOffsetUs !== null) {
      this.#fix = {
        offsetUs: clockOffsetUs,
        driftPpm: clockDriftPpm,
        arrivedAtRemoteUs: this.#deps.now() * 1_000,
      };
    }

    const jitterBufferMs = numberField(message, 'jitterBufferMs');

    if (jitterBufferMs !== null) {
      this.#deps.port.postMessage({
        type: 'target',
        frames:
          (jitterBufferMs / 1_000) * remoteAudioSampleRate + this.#frameCount,
      });
    }

    const networkRttMs = numberField(message, 'networkRttMs');

    if (networkRttMs !== null) {
      this.#rttSamples.push(networkRttMs);

      if (this.#rttSamples.length > rttWindowSamples) this.#rttSamples.shift();
    }

    this.#deps.emit({
      state: 'streaming',
      linkHealthy: booleanField(message, 'linkHealthy') ?? false,
      calibrationState:
        stringField(message, 'calibrationState') ?? 'not_required',
      clockDriftPpm,
      droppedStaleFrames60s: numberField(message, 'droppedStaleFrames60s') ?? 0,
      transmitting: booleanField(message, 'transmitting') ?? false,
      networkRttMs,
      networkJitterMs: jitterMs(this.#rttSamples),
      processingRttMs: numberField(message, 'processingRttMs'),
      quality: stringField(message, 'quality'),
      qualityReason: stringField(message, 'qualityReason') ?? 'steady',
    });
    this.#reportPlayout();
  }

  #reportPlayout(): void {
    if (!this.#isOpen() || this.#socket === null) return;

    this.#socket.send(
      JSON.stringify({
        version: 1,
        type: 'REMOTE_AUDIO_PLAYOUT',
        underrunFrames: this.#windowUnderrunFrames,
        concealedFrames: this.#windowConcealedFrames,
        longTaskMs: Math.min(
          maximumLongTaskMs,
          Math.round(this.#windowLongTaskMs),
        ),
      }),
    );

    this.#dropoutFrames.push(
      this.#windowUnderrunFrames +
        this.#windowConcealedFrames +
        this.#windowDroppedFrames,
    );

    if (this.#dropoutFrames.length > dropoutWindowCount)
      this.#dropoutFrames.shift();

    this.#deps.emit({ dropoutMs60s: this.#dropoutMs60s() });

    this.#windowUnderrunFrames = 0;
    this.#windowConcealedFrames = 0;
    this.#windowDroppedFrames = 0;
    this.#windowLongTaskMs = 0;
  }

  #dropoutMs60s(): number {
    let frames = 0;

    for (const window of this.#dropoutFrames) frames += window;

    return (frames / remoteAudioSampleRate) * 1_000;
  }

  #receiveAudio(data: ArrayBuffer): void {
    const frame = decodeAudioFrame(data);

    if (frame === null) return;

    const step = sequenceStep(this.#expectedSequence, frame.sequenceNumber);

    this.#expectedSequence = nextSequence(frame.sequenceNumber);
    this.#frameCount = frame.frameCount;

    if (this.#fix === null || this.#clock === null || step.kind === 'late')
      return;

    const left = frame.channelSamples[0];

    if (left === undefined) return;

    const right = frame.channelSamples[1] ?? left;

    const startFrame = playoutFrame(
      frame.targetPlayoutHostUs,
      this.#fix,
      this.#clock,
      this.#deps.now(),
      remoteAudioSampleRate,
    );

    const transfer =
      left === right ? [left.buffer] : [left.buffer, right.buffer];

    this.#deps.port.postMessage(
      { type: 'frame', startFrame, left, right },
      transfer,
    );
  }

  #answerPing(data: ArrayBuffer): void {
    const ping = decodePing(data);

    if (ping === null) return;

    const received = this.#deps.now() * 1_000;
    const sent = this.#deps.now() * 1_000;

    this.#socket?.send(encodePong(ping.t1HostSendUs, received, sent));
  }

  #flush(data: ArrayBuffer): void {
    if (decodeFlush(data) === null) return;

    this.#deps.port.postMessage({ type: 'flush' });
  }
}
