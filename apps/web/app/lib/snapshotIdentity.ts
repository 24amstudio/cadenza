import type { QueueEntry, Snapshot, Song } from './protocol/types';

// A new state frame arrives for every Host change, so most of what it carries is what the page already holds. Handing
// the unchanged song and queue back as the same objects keeps everything that reads them from running again.
export function reuseUnchanged(
  previous: Snapshot | null,
  next: Snapshot,
): Snapshot {
  if (previous === null) return next;

  const queue = sameQueue(previous.queue, next.queue)
    ? previous.queue
    : next.queue;

  const before = previous.current;
  const after = next.current;

  const current =
    before !== null &&
    after !== null &&
    before.occurrenceId === after.occurrenceId &&
    sameSong(before.song, after.song)
      ? { ...after, song: before.song }
      : after;

  return queue === next.queue && current === next.current
    ? next
    : { ...next, queue, current };
}

function sameQueue(first: QueueEntry[], second: QueueEntry[]): boolean {
  return (
    first.length === second.length &&
    first.every((entry, index) => {
      const other = second[index];

      return (
        other !== undefined &&
        entry.id === other.id &&
        entry.requesterName === other.requesterName &&
        entry.estimatedWaitMs === other.estimatedWaitMs &&
        sameSong(entry.song, other.song)
      );
    })
  );
}

function sameSong(first: Song, second: Song): boolean {
  return (
    first.source === second.source &&
    first.id === second.id &&
    first.title === second.title &&
    first.artist === second.artist &&
    first.album === second.album &&
    first.durationMs === second.durationMs &&
    first.artworkUrl === second.artworkUrl
  );
}
