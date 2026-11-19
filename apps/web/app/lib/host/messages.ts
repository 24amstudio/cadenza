import type { CommandResult } from '../protocol/types';

// User-facing text for a command that did not apply. An applied command needs no message; its new state arrives in
// the next snapshot.
export function describeCommandResult(result: CommandResult): string | null {
  switch (result.outcome) {
    case 'applied':
      return null;
    case 'expired':
      return 'The request expired before it could be applied.';
    case 'unconfirmed':
      return 'Music may still apply this request. Cadenza is checking.';
    case 'rejected':
      return describeRejection(result.errorCode);
  }
}

function describeRejection(errorCode: string | null): string {
  switch (errorCode) {
    case 'stale_revision':
    case 'stale_occurrence':
    case 'invalid_anchor':
      return 'Playback changed on Cadenza Host. Try again.';
    case 'invalid_deadline':
      return 'This browser and Cadenza Host disagree about the time. Try again in a moment.';
    case 'busy':
      return 'Cadenza Host is busy with another change. Try again in a moment.';
    case 'music_permission':
      return 'Cadenza Host cannot control Music. Check its Automation access.';
    case 'music_unavailable':
    case 'native_queue_unavailable':
      return 'Music is unavailable on Cadenza Host.';
    case 'forbidden':
      return 'Cadenza Host does not allow that change right now.';
    case 'unavailable':
      return 'Cadenza Host is not connected.';
    default:
      return 'Cadenza Host could not apply that change.';
  }
}
