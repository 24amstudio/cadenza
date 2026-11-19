import type { CommandResult } from '../protocol/types';
import { traceEvent } from './trace';
import type { Schedule } from './waiters';

// What was sent, kept for the trace of a command that did not apply.
export interface SentCommand {
  kind: string;
  expectedRevision: number;
  windowMs: number;
  roundTripMs: number | null;
}

interface PendingCommand {
  resolve: (result: CommandResult) => void;
  cancelSettle: () => void;
  sent: SentCommand;
}

// How long the Host gets to answer a command.status question before the outcome is called unknown.
const statusWaitMs = 1_500;

// An unconfirmed command is asked about again at these delays, so its late outcome is found without waiting for a reconnect.
const recheckDelaysMs = [1_500, 4_000];

// Commands the Host never accounted for are forgotten, oldest first, so a long session does not keep every one.
const orphanLimit = 32;

export type ResultKind = 'answered' | 'late' | 'unknown';

export function unconfirmedResult(
  commandId: string,
  message: string,
): CommandResult {
  return {
    commandId,
    outcome: 'unconfirmed',
    revision: 0,
    message,
    errorCode: 'outcome_unknown',
  };
}

export function unavailableResult(): CommandResult {
  return {
    commandId: '',
    outcome: 'rejected',
    revision: 0,
    message: 'Cadenza Host is not connected.',
    errorCode: 'unavailable',
  };
}

// Tracks mutations that were sent and have no result yet. A command is sent once and never sent again.
//
// A command whose answer is late is not called unknown at once. After settleMs the Host is asked with command.status,
// which reports the receipt it holds. Only a Host that says the outcome is unknown, or one that does not answer that
// question either, leaves the command unconfirmed. An unconfirmed command stays orphaned, so its final result is still
// reported, and it is asked about again a few times while the link is up. A reconnect queries it by its ID.
export class CommandTracker {
  private readonly pending = new Map<string, PendingCommand>();
  private readonly orphaned = new Set<string>();
  private readonly schedule: Schedule;
  private readonly settleMs: number;
  // Sends command.status over the live link. False means no link is up and nothing was sent.
  private readonly queryStatus: (commandId: string) => boolean;

  constructor(
    schedule: Schedule,
    settleMs: number,
    queryStatus: (commandId: string) => boolean,
  ) {
    this.schedule = schedule;
    this.settleMs = settleMs;
    this.queryStatus = queryStatus;
  }

  track(commandId: string, sent: SentCommand): Promise<CommandResult> {
    return new Promise((resolve) => {
      const cancelSettle = this.schedule(
        () => this.askHost(commandId),
        this.settleMs,
      );

      this.pending.set(commandId, { resolve, cancelSettle, sent });
    });
  }

  // What was sent for a command that is still waiting for its result.
  sentFor(commandId: string): SentCommand | null {
    return this.pending.get(commandId)?.sent ?? null;
  }

  // An error frame that names a pending command means the Host refused it before anything ran, so it settles now as
  // rejected instead of at its deadline. The Host sends no revision with a refusal. False when no pending command has
  // that ID, and the error is handled as it always was.
  refuse(error: {
    commandId: string | null;
    errorCode: string;
    message: string;
  }): boolean {
    const { commandId } = error;

    const pending =
      commandId === null ? undefined : this.pending.get(commandId);

    if (commandId === null || pending === undefined) return false;

    traceEvent(`command ${pending.sent.kind} rejected`, {
      errorCode: error.errorCode,
      message: error.message,
      expectedRevision: pending.sent.expectedRevision,
      windowMs: pending.sent.windowMs,
      roundTripMs: pending.sent.roundTripMs,
    });
    this.receive({
      commandId,
      outcome: 'rejected',
      revision: 0,
      message: error.message,
      errorCode: error.errorCode,
    });

    return true;
  }

  receive(result: CommandResult): ResultKind {
    const pending = this.pending.get(result.commandId);

    if (pending !== undefined) {
      this.pending.delete(result.commandId);
      pending.cancelSettle();
      pending.resolve(result);

      if (result.outcome === 'unconfirmed') this.orphan(result.commandId, true);

      return 'answered';
    }

    if (!this.orphaned.has(result.commandId)) return 'unknown';

    // Still unknown, so the command stays orphaned and its real outcome is still reported when it arrives.
    if (result.outcome === 'unconfirmed') return 'unknown';
    this.orphaned.delete(result.commandId);

    return 'late';
  }

  orphanedIds(): string[] {
    return [...this.orphaned];
  }

  orphanAll(message: string): void {
    for (const [commandId, pending] of this.pending) {
      pending.cancelSettle();
      this.orphan(commandId, false);
      pending.resolve(unconfirmedResult(commandId, message));
    }

    this.pending.clear();
  }

  // The command's time is up. The Host's receipt decides, so the answer to this question settles the command.
  private askHost(commandId: string): void {
    const pending = this.pending.get(commandId);

    if (pending === undefined) return;

    if (!this.queryStatus(commandId)) {
      this.settleUnanswered(commandId);

      return;
    }

    pending.cancelSettle = this.schedule(
      () => this.settleUnanswered(commandId),
      statusWaitMs,
    );
  }

  private settleUnanswered(commandId: string): void {
    const pending = this.pending.get(commandId);

    if (pending === undefined) return;
    this.pending.delete(commandId);
    this.orphan(commandId, true);
    pending.resolve(
      unconfirmedResult(
        commandId,
        'Cadenza Host has not confirmed this change yet.',
      ),
    );
  }

  private orphan(commandId: string, recheck: boolean): void {
    this.orphaned.add(commandId);

    for (const stale of [...this.orphaned].slice(0, -orphanLimit)) {
      this.orphaned.delete(stale);
    }

    if (recheck) this.recheck(commandId, 0);
  }

  private recheck(commandId: string, index: number): void {
    const delayMs = recheckDelaysMs[index];

    if (delayMs === undefined) return;
    this.schedule(() => {
      if (!this.orphaned.has(commandId) || !this.queryStatus(commandId)) return;
      this.recheck(commandId, index + 1);
    }, delayMs);
  }
}
