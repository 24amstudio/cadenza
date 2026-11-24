<script setup lang="ts">
import { computed, ref } from 'vue';
import { useHostStore } from '~/stores/host';
import { useSongActionsStore } from '~/stores/songActions';
import type { AutoPlayItem } from '~/lib/protocol/types';

// A song Music plays after the requests. A Remote can play it now or move it to Up Next, where it can be reordered.
const props = defineProps<{ item: AutoPlayItem }>();

const host = useHostStore();

const actions = useSongActionsStore();

const pending = ref<'now' | 'next' | null>(null);

const canPlayNext = computed(() =>
  host.capabilities.includes('queue.play-next'),
);

const ready = computed(
  () => host.connected && host.snapshot?.synchronized === true,
);

async function request(action: 'now' | 'next'): Promise<void> {
  if (pending.value !== null) return;

  pending.value = action;

  try {
    await actions.playAutoPlay(props.item, action);
  } finally {
    pending.value = null;
  }
}
</script>

<template>
  <li class="autoplay-row">
    <div class="meta">
      <strong>{{ item.title }}</strong>
      <span>{{ item.artist }}</span>
    </div>
    <div class="actions">
      <button
        class="request"
        type="button"
        :aria-busy="pending === 'now'"
        :disabled="!ready || pending !== null"
        :aria-label="`Play ${item.title} now`"
        @click="request('now')"
      >
        {{ pending === 'now' ? 'Starting…' : 'Play now' }}
      </button>
      <button
        v-if="canPlayNext"
        class="request"
        type="button"
        :aria-busy="pending === 'next'"
        :disabled="!ready || pending !== null"
        :aria-label="`Play ${item.title} next`"
        @click="request('next')"
      >
        {{ pending === 'next' ? 'Adding…' : 'Play next' }}
      </button>
    </div>
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

.autoplay-row:hover {
  background: var(--color-fill);
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

.meta span {
  color: var(--color-text-secondary);
  font-size: 13px;
}

.actions {
  display: flex;
  gap: 8px;
}

.request {
  min-height: 36px;
  padding: 0 14px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill);
  color: var(--color-text);
  font-size: 13px;
  font-weight: 560;
  white-space: nowrap;
}

.request:hover:not(:disabled) {
  background: var(--color-fill-strong);
}
</style>
