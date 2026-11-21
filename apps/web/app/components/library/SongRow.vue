<script setup lang="ts">
import { computed, ref } from 'vue';
import BrowseLink from '~/components/browse/BrowseLink.vue';
import AppIcon from '~/components/common/AppIcon.vue';
import ArtworkImage from '~/components/common/ArtworkImage.vue';
import FavoriteToggle from '~/components/library/FavoriteToggle.vue';
import { identityOf } from '~/lib/library/identity';
import { formatClock } from '~/lib/playback';
import type { Song } from '~/lib/protocol/types';
import { useHostStore } from '~/stores/host';
import { useSongActionsStore, type RowAction } from '~/stores/songActions';

// One song in a list. Tapping the artwork reveals Play now; the buttons below queue the song next or last. The heart
// keeps it in this browser.
const props = defineProps<{ song: Song; note?: string }>();

const host = useHostStore();
const actions = useSongActionsStore();

const armed = ref(false);

const requestActions: RowAction[] = ['next', 'add'];

const requestLabels: Record<RowAction, string> = {
  now: 'Play now',
  next: 'Play next',
  add: 'Add to queue',
};

const duration = computed(() =>
  props.song.durationMs === null ? '' : formatClock(props.song.durationMs),
);

const album = computed(() => props.song.album.trim());

function phaseOf(action: RowAction) {
  return actions.phaseOf(props.song, action);
}

function disabled(action: RowAction): boolean {
  if (!host.connected || identityOf(props.song) === null) return true;

  // Cadenza Host refuses every queue change until it has read Music's queue, so the button waits for that read.
  if (host.snapshot?.synchronized !== true) return true;

  if (action === 'next' && !host.capabilities.includes('queue.play-next'))
    return true;

  return phaseOf(action) !== null;
}

// Why a request is unavailable, so a greyed-out button says what to wait for instead of looking broken.
function unavailableReason(action: RowAction): string | null {
  if (!host.connected) return 'Connect to Cadenza Host to request songs.';

  if (identityOf(props.song) === null)
    return 'This song has no ID that Cadenza Host can queue.';

  if (host.snapshot?.synchronized !== true)
    return (
      host.snapshot?.issue ??
      "Cadenza Host is reading Music's queue. Requests resume when it finishes."
    );

  if (action === 'next' && !host.capabilities.includes('queue.play-next'))
    return 'This Cadenza Host cannot play a song next.';

  return null;
}

// The pressed button names what it is doing, so the row says Preparing… or Adding… only on that action.
function label(action: RowAction): string {
  const phase = phaseOf(action);

  if (phase === 'preparing') return 'Preparing…';

  if (phase === 'sending') return action === 'now' ? 'Starting…' : 'Adding…';

  return requestLabels[action];
}
</script>

<template>
  <li class="song-row" :class="{ armed }">
    <div class="art">
      <button
        class="art-toggle"
        type="button"
        :aria-expanded="armed"
        :aria-label="`Show play for ${song.title}`"
        @click="armed = !armed"
      >
        <ArtworkImage
          class="thumb"
          :url="song.artworkUrl"
          :alt="`${song.title} artwork`"
        />
      </button>
      <button
        class="play"
        type="button"
        :aria-label="`${label('now')}: ${song.title}`"
        :aria-busy="phaseOf('now') !== null"
        :class="{ pending: phaseOf('now') !== null }"
        :disabled="disabled('now')"
        @click="actions.queue(song, 'now')"
      >
        <AppIcon name="play" />
      </button>
    </div>
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
        v-for="action in requestActions"
        :key="action"
        class="request"
        :class="{ pending: phaseOf(action) !== null }"
        type="button"
        :aria-busy="phaseOf(action) !== null"
        :disabled="disabled(action)"
        :title="
          disabled(action)
            ? (unavailableReason(action) ?? undefined)
            : undefined
        "
        @click="actions.queue(song, action)"
      >
        {{ label(action) }}
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

.art {
  position: relative;
  grid-row: span 2;
  width: 48px;
  height: 48px;
}

.art-toggle {
  display: block;
  width: 100%;
  height: 100%;
  padding: 0;
  border: 0;
  border-radius: 7px;
  background: none;
  cursor: pointer;
}

.thumb {
  width: 100%;
  height: 100%;
  border-radius: 7px;
}

.play {
  position: absolute;
  top: 50%;
  left: 50%;
  display: grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border: 0;
  border-radius: 50%;
  background: var(--color-accent);
  color: var(--color-on-accent);
  opacity: 0;
  transform: translate(-50%, -50%);
  transition: opacity 160ms var(--ease-standard);
}

.play :deep(svg) {
  width: 16px;
  height: 16px;
}

.song-row:hover .play,
.song-row.armed .play,
.play:focus-visible,
.play.pending {
  opacity: 1;
}

.play:disabled:not(.pending) {
  opacity: 0;
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

  .art {
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
