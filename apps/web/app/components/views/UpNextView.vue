<script setup lang="ts">
import EmptyState from '~/components/common/EmptyState.vue';
import QueueRow from '~/components/queue/QueueRow.vue';
import { useHostStore } from '~/stores/host';

const host = useHostStore();
</script>

<template>
  <EmptyState
    v-if="host.queue.length === 0"
    icon="queue"
    title="Up Next is empty"
    body="Songs queued on Cadenza Host appear here in play order."
  />
  <section v-else class="up-next" aria-labelledby="up-next-title">
    <header class="page-header">
      <h1 id="up-next-title">Up Next</h1>
      <p>
        {{ host.queue.length }} {{ host.queue.length === 1 ? 'song' : 'songs' }}
      </p>
    </header>
    <ol class="queue-list">
      <QueueRow v-for="entry in host.queue" :key="entry.id" :entry="entry" />
    </ol>
  </section>
</template>

<style scoped>
.up-next {
  display: grid;
  gap: 16px;
  max-width: 760px;
  margin: 0 auto;
}

.page-header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  padding: 0 12px;
}

h1 {
  font-family: var(--font-display);
  font-size: 32px;
  font-weight: 750;
  letter-spacing: -0.02em;
}

.page-header p {
  color: var(--color-text-secondary);
  font-size: 14px;
}

.queue-list {
  display: grid;
  gap: 2px;
  margin: 0;
  padding: 0;
  list-style: none;
}
</style>
