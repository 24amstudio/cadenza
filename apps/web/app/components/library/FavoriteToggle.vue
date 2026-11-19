<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import type { Song } from '~/lib/protocol/types';
import { useLibraryStore } from '~/stores/library';

const props = defineProps<{ song: Song }>();

const library = useLibraryStore();
const saved = computed(() => library.isFavorite(props.song));
</script>

<template>
  <button
    class="favorite-toggle"
    :class="{ saved }"
    type="button"
    :aria-label="`Favorite ${song.title}`"
    :aria-pressed="saved"
    @click="library.toggleFavorite(song)"
  >
    <AppIcon :name="saved ? 'heart-filled' : 'heart'" />
  </button>
</template>

<style scoped>
.favorite-toggle {
  display: grid;
  place-items: center;
  flex: none;
  width: 40px;
  height: 40px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill);
  color: var(--color-text);
  font-size: 19px;
  transition:
    background-color 160ms var(--ease-standard),
    color 160ms;
}

.favorite-toggle:hover {
  background: var(--color-fill-strong);
}

.favorite-toggle.saved {
  color: var(--color-accent);
}
</style>
