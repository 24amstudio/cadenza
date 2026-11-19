<script setup lang="ts">
import ArtworkImage from '~/components/common/ArtworkImage.vue';
import type { BrowseItem } from '~/lib/protocol/types';
import { useUiStore } from '~/stores/ui';

type Collection = Exclude<BrowseItem, { type: 'song' }>;

// An album, artist or playlist in a grid. Artists are round, as in Music.
const props = defineProps<{ item: Collection }>();

const ui = useUiStore();

function open(): void {
  ui.openBrowse({
    request: { kind: props.item.type, id: props.item.id },
    title: props.item.title,
  });
}
</script>

<template>
  <li class="card-slot">
    <button class="card" type="button" @click="open">
      <ArtworkImage
        class="art"
        :class="{ round: item.type === 'artist' }"
        :url="item.artworkUrl"
        :alt="`${item.title} artwork`"
      />
      <strong>{{ item.title }}</strong>
      <span v-if="item.subtitle">{{ item.subtitle }}</span>
    </button>
  </li>
</template>

<style scoped>
.card-slot {
  min-width: 0;
}

.card {
  display: grid;
  gap: 4px;
  width: 100%;
  padding: 8px;
  border: 0;
  border-radius: var(--radius-control);
  background: transparent;
  color: var(--color-text);
  text-align: left;
  transition: background-color 160ms var(--ease-standard);
}

.card:hover {
  background: var(--color-fill);
}

.art {
  margin-bottom: 6px;
}

.art.round {
  border-radius: 999px;
}

.card strong,
.card span {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.card strong {
  font-size: 14px;
  font-weight: 600;
}

.card span {
  color: var(--color-text-secondary);
  font-size: 13px;
}
</style>
