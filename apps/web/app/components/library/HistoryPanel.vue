<script setup lang="ts">
import { computed, nextTick, ref, useTemplateRef } from 'vue';
import EmptyState from '~/components/common/EmptyState.vue';
import SongRow from '~/components/library/SongRow.vue';
import type { HistoryEntry } from '~/lib/library/history';
import { formatHistoryTime, groupHistory } from '~/lib/library/historyGroups';
import { summarizeHistory } from '~/lib/library/historySummary';
import { formatListeningTime } from '~/lib/playback';
import { useLibraryStore } from '~/stores/library';

const library = useLibraryStore();
const groups = computed(() => groupHistory(library.history, new Date()));
const summary = computed(() => summarizeHistory(library.history));
const dialog = useTemplateRef<HTMLDialogElement>('dialog');
const clearButton = useTemplateRef<HTMLButtonElement>('clearButton');

const noteFor = (entry: HistoryEntry): string =>
  `${entry.kind === 'played' ? 'Played' : 'Requested'} ${formatHistoryTime(entry.at)}`;

function confirmClear(): void {
  library.clearHistory();
  dialog.value?.close();
}

// Closing the dialog returns focus to the button that opened it, so keyboard users keep their place.
async function onDialogClosed(): Promise<void> {
  await nextTick();
  clearButton.value?.focus();
}
</script>

<template>
  <EmptyState
    v-if="library.history.length === 0"
    icon="now"
    title="Nothing in history yet"
    body="Songs you request, and songs that play while this browser is connected, appear here, newest first."
  />
  <div v-else class="history">
    <div class="history-toolbar">
      <button
        ref="clearButton"
        class="text-button"
        type="button"
        @click="dialog?.showModal()"
      >
        Clear history
      </button>
    </div>

    <section class="summary" aria-labelledby="history-summary-title">
      <h2 id="history-summary-title">Listening</h2>
      <dl class="metrics">
        <div class="metric primary">
          <dt>Total play time</dt>
          <dd>{{ formatListeningTime(summary.songTimeMs) }}</dd>
        </div>
        <div class="metric">
          <dt>Plays</dt>
          <dd>{{ summary.plays }}</dd>
        </div>
        <div class="metric">
          <dt>Songs</dt>
          <dd>{{ summary.songs }}</dd>
        </div>
        <div class="metric">
          <dt>Artists</dt>
          <dd>{{ summary.artists }}</dd>
        </div>
      </dl>
      <p class="note">
        Each play counts the full length of its song. This browser keeps its
        last
        {{ library.history.length }} entries, so older plays are not included.
      </p>
      <ol v-if="summary.topArtists.length > 0" class="top-artists">
        <li v-for="artist in summary.topArtists" :key="artist.name">
          <span>{{ artist.name }}</span>
          <small
            >{{ artist.plays }}
            {{ artist.plays === 1 ? 'play' : 'plays' }}</small
          >
        </li>
      </ol>
    </section>

    <section
      v-for="group in groups"
      :key="group.key"
      class="day"
      :aria-labelledby="`day-${group.key}`"
    >
      <h2 :id="`day-${group.key}`">{{ group.label }}</h2>
      <ul class="song-list">
        <SongRow
          v-for="entry in group.entries"
          :key="entry.id"
          :song="entry.song"
          :note="noteFor(entry)"
        />
      </ul>
    </section>
  </div>

  <dialog
    ref="dialog"
    class="confirm-dialog"
    aria-labelledby="clear-history-title"
    aria-describedby="clear-history-body"
    @close="onDialogClosed"
  >
    <h2 id="clear-history-title">Clear history?</h2>
    <p id="clear-history-body">
      This removes every history entry in this browser. Favorites are not
      changed.
    </p>
    <form method="dialog" class="dialog-actions">
      <button class="dialog-button" type="submit" autofocus>
        Keep history
      </button>
      <button class="dialog-button danger" type="button" @click="confirmClear">
        Clear history
      </button>
    </form>
  </dialog>
</template>

<style scoped>
.history {
  display: grid;
  gap: 20px;
}

.history-toolbar {
  display: flex;
  justify-content: flex-end;
  padding: 0 12px;
}

.summary {
  display: grid;
  gap: 14px;
  padding: 18px;
  border-radius: var(--radius-panel);
  background: var(--color-fill);
}

.summary h2 {
  color: var(--color-text-secondary);
  font-size: 13px;
  font-weight: 650;
}

.metrics {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  margin: 0;
}

.metric {
  display: grid;
  gap: 4px;
  padding: 12px 14px;
  border-radius: var(--radius-control);
  background: var(--color-surface);
}

.metric.primary {
  grid-column: 1 / -1;
}

.metric dt {
  color: var(--color-text-secondary);
  font-size: 13px;
}

.metric dd {
  margin: 0;
  font-family: var(--font-display);
  font-size: 26px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}

.metric.primary dd {
  font-size: 34px;
}

.note {
  color: var(--color-text-tertiary);
  font-size: 12px;
  line-height: 1.4;
}

.top-artists {
  display: grid;
  gap: 6px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.top-artists li {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  font-size: 14px;
}

.top-artists small {
  color: var(--color-text-secondary);
  font-variant-numeric: tabular-nums;
}

.day {
  display: grid;
  gap: 6px;
}

.day h2 {
  padding: 0 12px;
  color: var(--color-text-secondary);
  font-size: 13px;
  font-weight: 650;
}

.confirm-dialog {
  width: min(calc(100vw - 40px), 380px);
  padding: 28px;
  border: 0;
  border-radius: var(--radius-panel);
  background: var(--color-surface);
  color: var(--color-text);
  box-shadow: 0 30px 60px -30px var(--color-shadow);
}

.confirm-dialog::backdrop {
  background: rgb(0 0 0 / 0.4);
}

.confirm-dialog h2 {
  font-size: 19px;
  font-weight: 700;
}

.confirm-dialog p {
  margin-top: 10px;
  color: var(--color-text-secondary);
  line-height: 1.45;
}

.dialog-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 10px;
  margin-top: 22px;
}

.dialog-button {
  min-height: 40px;
  padding: 0 16px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill);
  color: var(--color-text);
  font-size: 14px;
  font-weight: 600;
}

.dialog-button.danger {
  background: var(--color-danger);
  color: var(--color-canvas);
}
</style>
