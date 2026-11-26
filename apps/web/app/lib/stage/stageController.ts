// The Tier-2 stage's connection. It owns the socket, pairing, the receiver token, reconnects, and the audio engine. The
// view reads `state` and calls `command` and `unlock`. It keeps no timers while the socket is closed and retries on a
// bounded backoff.

import { StageAudioEngine, supportedStageCodecs } from './stageAudioEngine';
import { StageClock, stageRetryDelayMs } from './stageClock';
import {
  parseStageMessage,
  receiverProfile,
  stageLogMessage,
  stagePlaybackMessage,
  type StagePlaybackReport,
  type StageServerMessage,
  type StageTrackSuite,
  type StageVideoPayload,
} from './stageProtocol';

const TOKEN_KEY = 'cadenza.stage.token.v1';
const RECEIVER_KEY = 'cadenza.stage.receiverId.v1';

export type StagePhase = 'connecting' | 'pairing' | 'ready' | 'offline';

export interface StageState {
  phase: StagePhase;
  pin: string | null;
  pinExpiresAt: number | null;
  suite: StageTrackSuite | null;
  video: StageVideoPayload | null;
  nextTrackId: string | null;
  audioUnlocked: boolean;
  playing: boolean;
  error: string | null;
}

/** Storage can be blocked or cleared. A stage then pairs again, and nothing else depends on the value. */
function readStorage(key: string): string | null {
  try {
    return globalThis.localStorage?.getItem(key) ?? null;
  } catch {
    return null;
  }
}

function writeStorage(key: string, value: string): void {
  try {
    globalThis.localStorage?.setItem(key, value);
  } catch {
    // The token is kept for this page only, and the next visit pairs again.
  }
}

function newReceiverId(): string {
  const bytes = new Uint8Array(6);
  crypto.getRandomValues(bytes);

  return `tv-${Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('')}`;
}

export class StageController {
  readonly clock = new StageClock();
  readonly engine: StageAudioEngine;
  readonly state: StageState = {
    phase: 'connecting',
    pin: null,
    pinExpiresAt: null,
    suite: null,
    video: null,
    nextTrackId: null,
    audioUnlocked: false,
    playing: false,
    error: null,
  };

  private socket: WebSocket | null = null;
  private attempt = 0;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private closed = false;
  // Reports and log lines are sent only on an approved socket. The Host closes a socket that sends them before approval.
  private approved = false;
  private lastPlayback = '';
  private readonly receiverId: string;
  private readonly onChange: () => void;

  constructor(onChange: () => void) {
    this.onChange = onChange;
    this.receiverId = readStorage(RECEIVER_KEY) ?? newReceiverId();
    writeStorage(RECEIVER_KEY, this.receiverId);
    this.engine = new StageAudioEngine(
      (message) => {
        this.state.error = message;
        this.log('error', message);
        this.onChange();
      },
      (report) => this.reportPlayback(report),
      (level, message) => this.log(level, message),
    );
  }

  start(): void {
    this.closed = false;
    this.connect();
  }

  stop(): void {
    this.closed = true;

    if (this.retryTimer !== null) clearTimeout(this.retryTimer);
    this.socket?.close();
    this.socket = null;
    this.engine.close();
  }

  /** Starts audio from a user gesture, which the browser requires before any sound plays. */
  async unlock(): Promise<void> {
    try {
      await this.engine.unlock();
      this.state.audioUnlocked = true;
    } catch {
      this.state.error = 'This TV did not start the audio output.';
    }

    this.onChange();
  }

  /** A playback command for the Host, from a TV remote key or a button. Only an approved stage may send one. */
  command(
    action:
      | 'playback.pause'
      | 'playback.resume'
      | 'playback.skip'
      | 'playback.previous',
  ): void {
    if (
      this.state.phase !== 'ready' ||
      this.socket?.readyState !== WebSocket.OPEN
    )
      return;
    this.socket.send(
      JSON.stringify({ version: 1, type: 'STAGE_COMMAND', action }),
    );
  }

