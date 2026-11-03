<script setup lang="ts">
import { computed } from 'vue';
import { useHostStore } from '~/stores/host';

// Shown only while the page is paired but not connected. Brief reconnects stay quiet; repeated failures get an action.
const host = useHostStore();

const unreachable = computed(
  () => host.phase === 'reconnecting' && host.attempt >= 3,
);

const message = computed(() => {
  if (unreachable.value) {
    return 'Cadenza Host is not reachable. Check that it is running and that this device is on the same network.';
  }

  if (host.phase === 'reconnecting') return 'Reconnecting to Cadenza Host…';

  return 'Connecting to Cadenza Host…';
});

const visible = computed(
  () => host.phase === 'connecting' || host.phase === 'reconnecting',
);
</script>

<template>
  <div
    v-if="visible"
    class="banner"
    :class="{ urgent: unreachable }"
    role="status"
  >
    <span class="banner-text">{{ message }}</span>
    <button
      v-if="unreachable"
      class="banner-action"
      type="button"
      @click="host.retry()"
    >
      Try again
    </button>
  </div>
</template>

<style scoped>
.banner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin: 14px 24px 0;
  padding: 10px 14px;
  border-radius: var(--radius-control);
  background: var(--color-fill-strong);
  color: var(--color-text-secondary);
  font-size: 14px;
}

.banner.urgent {
  color: var(--color-text);
  box-shadow: inset 3px 0 0 var(--color-accent);
}

.banner-action {
  flex: none;
  height: 30px;
  padding: 0 14px;
  border: 0;
  border-radius: 999px;
  background: var(--color-text);
  color: var(--color-canvas);
  font-size: 13px;
  font-weight: 600;
}
</style>
