<script setup lang="ts">
import { computed } from 'vue';
import EmptyState from '~/components/common/EmptyState.vue';
import LyricLines from '~/components/lyrics/LyricLines.vue';
import { lyricsLevel } from '~/lib/lyrics';
import { usePreferencesStore } from '~/stores/preferences';
import { useHostStore } from '~/stores/host';

const host = useHostStore();
const preferences = usePreferencesStore();

const song = computed(() => host.current?.song ?? null);
const document = computed(() => host.lyricsDocument);
const level = computed(() => lyricsLevel(document.value));
</script>

<template>
  <EmptyState
    v-if="song === null"
    icon="lyrics"
    title="No song is playing"
    body="Lyrics appear when a song with lyrics plays on Cadenza Host."
  />
  <EmptyState
    v-else-if="host.lyricsLoading"
    icon="lyrics"
    title="Loading lyrics"
    body="Cadenza Host is getting the lyrics for this song."
  />
  <EmptyState
    v-else-if="document === null || level === 0"
    icon="lyrics"
    title="No lyrics for this song"
    body="Cadenza Host has no lyrics for this song right now."
  />
  <section v-else class="lyrics-view" aria-labelledby="lyrics-title">
    <header class="lyrics-header">
      <h1 id="lyrics-title">{{ song.title }}</h1>
      <p>{{ song.artist }}</p>
    </header>
    <LyricLines
      :lines="document.lines"
      :position-ms="host.positionMs"
      :timed="level >= 2"
      :word-timed="level === 3"
      :size="preferences.lyricsSize"
      @seek="host.seekTo"
    />
  </section>
</template>

<style scoped>
.lyrics-view {
  display: grid;
  gap: 8px;
  max-width: min(100%, 1200px);
  margin: 0 auto;
}

.lyrics-header {
  display: grid;
  gap: 4px;
  padding-top: 4px;
  text-align: center;
}

h1 {
  font-family: var(--font-display);
  font-size: 18px;
  font-weight: 700;
}

.lyrics-header p {
  color: var(--color-text-secondary);
  font-size: 14px;
}
</style>