  private connect(): void {
    this.state.phase = 'connecting';
    this.onChange();
    const scheme = location.protocol === 'https:' ? 'wss' : 'ws';

    const socket = new WebSocket(
      `${scheme}://${location.host}/cast/live?role=tv_stage`,
    );

    socket.binaryType = 'arraybuffer';
    this.socket = socket;
    socket.onopen = () => {
      this.attempt = 0;
      this.lastPlayback = '';

      // A receiver with a token is approved on connect, so it is ready before the first track arrives.
      if (readStorage(TOKEN_KEY) !== null) {
        this.state.phase = 'ready';
        this.approved = true;
      }

      socket.send(this.profile());
    };

    socket.onmessage = (event: MessageEvent<unknown>) => {
      const data: unknown = event.data;

      if (data instanceof ArrayBuffer) {
        this.engine.handleBinary(new Uint8Array(data));

        return;
      }

      // String(value) returns the same string only for a string, so text frames are told apart without typeof.
      if (String(data) === data) {
        const message = parseStageMessage(data);

        if (message) this.apply(message);
      }
    };

    socket.onclose = () => {
      if (this.socket === socket) {
        this.socket = null;
        this.approved = false;
      }

      this.state.phase = 'offline';
      this.state.playing = false;
      this.onChange();

      if (!this.closed) this.scheduleRetry();
    };
  }

  private scheduleRetry(): void {
    const delay = stageRetryDelayMs(this.attempt);
    this.attempt += 1;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      this.connect();
    }, delay);
  }

  private profile(): string {
    const codecs = supportedStageCodecs();

    return receiverProfile({
      receiverId: this.receiverId,
      displayName: 'Cadenza TV',
      maxAudioChannels: codecs.includes('ac-3') ? 6 : 2,
      supportedCodecs: codecs,
      touch: navigator.maxTouchPoints > 0,
      lipSyncOffsetMs: 0,
      receiverToken: readStorage(TOKEN_KEY),
    });
  }

  /** Whether a report or log line may go out now: the socket is open and the Host has approved it. */
  private canReport(): boolean {
    return this.approved && this.socket?.readyState === WebSocket.OPEN;
  }

  private reportPlayback(report: StagePlaybackReport): void {
    const text = stagePlaybackMessage(report);

    if (text === this.lastPlayback || !this.canReport()) return;
    this.lastPlayback = text;
    this.socket?.send(text);
  }

  private log(level: 'info' | 'warn' | 'error', message: string): void {
    if (this.canReport()) this.socket?.send(stageLogMessage(level, message));
  }

  private apply(message: StageServerMessage): void {
    const now = performance.now();

    switch (message.type) {
      case 'STAGE_PAIRING':
        this.state.phase = 'pairing';
        this.state.pin = message.pin;
        this.state.pinExpiresAt = Date.now() + message.expiresInMs;
        break;
      case 'STAGE_ACCEPTED':
        writeStorage(TOKEN_KEY, message.receiverToken);
        this.state.phase = 'ready';
        this.state.pin = null;
        this.state.pinExpiresAt = null;
        this.approved = true;
        this.engine.reportCurrent();
        break;
      case 'TRACK_SUITE_PAYLOAD':
        this.state.phase = 'ready';
        this.state.suite = message.suite;
        this.state.video = null;
        this.clock.set(0, true, 1, now);
        this.state.playing = true;
        break;
      case 'PREFETCH_NEXT_SUITE':
        this.state.nextTrackId = message.trackId;
        break;
      case 'OPTIMISTIC_STATE':
        this.clock.set(
          message.targetPositionMs,
          message.isPlaying,
          message.playbackRate,
          now,
        );
        this.state.playing = message.isPlaying;
        break;
      case 'CLOCK_CALIBRATE':
        this.clock.set(message.actualPositionMs, this.clock.isPlaying, 1, now);
        break;
      case 'VIDEO_KARAOKE_PAYLOAD':
        this.state.video = {
          mediaUrl: message.mediaUrl,
          subtitleUrl: message.subtitleUrl,
          userOffsetMs: message.userOffsetMs,
        };
        break;
    }

    this.onChange();
  }
}
