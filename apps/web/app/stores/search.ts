import { defineStore } from 'pinia';
import { shallowRef } from 'vue';
import type { SearchScope } from '~/lib/protocol/types';
import {
  SearchSession,
  emptySearchState,
  type SearchState,
} from '~/lib/search/searchSession';
import { useHostStore } from '~/stores/host';

// The Host capability each scope needs. A Host without it cannot answer that scope.
const scopeCapability: Record<SearchScope, string> = {
  catalog: 'catalog.public-web',
  library: 'library',
};

export const useSearchStore = defineStore('search', () => {
  const host = useHostStore();
  const state = shallowRef<SearchState>(emptySearchState());

  const session = new SearchSession(
    {
      search: (query, scope, settle) => host.searchSongs(query, scope, settle),
      suggest: (query, settle) => host.suggestSongs(query, settle),
      cancel: (requestId) => host.cancelSongRequest(requestId),
      schedule: scheduleTask,
    },
    (next) => {
      state.value = next;
    },
  );

  function scopeSupported(scope: SearchScope): boolean {
    return host.capabilities.includes(scopeCapability[scope]);
  }

  function setQuery(query: string): void {
    session.setQuery(query);
  }

  function submit(): void {
    session.submit();
  }

  function setScope(scope: SearchScope): void {
    session.setScope(scope);
  }

  function chooseTerm(term: string): void {
    session.chooseTerm(term);
  }

  function clear(): void {
    session.clear();
  }

  return {
    state,
    scopeSupported,
    setQuery,
    submit,
    setScope,
    chooseTerm,
    clear,
  };
});

function scheduleTask(callback: () => void, delayMs: number): () => void {
  const handle = setTimeout(callback, delayMs);

  return () => clearTimeout(handle);
}
