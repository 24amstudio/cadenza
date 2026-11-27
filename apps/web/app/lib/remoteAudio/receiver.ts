import { contextFrameForHost, type ClockFix } from './clockMap';
import {
  audioType,
  decodeAudioFrame,
  decodeFlush,
  decodePing,
  encodePong,
  flushType,
  pingType,
} from './wire';
import { nextSequence, sequenceStep } from './sequence';
import {
  commandMessage,
  parseSetupMessage,
  streamConfigMessage,
  type RemoteAudioHostSetup,
  type RemoteAudioRoomStatus,
  type RemoteAudioSettings,
} from './config';

export const remoteAudioSampleRate = 48_000;

/** The `/cast/live` audio socket for the Host socket that this page already uses. */
export function remoteAudioSocketUrl(socketUrl: string): string {
  const url = new URL(socketUrl);

  url.pathname = '/cast/live';
  url.search = '?role=remote_audio';
  url.hash = '';

  return url.toString();
}

export interface RemoteAudioStatus {
  state: 'idle' | 'connecting' | 'streaming' | 'failed';
  linkHealthy: boolean;
  calibrationState: string;
  clockDriftPpm: number;
  droppedStaleFrames60s: number;
  message: string;
  /** The setup the Host owns, as its latest `REMOTE_AUDIO_SETUP` carried it. */
  setup: RemoteAudioHostSetup | null;
  roomStatus: RemoteAudioRoomStatus;
}

export interface RemoteAudioCredentials {
  clientId: string;
  token: string;
}

interface SyncMessage {
  type: string;
  clockOffsetUs?: number;
  clockDriftPpm?: number;
  jitterBufferMs?: number;
  calibrationState?: string;
  droppedStaleFrames60s?: number;
  linkHealthy?: boolean;
}

/** The Remote's end of the audio socket. It plays what the Host sends and reports the Remote's clock for the Host to
 *  measure. The audio graph lives in an AudioWorklet that runs at 48 kHz. */
