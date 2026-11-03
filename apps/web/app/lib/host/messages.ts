import type { CommandResult } from '../protocol/types';

// User-facing text for a command that did not apply. An applied command needs no message; its new state arrives in
// the next snapshot.
export function describeCommandResult(result: CommandResult): string | null {
  switch (result.outcome) {
    case 'applied':
      return null;
    case 'expired':
      return 'That change expired before Cadenza Host applied it.';
    case 'unconfirmed':
      return 'Cadenza Host has not confirmed that change yet. It will not be sent again automatically.';
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
