import type { RemoteAudioSettings } from './config';
import {
  remoteAudioSampleRate,
  type RemoteAudioCredentials,
  type RemoteAudioStatus,
} from './socketCore';
import type { SocketWorkerInbound, SocketWorkerOutbound } from './socketWorker';

export { remoteAudioSampleRate };

export type { RemoteAudioCredentials, RemoteAudioStatus };

/** The `/cast/live` audio socket for the Host socket that this page already uses. */
export function remoteAudioSocketUrl(socketUrl: string): string {
  const url = new URL(socketUrl);

  url.pathname = '/cast/live';
  url.search = '?role=remote_audio';
  url.hash = '';

  return url.toString();
}

const clockIntervalMs = 250;

export class RemoteAudioReceiver {
  #context: AudioContext | null = null;
  #node: AudioWorkletNode | null = null;
  #worker: Worker | null = null;
  #clockTimer: ReturnType<typeof setInterval> | null = null;
  #longTasks: PerformanceObserver | null = null;
  #longTaskMs = 0;
  #latestSettings: RemoteAudioSettings | null = null;
  #status: RemoteAudioStatus = {
    state: 'idle',
    socketOpen: false,
    linkHealthy: false,
    calibrationState: 'not_required',
    clockDriftPpm: 0,
    droppedStaleFrames60s: 0,
    playoutDroppedFrames: 0,
    networkJitterMs: null,
    dropoutMs60s: 0,
    transmitting: false,
    networkRttMs: null,
    processingRttMs: null,
    quality: null,
    qualityReason: 'steady',
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

  async start(baseURL: string): Promise<void> {
    this.#publish({
      state: 'connecting',
      message: 'Connecting to the Host',
      playoutDroppedFrames: 0,
    });

    const context = new AudioContext({
      sampleRate: remoteAudioSampleRate,
      latencyHint: 'interactive',
    });

    await context.audioWorklet.addModule(`${baseURL}remote-audio-worklet.js`);
    await context.resume();

    const node = new AudioWorkletNode(context, 'cadenza-remote-audio', {
      outputChannelCount: [2],
    });

    node.connect(context.destination);

    const frames = new MessageChannel();
    node.port.postMessage({ type: 'frame-port', port: frames.port2 }, [
      frames.port2,
    ]);

    const worker = new Worker(new URL('./socketWorker.ts', import.meta.url), {
      type: 'module',
    });

    worker.onmessage = (event: MessageEvent<SocketWorkerOutbound>) => {
      if (event.data.type === 'status') this.#publish(event.data.patch);
    };

    this.#context = context;
    this.#node = node;
    this.#worker = worker;
    this.#observeLongTasks();
    this.#post(
      {
        type: 'start',
        url: this.url,
        credentials: this.credentials,
        output: {
          baseLatencyMs: (context.baseLatency ?? 0) * 1_000,
          outputLatencyMs: (context.outputLatency ?? 0) * 1_000,
          userAgent: navigator.userAgent,
        },
        port: frames.port1,
      },
      [frames.port1],
    );

    if (this.#latestSettings !== null) {
      this.#post({ type: 'config', settings: this.#latestSettings });
    }

    this.#clockTimer = setInterval(() => this.#sampleClock(), clockIntervalMs);
  }

  sendCommand(action: 'new_environment'): boolean {
    if (!this.#status.socketOpen || this.#worker === null) return false;

    this.#post({ type: 'command', action });

    return true;
  }

  /** Sends the stream settings for this Remote. The Host applies them to the next frames. */
  sendConfig(settings: RemoteAudioSettings): void {
    const plain: RemoteAudioSettings = { ...settings };
    this.#latestSettings = plain;

    if (this.#worker !== null) this.#post({ type: 'config', settings: plain });
  }

  stop(): void {
    if (this.#clockTimer !== null) clearInterval(this.#clockTimer);
    this.#clockTimer = null;
    this.#longTasks?.disconnect();
    this.#longTasks = null;
    this.#worker?.terminate();
    this.#worker = null;
    this.#node?.disconnect();
    this.#node = null;
    void this.#context?.close();
    this.#context = null;
    this.#publish({ state: 'idle', message: '', socketOpen: false });
  }

  #sampleClock(): void {
    if (this.#context === null) return;

    const timestamp = this.#context.getOutputTimestamp();

    if (timestamp.performanceTime) {
      this.#post({
        type: 'clock',
        sample: {
          contextTime: timestamp.contextTime ?? 0,
          epochMs: performance.timeOrigin + timestamp.performanceTime,
        },
      });
    }

    if (this.#longTaskMs > 0) {
      this.#post({ type: 'longTasks', ms: this.#longTaskMs });
      this.#longTaskMs = 0;
    }
  }

  #observeLongTasks(): void {
    if (typeof PerformanceObserver === 'undefined') return;

    if (!PerformanceObserver.supportedEntryTypes.includes('longtask')) return;

    this.#longTasks = new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) {
        this.#longTaskMs += entry.duration;
      }
    });
    this.#longTasks.observe({ type: 'longtask', buffered: false });
  }

  #post(message: SocketWorkerInbound, transfer: Transferable[] = []): void {
    this.#worker?.postMessage(message, transfer);
  }

  #publish(patch: Partial<RemoteAudioStatus>): void {
    this.#status = { ...this.#status, ...patch };
    this.onStatus(this.#status);
  }
}
