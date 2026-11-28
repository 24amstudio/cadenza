<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import { useHostStore } from '~/stores/host';

// Library write-back for the playing song. It only applies to songs in the Mac's Music library, and Music changes
// only the favorite flag or adds the song to the Cadenza Host playlist.
const host = useHostStore();

const libraryId = computed(() => {
  const song = host.current?.song;

  return song?.source === 'library' ? song.id : null;
});

function favorite(): void {
  const id = libraryId.value;

  if (id !== null) host.setFavorite({ source: 'library', id }, true);
}

function addToPlaylist(): void {
  const id = libraryId.value;

  if (id !== null) {
    host.addToHostPlaylist('Cadenza Host', [{ source: 'library', id }]);
  }
}
</script>

<template>
  <div v-if="libraryId !== null" class="library-actions">
    <button
      type="button"
      class="library-button"
      aria-label="Favorite in Music"
      title="Favorite in Music"
      :disabled="!host.connected"
      @click="favorite"
    >
      <AppIcon name="heart" />
    </button>
    <button
      type="button"
      class="library-button"
      aria-label="Add to Host playlist"
      title="Add to Host playlist"
      :disabled="!host.connected"
      @click="addToPlaylist"
    >
      <AppIcon name="playlist-add" />
    </button>
  </div>
</template>

<style scoped>
.library-actions {
  display: flex;
  gap: 8px;
}

.library-button {
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 18px;
  cursor: pointer;
}

.library-button:hover:not(:disabled) {
  background: var(--color-fill);
  color: var(--color-accent);
}

.library-button:disabled {
  opacity: 0.5;
  cursor: default;
}
</style>
