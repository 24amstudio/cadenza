<script setup lang="ts">
import { computed } from 'vue';
import BrowseSection from '~/components/browse/BrowseSection.vue';
import BrowseStatus from '~/components/browse/BrowseStatus.vue';
import { useBrowseRequest } from '~/stores/browse';

// The playlists in Music on Cadenza Host. Choosing one opens its page. Leaving the tab cancels a request still running.
const { entry, retry } = useBrowseRequest(() => ({ kind: 'playlists' }));

const sections = computed(() => entry.value?.page?.sections ?? []);
</script>

<template>
  <div class="playlists">
    <BrowseStatus
      :entry="entry"
      empty-title="No playlists yet"
      empty-body="Playlists you make in Music on Cadenza Host appear here."
      @retry="retry"
    />
    <BrowseSection
      v-for="section in sections"
      :key="section.id"
      :section="section"
    />
  </div>
</template>

<style scoped>
.playlists {
  display: grid;
  gap: 24px;
}
</style>
