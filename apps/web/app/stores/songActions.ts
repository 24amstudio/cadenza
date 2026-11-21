import { defineStore } from 'pinia';
import { shallowRef } from 'vue';
import { describeCommandResult } from '~/lib/host/messages';
import type { RequestOutcome } from '~/lib/host/songRequests';
import { identityOf, songKey } from '~/lib/library/identity';
import type {
  CommandResult,
  QueueActionKind,
  Song,
  SongIdentity,
} from '~/lib/protocol/types';
import { useHostStore } from '~/stores/host';
import { useLibraryStore } from '~/stores/library';
import { useNoticesStore } from '~/stores/notices';

// The three request buttons on a song row.
export type RowAction = 'now' | 'next' | 'add';

const queueKindOf: Record<RowAction, QueueActionKind> = {
  now: 'queue.play_now',
  next: 'queue.play_next',
  add: 'queue.enqueue',
};

// Preparing comes first when the Host has not seen the song in this session. Sending follows once it is prepared.
export type RowPhase = 'preparing' | 'sending';

export const useSongActionsStore = defineStore('songActions', () => {
  const host = useHostStore();
  const library = useLibraryStore();
  const notices = useNoticesStore();
  // Songs the Host has prepared, for the Host process named by preparedEpoch. A new process forgets them.
  const prepared = new Set<string>();
  let preparedEpoch: string | null = null;
  // The preparation under way for each song, shared by requests that arrive while it runs.
  const preparing = new Map<string, Promise<RequestOutcome<null>>>();
  const phases = shallowRef<Map<string, RowPhase>>(new Map());

  function phaseOf(song: Song, action: RowAction): RowPhase | null {
    return phases.value.get(rowKey(song, action)) ?? null;
  }

  // Queues the song for the next place or the end of the queue. A press while that action is busy does nothing, so the
  // same request is never sent twice.
  // A request that the Host answers with song_not_ready is prepared once more and sent again, one time only. The Host
  // drops a song's preparation when Music's search moves on, while this page still remembers it as prepared.
  async function queue(
    song: Song,
    action: RowAction,
    retry = false,
  ): Promise<void> {
    const identity = identityOf(song);
    const key = rowKey(song, action);

    if (identity === null) {
      notices.show(
        'This song has no Apple Music or library ID, so Cadenza Host cannot queue it.',
      );

      return;
    }

    if (phases.value.has(key)) return;

    setPhase(key, 'preparing');
    forgetOnNewEpoch();
    const outcome = await prepare(identity, song);

    if (!outcome.ok) {
      setPhase(key, null);
      notices.show(outcome.message);

      return;
    }

    setPhase(key, 'sending');

    if (!retry) library.recordRequested(song);

    host.queueSong(identity, queueKindOf[action], (result) => {
      setPhase(key, null);

      if (!retry && result?.errorCode === 'song_not_ready') {
        prepared.delete(`${identity.source}:${identity.id}`);
        void queue(song, action, true);

        return;
      }

      const message = queuedMessage(action, result);

      if (message !== null) notices.show(message);
    });
  }

  function prepare(
    identity: SongIdentity,
    song: Song,
  ): Promise<RequestOutcome<null>> {
    const id = `${identity.source}:${identity.id}`;

    if (prepared.has(id))
      return Promise.resolve<RequestOutcome<null>>({ ok: true, value: null });

    const running = preparing.get(id);

    if (running !== undefined) return running;

    const request = new Promise<RequestOutcome<null>>((resolve) => {
      const sent = host.prepareSong(identity, resolve, song);

      if (!sent)
        resolve({
          ok: false,
          errorCode: 'unavailable',
          message: 'Cadenza Host is not connected.',
        });
    }).then((outcome) => {
      preparing.delete(id);

      if (outcome.ok) prepared.add(id);

      return outcome;
    });

    preparing.set(id, request);

    return request;
  }

  function forgetOnNewEpoch(): void {
    const epoch = host.snapshot?.hostEpoch ?? null;

    if (epoch === preparedEpoch) return;
    prepared.clear();
    preparedEpoch = epoch;
  }

  function setPhase(key: string, phase: RowPhase | null): void {
    const next = new Map(phases.value);

    if (phase === null) next.delete(key);
    else next.set(key, phase);
    phases.value = next;
  }

  return { phaseOf, queue };
});

function rowKey(song: Song, action: RowAction): string {
  return `${songKey(song)}|${action}`;
}

// What the person hears when a request is answered. null means nothing was sent, and the queue has already said why.
function queuedMessage(
  action: RowAction,
  result: CommandResult | null,
): string | null {
  if (result === null) return null;

  if (result.outcome !== 'applied') return describeCommandResult(result);

  if (action === 'now') return 'Playing now';

  return action === 'next' ? 'Will play next' : 'Added to queue';
}
