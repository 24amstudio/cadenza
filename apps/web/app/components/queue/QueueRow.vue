<script setup lang="ts">
import ArtworkImage from '~/components/common/ArtworkImage.vue';
import { formatWait } from '~/lib/playback';
import type { QueueEntry } from '~/lib/protocol/types';

defineProps<{ entry: QueueEntry }>();
</script>

<template>
  <li class="queue-row">
    <ArtworkImage
      class="thumb"
      :url="entry.song.artworkUrl"
      :alt="`${entry.song.title} artwork`"
    />
    <div class="meta">
      <strong>{{ entry.song.title }}</strong>
      <span>{{ entry.song.artist }}</span>
    </div>
    <div class="side">
      <span>{{ formatWait(entry.estimatedWaitMs) }}</span>
      <small>Added by {{ entry.requesterName }}</small>
    </div>
  </li>
</template>

<style scoped>
.queue-row {
  display: grid;
  grid-template-columns: 48px minmax(0, 1fr) auto;
  align-items: center;
  gap: 14px;
  padding: 10px 12px;
  border-radius: var(--radius-control);
  transition: background-color 160ms var(--ease-standard);
}

.queue-row:hover {
  background: var(--color-fill);
}

.thumb {
  width: 48px;
  height: 48px;
  border-radius: 7px;
}

.meta,
.side {
  display: grid;
  min-width: 0;
}

.meta strong,
.meta span,
.side span,
.side small {
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}

.meta strong {
  font-size: 15px;
  font-weight: 600;
}

.meta span,
.side small {
  color: var(--color-text-secondary);
  font-size: 13px;
}

.side {
  justify-items: end;
  text-align: right;
}

.side span {
  font-size: 13px;
  font-variant-numeric: tabular-nums;
}

.side small {
  max-width: 180px;
  font-size: 12px;
  color: var(--color-text-tertiary);
}
</style>
