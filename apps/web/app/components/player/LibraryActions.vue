<script setup lang="ts">
import { computed } from 'vue';
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
      :disabled="!host.connected"
      @click="favorite"
    >
      Favorite in Music
    </button>
    <button
      type="button"
      class="library-button"
      :disabled="!host.connected"
      @click="addToPlaylist"
    >
      Add to Host playlist
    </button>
  </div>
</template>

<style scoped>
.library-actions {
  display: flex;
  gap: 6px;
}

.library-button {
  min-height: 32px;
  padding: 0 10px;
  border: 1px solid var(--color-fill-strong);
  border-radius: 8px;
  background: transparent;
  color: var(--color-text);
  font: inherit;
  font-size: 13px;
  cursor: pointer;
}

.library-button:disabled {
  opacity: 0.5;
  cursor: default;
}
</style>
