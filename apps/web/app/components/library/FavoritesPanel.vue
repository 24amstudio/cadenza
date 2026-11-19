<script setup lang="ts">
import EmptyState from '~/components/common/EmptyState.vue';
import SongRow from '~/components/library/SongRow.vue';
import { songKey } from '~/lib/library/identity';
import { useLibraryStore } from '~/stores/library';

const library = useLibraryStore();
</script>

<template>
  <EmptyState
    v-if="library.favorites.length === 0"
    icon="heart"
    title="No favorites yet"
    body="Tap the heart on a song to keep it here. Favorites are saved in this browser only, so they do not follow you to another browser or device."
  />
  <ul v-else class="song-list" aria-label="Favorites">
    <SongRow
      v-for="song in library.favorites"
      :key="songKey(song)"
      :song="song"
    />
  </ul>
</template>
