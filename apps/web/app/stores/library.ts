import { defineStore } from 'pinia';
import { computed, shallowRef, watch } from 'vue';
import { randomUuid } from '~/lib/host/ids';
import { songKey } from '~/lib/library/identity';
import { Favorites } from '~/lib/library/favorites';
import { History, type HistoryEntry } from '~/lib/library/history';
import { browserLocalStorage, keyValueStore } from '~/lib/library/keyValue';
import type { Song } from '~/lib/protocol/types';
import { useHostStore } from '~/stores/host';
import { useNoticesStore } from '~/stores/notices';

// Favorites and history stay in this browser. When storage is blocked, they still work for this visit.
export const useLibraryStore = defineStore('library', () => {
  const host = useHostStore();
  const notices = useNoticesStore();
  const store = keyValueStore(browserLocalStorage);
  const favoriteBook = new Favorites(store);
  const historyBook = new History(store, randomUuid);
  const favorites = shallowRef<Song[]>(favoriteBook.list());
  const history = shallowRef<HistoryEntry[]>(historyBook.list());
  const favoriteKeys = computed(() => new Set(favorites.value.map(songKey)));

  function isFavorite(song: Song): boolean {
    return favoriteKeys.value.has(songKey(song));
  }

  function toggleFavorite(song: Song): void {
    const saved = favoriteBook.toggle(song);

    favorites.value = favoriteBook.list();
    notices.show(saved ? 'Saved to Favorites' : 'Removed from Favorites');
  }

  function recordRequested(song: Song): void {
    historyBook.recordRequested(song, Date.now());
    history.value = historyBook.list();
  }

  function clearHistory(): void {
    historyBook.clear();
    history.value = historyBook.list();
    notices.show('History cleared');
  }

  // A play is recorded once per occurrence, when this browser sees it playing while connected. The first snapshot counts
  // too, so a song that was already playing when the page connected is kept.
  watch(
    [
      () => host.current?.occurrenceId ?? null,
      () => host.isPlaying,
      () => host.connected,
    ],
    ([occurrenceId, playing, connected]) => {
      const song = host.current?.song;

      if (occurrenceId === null || song === undefined || !playing || !connected)
        return;

      if (historyBook.recordPlayed(song, occurrenceId, Date.now()))
        history.value = historyBook.list();
    },
    { immediate: true },
  );

  return {
    favorites,
    history,
    isFavorite,
    toggleFavorite,
    recordRequested,
    clearHistory,
  };
});
