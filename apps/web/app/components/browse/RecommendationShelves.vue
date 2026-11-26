<script setup lang="ts">
import { computed, onMounted, ref } from 'vue';
import type { RecommendationShelfItem, Song } from '~/lib/protocol/types';
import { shelfReasons, splitShelves, type Shelves } from '~/lib/shelves';
import { useHostStore } from '~/stores/host';
import { useSongActionsStore } from '~/stores/songActions';

// Suggestions the Host ranks from this Remote's taste. Playing one queues it like any other song.
const host = useHostStore();
const songActions = useSongActionsStore();

type LoadState = 'loading' | 'ready' | 'failed';

const state = ref<LoadState>('loading');
const shelves = ref<Shelves>({ forYou: [], roomBlend: [] });

const sections = computed(() =>
  [
    { key: 'for-you', title: 'For You', items: shelves.value.forYou },
    { key: 'room-blend', title: 'Room Blend', items: shelves.value.roomBlend },
  ].filter((section) => section.items.length > 0),
);

function load(): void {
  state.value = 'loading';

  const started = host.shelf((outcome) => {
    if (!outcome.ok) {
      state.value = 'failed';

      return;
    }

    shelves.value = splitShelves(outcome.value);
    state.value = 'ready';
  });

  if (started === null) state.value = 'failed';
}

function songOf(item: RecommendationShelfItem): Song {
  return {
    source: item.source,
    id: item.id,
    title: item.title,
    artist: item.artist,
    album: '',
    durationMs: null,
    artworkUrl: null,
  };
}

function queue(item: RecommendationShelfItem, action: 'next' | 'add'): void {
  void songActions.queue(songOf(item), action);
}

onMounted(load);
</script>

<template>
  <section class="shelves" aria-label="Suggestions">
    <p v-if="state === 'loading'" class="shelves-note">Finding suggestions.</p>
    <p v-else-if="state === 'failed'" class="shelves-note">
      Suggestions are not available from this Host.
    </p>
    <p v-else-if="sections.length === 0" class="shelves-note">
      Play a few songs, and suggestions will appear here.
    </p>
    <template v-else>
      <section v-for="section in sections" :key="section.key" class="shelf">
        <h3 class="shelf-title">{{ section.title }}</h3>
        <ul class="shelf-items">
          <li
            v-for="item in section.items"
            :key="item.source + item.id"
            class="shelf-item"
          >
            <div class="shelf-text">
              <span class="shelf-song">{{ item.title }}</span>
              <span class="shelf-artist">{{ item.artist }}</span>
              <span v-if="shelfReasons(item).length > 0" class="shelf-reasons">
                {{ shelfReasons(item).join(', ') }}
              </span>
            </div>
            <div class="shelf-actions">
              <button
                type="button"
                class="shelf-button"
                :aria-label="`Play ${item.title} next`"
                @click="queue(item, 'next')"
              >
                Play next
              </button>
              <button
                type="button"
                class="shelf-button"
                :aria-label="`Add ${item.title} to the queue`"
                @click="queue(item, 'add')"
              >
                Add
              </button>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </section>
</template>

<style scoped>
.shelves {
  display: grid;
  gap: 16px;
}

.shelves-note {
  margin: 0;
  color: var(--color-text-tertiary);
  font-size: 14px;
}

.shelf {
  display: grid;
  gap: 8px;
}

.shelf-title {
  margin: 0;
  font-family: var(--font-display);
  font-size: 18px;
  font-weight: 700;
}

.shelf-items {
  display: grid;
  gap: 8px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.shelf-item {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 8px 12px;
  border-radius: 12px;
  background: var(--color-fill);
}

.shelf-text {
  display: grid;
  min-width: 0;
}

.shelf-song {
  color: var(--color-text);
  font-weight: 600;
}

.shelf-artist,
.shelf-reasons {
  color: var(--color-text-secondary);
  font-size: 13px;
}

.shelf-actions {
  display: flex;
  gap: 8px;
}

.shelf-button {
  min-height: 36px;
  padding: 0 12px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill-strong);
  color: var(--color-text);
  font: inherit;
  font-size: 14px;
}
</style>
