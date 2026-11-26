<script setup lang="ts">
import { useHostStore } from '~/stores/host';

// A song shared from Apple Music. The person chooses what the Host does with it, and nothing is sent until they do.
const props = defineProps<{ songId: string }>();
const emit = defineEmits<{ close: [] }>();

const host = useHostStore();

function send(
  kind: 'queue.play_now' | 'queue.play_next' | 'queue.enqueue',
): void {
  host.queueSong(
    { source: 'catalog', id: props.songId },
    kind,
    () => undefined,
  );
  emit('close');
}
</script>

<template>
  <div class="shared-link" role="dialog" aria-labelledby="shared-song-title">
    <h2 id="shared-song-title">Shared song</h2>
    <p>
      Cadenza Host will find this song in Apple Music and send it to your Mac.
    </p>
    <div class="shared-actions">
      <button
        type="button"
        :disabled="!host.canControl"
        @click="send('queue.play_now')"
      >
        Play now
      </button>
      <button
        type="button"
        :disabled="!host.connected"
        @click="send('queue.play_next')"
      >
        Play next
      </button>
      <button
        type="button"
        :disabled="!host.connected"
        @click="send('queue.enqueue')"
      >
        Add to queue
      </button>
      <button type="button" @click="emit('close')">Cancel</button>
    </div>
  </div>
</template>

<style scoped>
.shared-link {
  position: fixed;
  left: 16px;
  right: 16px;
  bottom: 16px;
  z-index: 900;
  display: grid;
  gap: 12px;
  padding: 16px;
  border: 1px solid var(--color-fill-strong);
  border-radius: 16px;
  background: var(--color-surface, #1c1c1e);
  color: var(--color-text);
}

.shared-link h2 {
  margin: 0;
  font-size: 18px;
}

.shared-link p {
  margin: 0;
  color: var(--color-text-secondary);
  font-size: 14px;
}

.shared-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.shared-actions button {
  min-height: 44px;
  padding: 0 14px;
  border: 1px solid var(--color-fill-strong);
  border-radius: 10px;
  background: transparent;
  color: var(--color-text);
  font: inherit;
  cursor: pointer;
}

.shared-actions button:disabled {
  opacity: 0.5;
  cursor: default;
}
</style>
