import type {
  Snapshot,
  CommandAction,
  CommandResult,
  QueueActionKind,
  RepeatMode,
  SongIdentity,
} from '../protocol/types';
import { traceEvent } from './trace';
import type { Readiness } from './client';

// The controls a person can press. Each one shows its own pending state while its command is queued or in flight.
export type ControlKey =
  | 'toggle'
  | 'next'
  | 'previous'
  | 'seek'
  | 'volume'
  | 'shuffle'
  | 'repeat'
  | 'queue';

type Intent =
  | { key: 'toggle' | 'next' | 'previous' }
  | { key: 'seek'; positionMs: number; occurrenceId: string }
  | { key: 'volume'; percent: number }
  | { key: 'shuffle'; enabled: boolean }
  | { key: 'repeat'; mode: RepeatMode }
  // Each song the person asked for is sent. Requests are never merged, and settled gets null when nothing was sent.
  | {
      key: 'queue';
      kind: QueueActionKind;
      song: SongIdentity;
      settled: (result: CommandResult | null) => void;
    };

export interface ControlPort {
  awaitReadiness(timeoutMs: number): Promise<Readiness>;
  awaitRevision(minRevision: number, timeoutMs: number): Promise<void>;
  latestSnapshot(): Snapshot | null;
  send(action: CommandAction): Promise<CommandResult>;
  wait(ms: number): Promise<void>;
}

export interface ControlOutput {
  pendingChanged(pending: ReadonlySet<ControlKey>): void;
  // The final result of an intent, after any retry. Applied results are included, so a caller can reconcile its state.
  finished(key: ControlKey, result: CommandResult): void;
  // Something stopped an intent before it was sent, such as a link that is down.
  notice(message: string): void;
}

const readyTimeoutMs = 3_000;
const revisionWaitMs = 800;
const busyRetryDelayMs = 300;

// A refusal before dispatch is the Host saying the command did nothing, so one more attempt with fresh state is safe. An
// unconfirmed result never qualifies: that command may have been applied.
const maximumRetries = 2;

function retryable(result: CommandResult): boolean {
  return (
    result.outcome === 'expired' ||
    (result.outcome === 'rejected' &&
      (result.errorCode === 'stale_revision' || result.errorCode === 'busy'))
  );
}

// Turns presses into commands, one at a time. The Host runs a single Music action at once and bumps its revision after
// each, so a second command sent early carries a stale revision and is refused. The queue therefore sends each command
// against the newest state, after the previous one has produced its own.
//
// A press is never dropped without a reason:
// - Next and Previous keep at most one waiting press each. More presses while one is waiting add nothing the person
//   could see, and an unbounded backlog would keep skipping songs after they stop pressing.
// - Two Play/Pause presses cancel out, which is what pressing twice does.
// - Seek, volume, shuffle and repeat send only the latest value. An older target has been overtaken.
export class ControlQueue {
  private readonly port: ControlPort;
  private readonly output: ControlOutput;
  private readonly waiting: Intent[] = [];
  private running: Intent | null = null;
  private draining = false;

  constructor(port: ControlPort, output: ControlOutput) {
    this.port = port;
    this.output = output;
  }

  press(intent: Intent): void {
    this.add(intent);
    this.publish();
    void this.drain();
  }

  private add(intent: Intent): void {
    if (intent.key === 'queue') {
      this.waiting.push(intent);

      return;
    }

    const index = this.waiting.findIndex((item) => item.key === intent.key);

    if (index < 0) {
      this.waiting.push(intent);

      return;
    }

    if (intent.key === 'toggle') {
      this.waiting.splice(index, 1);

      return;
    }

    if (
      intent.key === 'seek' ||
      intent.key === 'volume' ||
      intent.key === 'shuffle' ||
      intent.key === 'repeat'
    ) {
      this.waiting[index] = intent;
    }
  }

  private publish(): void {
    const pending = new Set<ControlKey>(this.waiting.map((item) => item.key));

    if (this.running !== null) pending.add(this.running.key);
    this.output.pendingChanged(pending);
  }

  private async drain(): Promise<void> {
    if (this.draining) return;
    this.draining = true;

    try {
      for (let next = this.waiting.shift(); next; next = this.waiting.shift()) {
        this.running = next;
        this.publish();
        const result = await this.perform(next);

        if (next.key === 'queue') next.settled(result);
        this.running = null;
        this.publish();
      }
    } finally {
      this.running = null;
      this.draining = false;
      this.publish();
    }
  }

