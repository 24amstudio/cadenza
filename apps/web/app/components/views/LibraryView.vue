<script setup lang="ts">
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import PlaylistsPanel from '~/components/browse/PlaylistsPanel.vue';
import FavoritesPanel from '~/components/library/FavoritesPanel.vue';
import HistoryPanel from '~/components/library/HistoryPanel.vue';
import { useHostStore } from '~/stores/host';

type Tab = 'favorites' | 'history' | 'playlists';

const host = useHostStore();

// Playlists come from the Host, so the tab is there only when the Host can browse.
const tabs = computed<{ id: Tab; label: string }[]>(() => [
  { id: 'favorites', label: 'Favorites' },
  { id: 'history', label: 'History' },
  ...(host.supportsBrowse
    ? [{ id: 'playlists' as const, label: 'Playlists' }]
    : []),
]);

const chosen = ref<Tab>('favorites');

const selected = computed(() =>
  tabs.value.some((tab) => tab.id === chosen.value)
    ? chosen.value
    : 'favorites',
);

const tabButtons = useTemplateRef<HTMLButtonElement[]>('tab');

// The tab pattern moves between tabs with the arrow keys, and Home and End jump to the first and last.
function tabIndexAfter(key: string, index: number): number | null {
  switch (key) {
    case 'ArrowRight':
      return (index + 1) % tabs.value.length;
    case 'ArrowLeft':
      return (index + tabs.value.length - 1) % tabs.value.length;
    case 'Home':
      return 0;
    case 'End':
      return tabs.value.length - 1;
    default:
      return null;
  }
}

function onKeydown(event: KeyboardEvent): void {
  const index = tabs.value.findIndex((tab) => tab.id === selected.value);
  const next = tabIndexAfter(event.key, index);
  const tab = next === null ? undefined : tabs.value[next];

  if (next === null || tab === undefined) return;
  event.preventDefault();
  chosen.value = tab.id;
  void nextTick(() => tabButtons.value?.[next]?.focus());
}
</script>

<template>
  <section class="library" aria-labelledby="library-title">
    <header class="page-header">
      <h1 id="library-title">Library</h1>
    </header>

    <div
      class="tablist"
      role="tablist"
      aria-label="Library sections"
      @keydown="onKeydown"
    >
      <button
        v-for="tab in tabs"
        :id="`tab-${tab.id}`"
        ref="tab"
        :key="tab.id"
        class="segment"
        type="button"
        role="tab"
        :aria-selected="selected === tab.id"
        :aria-controls="`panel-${tab.id}`"
        :tabindex="selected === tab.id ? 0 : -1"
        @click="chosen = tab.id"
      >
        {{ tab.label }}
      </button>
    </div>

    <div
      v-show="selected === 'favorites'"
      id="panel-favorites"
      role="tabpanel"
      aria-labelledby="tab-favorites"
      tabindex="0"
    >
      <FavoritesPanel />
    </div>
    <div
      v-show="selected === 'history'"
      id="panel-history"
      role="tabpanel"
      aria-labelledby="tab-history"
      tabindex="0"
    >
      <HistoryPanel />
    </div>
    <div
      v-if="selected === 'playlists'"
      id="panel-playlists"
      role="tabpanel"
      aria-labelledby="tab-playlists"
      tabindex="0"
    >
      <PlaylistsPanel />
    </div>
  </section>
</template>

<style scoped>
.library {
  display: grid;
  gap: 16px;
  max-width: 760px;
  margin: 0 auto;
}

.page-header {
  padding: 0 12px;
}

h1 {
  font-family: var(--font-display);
  font-size: 32px;
  font-weight: 750;
  letter-spacing: -0.02em;
}

.tablist {
  display: grid;
  grid-auto-flow: column;
  grid-auto-columns: 1fr;
  gap: 2px;
  max-width: 440px;
  padding: 4px;
  border-radius: 12px;
  background: var(--color-fill);
}

.segment {
  min-height: 34px;
  border: 0;
  border-radius: 9px;
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 14px;
  font-weight: 600;
}

.segment[aria-selected='true'] {
  background: var(--color-surface);
  color: var(--color-text);
  box-shadow: 0 2px 8px -4px var(--color-shadow);
}

[role='tabpanel'] {
  padding-top: 8px;
}
</style>
