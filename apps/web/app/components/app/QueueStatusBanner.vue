<script setup lang="ts">
import { computed } from 'vue';
import { useHostStore } from '~/stores/host';

// Song requests stay disabled until Cadenza Host can read Music's queue. This says why and what the person can do.
const host = useHostStore();

const message = computed(() => {
  const snapshot = host.snapshot;

  if (!host.connected || snapshot === null || snapshot.synchronized)
    return null;

  return (
    snapshot.issue ??
    'Cadenza Host has not read Music’s queue yet. Song requests are available once it has.'
  );
});
</script>

<template>
  <div v-if="message !== null" class="banner" role="status">
    <span class="banner-text">{{ message }}</span>
  </div>
</template>

<style scoped>
.banner {
  margin: 14px 24px 0;
  padding: 10px 14px;
  border-radius: var(--radius-control);
  background: var(--color-fill-strong);
  color: var(--color-text);
  font-size: 14px;
  box-shadow: inset 3px 0 0 var(--color-accent);
}
</style>
