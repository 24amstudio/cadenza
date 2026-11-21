<script setup lang="ts">
import type { AutoPlayItem } from '~/lib/protocol/types';

// A song Music plays after the requests. It has no requester and cannot be changed from a Remote.
defineProps<{ item: AutoPlayItem }>();
</script>

<template>
  <li class="autoplay-row">
    <div class="meta">
      <strong>{{ item.title }}</strong>
      <span>{{ item.artist }}</span>
    </div>
    <small>AutoPlay</small>
  </li>
</template>

<style scoped>
.autoplay-row {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  gap: 14px;
  padding: 10px 12px;
  border-radius: var(--radius-control);
}

.meta {
  display: grid;
  min-width: 0;
}

.meta strong,
.meta span {
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}

.meta strong {
  font-size: 15px;
  font-weight: 600;
}

.meta span,
small {
  color: var(--color-text-secondary);
  font-size: 13px;
}

small {
  color: var(--color-text-tertiary);
  font-size: 12px;
}
</style>
