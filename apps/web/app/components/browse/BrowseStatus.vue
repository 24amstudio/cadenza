<script setup lang="ts">
import EmptyState from '~/components/common/EmptyState.vue';
import type { BrowseEntry } from '~/stores/browse';

// What stands in for a page that has nothing to show yet: skeleton rows while it loads, the reason and a Retry when it
// failed, or an empty message when the Host sent no items.
defineProps<{
  entry: BrowseEntry | null;
  emptyTitle: string;
  emptyBody: string;
}>();

const emit = defineEmits<{ retry: [] }>();
</script>

<template>
  <div
    v-if="entry === null || (entry.page === null && entry.status === 'loading')"
    class="loading"
    role="status"
  >
    <span class="visually-hidden">Cadenza Host is loading this page.</span>
    <span
      v-for="row in 5"
      :key="row"
      class="row skeleton"
      aria-hidden="true"
    ></span>
  </div>
  <EmptyState
    v-else-if="entry.page === null && entry.status === 'failed'"
    class="failed"
    icon="queue"
    title="This page did not load"
    :body="entry.message ?? 'Cadenza Host could not load this page.'"
  >
    <button class="retry" type="button" @click="emit('retry')">
      Try again
    </button>
  </EmptyState>
  <EmptyState
    v-else-if="
      entry.page !== null &&
      entry.page.sections.every((section) => section.items.length === 0)
    "
    class="empty"
    icon="queue"
    :title="emptyTitle"
    :body="emptyBody"
  />
</template>

<style scoped>
.loading {
  display: grid;
  gap: 12px;
  padding: 8px 12px;
}

.row {
  height: 52px;
  border-radius: var(--radius-control);
}

.failed,
.empty {
  min-height: 280px;
}

.retry {
  min-height: 40px;
  margin-top: 8px;
  padding: 0 20px;
  border: 0;
  border-radius: 999px;
  background: var(--color-accent);
  color: var(--color-on-accent);
  font-weight: 600;
}

.retry:hover {
  background: var(--color-accent-hover);
}
</style>
