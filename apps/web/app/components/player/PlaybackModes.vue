<script setup lang="ts">
import AppIcon from '~/components/common/AppIcon.vue';
import type { ControlKey } from '~/lib/host/controlQueue';
import { repeatLabel } from '~/lib/playbackModes';
import type { RepeatMode } from '~/lib/protocol/types';

// Shuffle is on or off. Repeat steps through off, all, then one, and each step has its own icon and label.
defineProps<{
  shuffle: boolean;
  repeat: RepeatMode;
  pending: ReadonlySet<ControlKey>;
  disabled: boolean;
  compact?: boolean;
}>();

const emit = defineEmits<{ shuffle: []; repeat: [] }>();
</script>

<template>
  <div class="modes" :class="{ compact }">
    <button
      class="mode-button"
      :class="{ active: shuffle, pending: pending.has('shuffle') }"
      type="button"
      :aria-label="shuffle ? 'Shuffle on' : 'Shuffle off'"
      :aria-pressed="shuffle"
      :aria-busy="pending.has('shuffle')"
      :disabled="disabled"
      @click="emit('shuffle')"
    >
      <AppIcon name="shuffle" />
    </button>
    <button
      class="mode-button"
      :class="{ active: repeat !== 'off', pending: pending.has('repeat') }"
      type="button"
      :aria-label="repeatLabel(repeat)"
      :aria-busy="pending.has('repeat')"
      :disabled="disabled"
      @click="emit('repeat')"
    >
      <AppIcon :name="repeat === 'one' ? 'repeat-one' : 'repeat'" />
    </button>
  </div>
</template>

<style scoped>
.modes {
  display: flex;
  align-items: center;
  gap: 10px;
}

.mode-button {
  position: relative;
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 20px;
  transition:
    background-color 160ms var(--ease-standard),
    color 160ms var(--ease-standard);
}

.mode-button:hover:not(:disabled) {
  background: var(--color-fill);
}

/* A mode that is on is the accent colour with a dot under it, so it does not rely on colour alone. */
.mode-button.active {
  color: var(--color-accent);
}

.mode-button.active::before {
  content: '';
  position: absolute;
  bottom: 3px;
  left: 50%;
  width: 4px;
  height: 4px;
  margin-left: -2px;
  border-radius: 999px;
  background: currentColor;
}

.mode-button.pending::after {
  content: '';
  position: absolute;
  inset: -2px;
  border: 2px solid var(--color-accent);
  border-radius: 999px;
  opacity: 0.7;
  animation: mode-pulse 900ms var(--ease-standard) infinite alternate;
  pointer-events: none;
}

@keyframes mode-pulse {
  from {
    opacity: 0.15;
  }

  to {
    opacity: 0.8;
  }
}

@media (prefers-reduced-motion: reduce) {
  .mode-button.pending::after {
    animation: none;
  }
}

.compact .mode-button {
  width: 34px;
  height: 34px;
  font-size: 18px;
}

.compact {
  gap: 4px;
}
</style>