  // The action is decided once, from the state when its turn comes. A retry resends that same action with a new envelope, so
  // a Play/Pause press cannot turn into its opposite because the state changed in between.
  // Resolves with the final result, or null when nothing was sent. Only playback intents are reported through finished.
  private async perform(intent: Intent): Promise<CommandResult | null> {
    let action: CommandAction | null = null;
    let occurrence: string | null = null;

    for (let attempt = 0; ; attempt += 1) {
      const snapshot = await this.readySnapshot();

      if (snapshot === null) return null;
      const playing = snapshot.current?.occurrenceId ?? null;

      if (action === null) {
        const built = this.build(intent, snapshot);

        if (built.action === null) {
          this.output.notice(built.reason);

          return null;
        }

        action = built.action;
        occurrence = playing;
      } else if (isOccurrenceBound(action) && playing !== occurrence) {
        this.output.notice(
          'Playback moved to another song, so that change was not sent again.',
        );

        return null;
      }

      const result = await this.port.send(action);

      if (!retryable(result) || attempt >= maximumRetries) {
        if (intent.key !== 'queue') this.output.finished(intent.key, result);

        return result;
      }

      traceEvent(`command ${action.kind} will be tried again`, {
        attempt: attempt + 1,
        errorCode: result.errorCode,
        outcome: result.outcome,
      });
      await this.catchUp(result);
    }
  }

  private async readySnapshot(): Promise<Snapshot | null> {
    const readiness = await this.port.awaitReadiness(readyTimeoutMs);
    const snapshot = this.port.latestSnapshot();

    if (readiness === 'ready' && snapshot !== null) return snapshot;

    this.output.notice(
      readiness === 'syncing'
        ? 'Cadenza Host is still syncing. Try again in a moment.'
        : 'Cadenza Host is not connected.',
    );

    return null;
  }

  // Waits for the state the refusal pointed at. A stale revision names the revision to wait for. A busy Host needs a moment.
  private async catchUp(result: CommandResult): Promise<void> {
    if (result.errorCode === 'busy') {
      await this.port.wait(busyRetryDelayMs);

      return;
    }

    await this.port.awaitRevision(result.revision, revisionWaitMs);
  }

  // The action for the newest state, or the reason there is none.
  private build(intent: Intent, snapshot: Snapshot): BuiltAction {
    if (intent.key === 'volume') {
      return actionOf({ kind: 'playback.volume', percent: intent.percent });
    }

    if (intent.key === 'shuffle') {
      return actionOf({ kind: 'playback.shuffle', enabled: intent.enabled });
    }

    if (intent.key === 'repeat') {
      return actionOf({ kind: 'playback.repeat', mode: intent.mode });
    }

    // A request names its song, and the Host decides where it goes, so nothing needs to be playing.
    if (intent.key === 'queue') {
      return actionOf({ kind: intent.kind, song: intent.song });
    }

    const song = snapshot.current;

    if (song === null) return refusal('Nothing is playing on Cadenza Host.');

    switch (intent.key) {
      case 'toggle':
        return actionOf({
          kind: snapshot.playing ? 'playback.pause' : 'playback.resume',
          occurrenceId: song.occurrenceId,
        });
      case 'next':
        return actionOf({
          kind: 'playback.skip',
          occurrenceId: song.occurrenceId,
        });
      case 'previous':
        return actionOf({
          kind: 'playback.previous',
          occurrenceId: song.occurrenceId,
        });
      case 'seek':
        // A position belongs to the song it was chosen on.
        return intent.occurrenceId === song.occurrenceId
          ? actionOf({
              kind: 'playback.seek',
              occurrenceId: song.occurrenceId,
              positionMs: intent.positionMs,
            })
          : refusal('The song changed before that position was sent.');
    }
  }
}

type BuiltAction =
  { action: CommandAction; reason: null } | { action: null; reason: string };

function actionOf(action: CommandAction): BuiltAction {
  return { action, reason: null };
}

// A playback change is tied to the song it was chosen on. Volume, modes and requests are not.
function isOccurrenceBound(action: CommandAction): boolean {
  return (
    action.kind !== 'playback.volume' &&
    action.kind !== 'playback.shuffle' &&
    action.kind !== 'playback.repeat' &&
    action.kind !== 'queue.enqueue' &&
    action.kind !== 'queue.play_next'
  );
}

function refusal(reason: string): BuiltAction {
  return { action: null, reason };
}
