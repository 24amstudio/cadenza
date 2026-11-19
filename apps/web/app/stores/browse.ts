import { defineStore } from 'pinia';
import { computed, shallowRef, watch } from 'vue';
import { browseKey, browseTtlMs, describeBrowseFailure } from '~/lib/browse';
import type { BrowsePage, BrowseRequest } from '~/lib/protocol/types';
import { useHostStore } from '~/stores/host';

export interface BrowseEntry {
  // The last page the Host sent. It stays on screen while a newer one loads.
  page: BrowsePage | null;
  status: 'loading' | 'done' | 'failed';
  message: string | null;
  loadedAtMs: number;
}

// Pages are kept briefly so going back and forth does not ask the Host again. The oldest are dropped past this count.
const entryLimit = 24;

export const useBrowseStore = defineStore('browse', () => {
  const host = useHostStore();
  const entries = shallowRef<ReadonlyMap<string, BrowseEntry>>(new Map());
  // The Host request that is answering each page, so leaving the page can cancel it.
  const inFlight = new Map<string, string>();

  function entryFor(request: BrowseRequest): BrowseEntry | null {
    return entries.value.get(browseKey(request)) ?? null;
  }

  function put(key: string, entry: BrowseEntry): void {
    const next = new Map(entries.value);

    next.delete(key);
    next.set(key, entry);

    for (const stale of next.keys()) {
      if (next.size <= entryLimit) break;

      if (!inFlight.has(stale)) next.delete(stale);
    }

    entries.value = next;
  }

  // Asks the Host for a page unless a fresh one is held or the request is already running.
  function load(request: BrowseRequest, force = false): void {
    const key = browseKey(request);
    const held = entries.value.get(key) ?? null;

    if (inFlight.has(key)) return;

    if (
      !force &&
      held !== null &&
      held.page !== null &&
      held.status === 'done' &&
      Date.now() - held.loadedAtMs < browseTtlMs(request.kind)
    ) {
      return;
    }

    const requestId = host.browse(request, (outcome) => {
      inFlight.delete(key);

      if (outcome.ok) {
        const done: BrowseEntry = {
          page: outcome.value,
          status: 'done',
          message: null,
          loadedAtMs: Date.now(),
        };

        put(key, done);
        // The same page opened by its ID, from a card, finds this result.
        put(
          browseKey({ kind: outcome.value.kind, id: outcome.value.id }),
          done,
        );

        return;
      }

      put(key, {
        page: held?.page ?? null,
        status: 'failed',
        message: describeBrowseFailure(outcome.errorCode, outcome.message),
        loadedAtMs: held?.loadedAtMs ?? 0,
      });
    });

    if (requestId === null) {
      put(key, {
        page: held?.page ?? null,
        status: 'failed',
        message: describeBrowseFailure('unavailable', ''),
        loadedAtMs: held?.loadedAtMs ?? 0,
      });

      return;
    }

    inFlight.set(key, requestId);
    put(key, {
      page: held?.page ?? null,
      status: 'loading',
      message: null,
      loadedAtMs: held?.loadedAtMs ?? 0,
    });
  }

  // The page was left, so the Host stops working on it. A page already held stays as it was.
  function release(request: BrowseRequest): void {
    const key = browseKey(request);
    const requestId = inFlight.get(key);

    if (requestId === undefined) return;
    inFlight.delete(key);
    host.abortBrowse(requestId);

    const held = entries.value.get(key);
    const next = new Map(entries.value);

    if (held === undefined || held.page === null) next.delete(key);
    else next.set(key, { ...held, status: 'done' });
    entries.value = next;
  }

  return { entryFor, load, release };
});

// One page on screen: asks the Host when the page opens or its request changes, cancels the request when the page is
// left, and asks again once the link returns after a failure.
export function useBrowseRequest(request: () => BrowseRequest) {
  const browse = useBrowseStore();
  const host = useHostStore();
  const entry = computed(() => browse.entryFor(request()));

  watch(
    () => browseKey(request()),
    (_key, _previous, onCleanup) => {
      const opened = request();

      browse.load(opened);
      onCleanup(() => browse.release(opened));
    },
    { immediate: true },
  );

  watch(
    () => host.connected,
    (connected) => {
      if (connected && entry.value?.status === 'failed') {
        browse.load(request(), true);
      }
    },
  );

  return { entry, retry: () => browse.load(request(), true) };
}