export class RemoteAudioReceiver {
  #context: AudioContext | null = null;
  #node: AudioWorkletNode | null = null;
  #socket: WebSocket | null = null;
  #fix: ClockFix | null = null;
  #expectedSequence: number | null = null;
  #frameCount = 512;
  #status: RemoteAudioStatus = {
    state: 'idle',
    linkHealthy: false,
    calibrationState: 'not_required',
    clockDriftPpm: 0,
    droppedStaleFrames60s: 0,
    message: '',
    setup: null,
    roomStatus: 'not_measured',
  };

  constructor(
    private readonly url: string,
    private readonly credentials: RemoteAudioCredentials,
    private readonly onStatus: (status: RemoteAudioStatus) => void = () => {},
  ) {}

  get status(): RemoteAudioStatus {
    return this.#status;
  }

  /** Opens the audio context, which needs a user gesture, and the socket. */
  async start(): Promise<void> {
    this.#publish({ state: 'connecting', message: 'Connecting to the Host' });

    const context = new AudioContext({
      sampleRate: remoteAudioSampleRate,
      latencyHint: 'interactive',
    });

    await context.audioWorklet.addModule('/remote-audio-worklet.js');
    await context.resume();

    const node = new AudioWorkletNode(context, 'cadenza-remote-audio', {
      outputChannelCount: [2],
    });

    node.connect(context.destination);
    this.#context = context;
    this.#node = node;

    const socket = new WebSocket(this.url);

    // A socket that stop() has already replaced reports nothing, so a deliberate stop never reads as a failure.
    const isCurrent = () => this.#socket === socket;

    socket.binaryType = 'arraybuffer';
    socket.onopen = () => {
      if (isCurrent()) this.#handshake(context);
    };

    socket.onmessage = (event: MessageEvent<string | ArrayBuffer>) => {
      if (isCurrent()) this.#receive(event.data);
    };

    socket.onclose = () => {
      if (isCurrent())
        this.#publish({ state: 'failed', message: 'The audio socket closed' });
    };

    socket.onerror = () => {
      if (isCurrent())
        this.#publish({ state: 'failed', message: 'The audio socket failed' });
    };

    this.#socket = socket;
  }

  /** Asks the Host for a new output environment, which measures the room again. */
  sendCommand(action: 'new_environment'): void {
    this.#socket?.send(commandMessage(action));
  }

  /** Sends the stream settings for this Remote. The Host applies them to the next frames. */
  sendConfig(settings: RemoteAudioSettings): void {
    this.#socket?.send(
      streamConfigMessage(settings, this.credentials.clientId),
    );
  }

  stop(): void {
    this.#socket?.close();
    this.#socket = null;
    this.#node?.disconnect();
    this.#node = null;
    void this.#context?.close();
    this.#context = null;
    this.#fix = null;
    this.#expectedSequence = null;
    this.#publish({ state: 'idle', message: '' });
  }

  #handshake(context: AudioContext): void {
    this.#socket?.send(
      JSON.stringify({
        version: 1,
        type: 'REMOTE_AUDIO_HANDSHAKE',
        clientId: this.credentials.clientId,
        token: this.credentials.token,
        transport: 'wifi_lan',
        sampleRate: remoteAudioSampleRate,
        baseLatencyMs: (context.baseLatency ?? 0) * 1_000,
        outputLatencyMs: (context.outputLatency ?? 0) * 1_000,
        userAgent: navigator.userAgent,
      }),
    );
  }

  #receive(data: string | ArrayBuffer): void {
    if (!(data instanceof ArrayBuffer)) {
      this.#receiveSync(data);

      return;
    }

    const type = new Uint8Array(data)[0];

    if (type === audioType) this.#receiveAudio(data);
    else if (type === pingType) this.#answerPing(data);
    else if (type === flushType) this.#flush(data);
  }

  #receiveSync(text: string): void {
    let message: SyncMessage;

    try {
      // SAFETY: the Host's sync message is JSON, and every field is read below with an explicit check before use.
      message = JSON.parse(text) as SyncMessage;
    } catch {
      return;
    }

    if (message.type === 'REMOTE_AUDIO_SETUP') {
      this.#receiveSetup(text);

      return;
    }

    if (message.type !== 'REMOTE_AUDIO_SYNC') return;

    if (message.clockOffsetUs !== undefined) {
      this.#fix = {
        offsetUs: message.clockOffsetUs,
        driftPpm: message.clockDriftPpm ?? 0,
        arrivedAtRemoteUs: performance.now() * 1_000,
      };
    }

    // The cushion plus one frame is the locked fill, so the worklet's controller holds the clock at this target.
    if (message.jitterBufferMs !== undefined) {
      this.#node?.port.postMessage({
        type: 'target',
        frames:
          (message.jitterBufferMs / 1_000) * remoteAudioSampleRate +
          this.#frameCount,
      });
    }

    this.#publish({
      state: 'streaming',
      linkHealthy: message.linkHealthy ?? false,
      calibrationState: message.calibrationState ?? 'not_required',
      clockDriftPpm: message.clockDriftPpm ?? 0,
      droppedStaleFrames60s: message.droppedStaleFrames60s ?? 0,
    });
  }

  #receiveSetup(text: string): void {
    const setup = parseSetupMessage(text);

    if (setup === null) return;

    this.#publish({ setup, roomStatus: setup.roomStatus });
  }

  #receiveAudio(data: ArrayBuffer): void {
    const frame = decodeAudioFrame(data);

    if (frame === null || this.#node === null || this.#context === null) return;

    const step = sequenceStep(this.#expectedSequence, frame.sequenceNumber);

    this.#expectedSequence = nextSequence(frame.sequenceNumber);
    this.#frameCount = frame.frameCount;

    const timestamp = this.#context.getOutputTimestamp();

    if (
      this.#fix === null ||
      !timestamp.performanceTime ||
      step.kind === 'late'
    ) {
      return;
    }

    const left = frame.channelSamples[0];

    if (left === undefined) return;

    const right = frame.channelSamples[1] ?? left;

    const startFrame = contextFrameForHost(
      frame.targetPlayoutHostUs,
      this.#fix,
      {
        contextTime: timestamp.contextTime ?? 0,
        performanceTime: timestamp.performanceTime,
      },
      remoteAudioSampleRate,
    );

    // A mono frame shares one array for both channels, and a transfer list cannot name the same buffer twice.
    const transfer =
      left === right ? [left.buffer] : [left.buffer, right.buffer];

    this.#node.port.postMessage(
      { type: 'frame', startFrame, left, right },
      transfer,
    );
  }

  #answerPing(data: ArrayBuffer): void {
    const ping = decodePing(data);

    if (ping === null) return;

    const received = performance.now() * 1_000;
    const sent = performance.now() * 1_000;

    this.#socket?.send(encodePong(ping.t1HostSendUs, received, sent));
  }

  #flush(data: ArrayBuffer): void {
    if (decodeFlush(data) === null) return;

    this.#node?.port.postMessage({ type: 'flush' });
  }

  #publish(patch: Partial<RemoteAudioStatus>): void {
    this.#status = { ...this.#status, ...patch };
    this.onStatus(this.#status);
  }
}
