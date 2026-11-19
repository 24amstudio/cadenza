<script setup lang="ts">
import { computed } from 'vue';
import BrowseLink from '~/components/browse/BrowseLink.vue';
import ArtworkImage from '~/components/common/ArtworkImage.vue';
import FavoriteToggle from '~/components/library/FavoriteToggle.vue';
import { identityOf } from '~/lib/library/identity';
import { formatClock } from '~/lib/playback';
import type { Song } from '~/lib/protocol/types';
import { useHostStore } from '~/stores/host';
import { useSongActionsStore, type RowAction } from '~/stores/songActions';

// One song in a list. The two request buttons send it to Cadenza Host. The heart keeps it in this browser.
const props = defineProps<{ song: Song; note?: string }>();

const host = useHostStore();
const actions = useSongActionsStore();

const duration = computed(() =>
  props.song.durationMs === null ? '' : formatClock(props.song.durationMs),
);

const album = computed(() => props.song.album.trim());

function phaseOf(action: RowAction) {
  return actions.phaseOf(props.song, action);
}

function disabled(action: RowAction): boolean {
  if (!host.connected || identityOf(props.song) === null) return true;

  if (action === 'next' && !host.capabilities.includes('queue.play-next'))
    return true;

  return phaseOf(action) !== null;
}

// The pressed button names what it is doing, so the row says Preparing… or Adding… only on that action.
function label(action: RowAction): string {
  const phase = phaseOf(action);

  if (phase === 'preparing') return 'Preparing…';

  if (phase === 'sending') return 'Adding…';

  return action === 'next' ? 'Play next' : 'Add to queue';
}
</script>

<template>
  <li class="song-row">
    <ArtworkImage
      class="thumb"
      :url="song.artworkUrl"
      :alt="`${song.title} artwork`"
    />
    <div class="meta">
      <strong>{{ song.title }}</strong>
      <span><BrowseLink kind="artist" :song="song" /></span>
      <small v-if="album !== ''"
        ><BrowseLink kind="album" :song="song"
      /></small>
    </div>
    <div class="side">
      <span v-if="duration !== ''">{{ duration }}</span>
      <small v-if="note !== undefined">{{ note }}</small>
    </div>
    <div class="actions">
      <button
        class="request"
        :class="{ pending: phaseOf('next') !== null }"
        type="button"
        :aria-busy="phaseOf('next') !== null"
        :disabled="disabled('next')"
        @click="actions.queue(song, 'next')"
      >
        {{ label('next') }}
      </button>
      <button
        class="request"
        :class="{ pending: phaseOf('add') !== null }"
        type="button"
        :aria-busy="phaseOf('add') !== null"
        :disabled="disabled('add')"
        @click="actions.queue(song, 'add')"
      >
        {{ label('add') }}
      </button>
      <FavoriteToggle :song="song" />
    </div>
  </li>
</template>

<style scoped>
.song-row {
  display: grid;
  grid-template-columns: 48px minmax(0, 1fr) auto;
  align-items: center;
  gap: 6px 14px;
  padding: 10px 12px;
  border-radius: var(--radius-control);
  transition: background-color 160ms var(--ease-standard);
}

.song-row:hover {
  background: var(--color-fill);
}

.thumb {
  grid-row: span 2;
  width: 48px;
  height: 48px;
  border-radius: 7px;
}

.meta,
.side {
  display: grid;
  min-width: 0;
}

.meta {
  grid-column: 2;
  grid-row: 1;
}

.side {
  grid-column: 3;
  grid-row: 1;
  justify-items: end;
  text-align: right;
}

.meta strong,
.meta span,
.meta small,
.side span,
.side small {
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}

.meta strong {
  font-size: 15px;
  font-weight: 600;
}

.meta span,
.meta small,
.side span,
.side small {
  color: var(--color-text-secondary);
  font-size: 13px;
}

.meta small,
.side small {
  color: var(--color-text-tertiary);
  font-size: 12px;
}

.side span {
  font-variant-numeric: tabular-nums;
}

.actions {
  grid-column: 2 / -1;
  grid-row: 2;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

.request {
  min-height: 36px;
  padding: 0 14px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill);
  color: var(--color-text);
  font-size: 13px;
  font-weight: 560;
  white-space: nowrap;
  transition: background-color 160ms var(--ease-standard);
}

.request:hover:not(:disabled) {
  background: var(--color-fill-strong);
}

.request.pending {
  color: var(--color-accent);
  box-shadow: inset 0 0 0 2px var(--color-accent);
}

@media (min-width: 720px) {
  .song-row {
    grid-template-columns: 48px minmax(0, 1fr) auto auto;
  }

  .thumb {
    grid-row: auto;
  }

  .meta {
    grid-row: auto;
  }

  .side {
    grid-column: 3;
    grid-row: auto;
  }

  .actions {
    grid-column: 4;
    grid-row: auto;
    flex-wrap: nowrap;
    justify-content: flex-end;
  }
}
</style>
