<script setup lang="ts">
import { computed } from 'vue';
import BrowseCard from '~/components/browse/BrowseCard.vue';
import SongRow from '~/components/library/SongRow.vue';
import type { BrowseItem, BrowseSection } from '~/lib/protocol/types';

const props = defineProps<{ section: BrowseSection }>();

type Collection = Exclude<BrowseItem, { type: 'song' }>;

// Songs list as rows with the usual request actions. Albums, artists and playlists list as a grid of cards.
const songs = computed(() =>
  props.section.items.flatMap((item) =>
    item.type === 'song' ? [item.song] : [],
  ),
);

const collections = computed(() =>
  props.section.items.filter(
    (item): item is Collection => item.type !== 'song',
  ),
);
</script>

<template>
  <section class="browse-section" :aria-label="section.title">
    <h2>{{ section.title }}</h2>
    <ol v-if="songs.length > 0" class="songs">
      <SongRow
        v-for="(song, index) in songs"
        :key="`${song.id}-${index}`"
        :song="song"
      />
    </ol>
    <ul v-if="collections.length > 0" class="cards">
      <BrowseCard
        v-for="item in collections"
        :key="`${item.type}-${item.id}`"
        :item="item"
      />
    </ul>
  </section>
</template>

<style scoped>
.browse-section {
  display: grid;
  gap: 10px;
}

h2 {
  padding: 0 12px;
  font-family: var(--font-display);
  font-size: 22px;
  font-weight: 700;
  letter-spacing: -0.015em;
}

.songs,
.cards {
  margin: 0;
  padding: 0;
  list-style: none;
}

.songs {
  display: grid;
  gap: 2px;
}

.cards {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 6px;
}

@media (max-width: 719px) {
  .cards {
    grid-template-columns: repeat(auto-fill, minmax(124px, 1fr));
  }
}
</style>
