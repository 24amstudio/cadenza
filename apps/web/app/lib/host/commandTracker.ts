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

// Tracks mutations that were sent and have no result yet. A command is sent once. If its answer does not come on a live
// link, or the link closes, it settles as unconfirmed and stays orphaned, so a late result is still reported and the
// reconnect can query it by its ID. It is never sent again.
export class CommandTracker {
  private readonly pending = new Map<string, PendingCommand>();
  private readonly orphaned = new Set<string>();
  private readonly schedule: Schedule;
  private readonly settleMs: number;

  constructor(schedule: Schedule, settleMs: number) {
    this.schedule = schedule;
    this.settleMs = settleMs;
  }

  track(commandId: string, sent: SentCommand): Promise<CommandResult> {
    return new Promise((resolve) => {
      const cancelSettle = this.schedule(
        () => this.settleUnanswered(commandId),
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

      return 'answered';
    }

    return this.orphaned.delete(result.commandId) ? 'late' : 'unknown';
  }

  orphanedIds(): string[] {
    return [...this.orphaned];
  }

  orphanAll(message: string): void {
    for (const [commandId, pending] of this.pending) {
      pending.cancelSettle();
      this.orphaned.add(commandId);
      pending.resolve(unconfirmedResult(commandId, message));
    }

    this.pending.clear();
  }

  private settleUnanswered(commandId: string): void {
    const pending = this.pending.get(commandId);

    if (pending === undefined) return;
    this.pending.delete(commandId);
    this.orphaned.add(commandId);
    pending.resolve(
      unconfirmedResult(
        commandId,
        'Cadenza Host has not confirmed this change yet.',
      ),
    );
  }
}
