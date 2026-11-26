import { sharedLocalLog } from '../../app/lib/host/localLog';

// The shared log outlives each test, and a report carries only a small batch. A test that reads the log starts from an
// empty one, so the entries it expects are the newest ones held.
export function emptySharedLog(): void {
  const log = sharedLocalLog();

  while (log.pending().length > 0) {
    log.forget(log.pending().map((entry) => entry.id));
  }
}
