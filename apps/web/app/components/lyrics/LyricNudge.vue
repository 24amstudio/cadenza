<script setup lang="ts">
import { computed } from 'vue';
import { LYRIC_NUDGE_STEP_MS, nudgeDelay } from '~/lib/lyricNudge';

const props = defineProps<{
  delayMs: number;
  canSyncFirstLine: boolean;
}>();

const emit = defineEmits<{
  'update:delayMs': [delayMs: number];
  syncFirstLine: [];
}>();

const stepLabel = `${LYRIC_NUDGE_STEP_MS / 1000} s`;

const valueLabel = computed(() => {
  const seconds = props.delayMs / 1000;

  if (seconds === 0) return '0.0 s';

  return `${seconds > 0 ? '+' : ''}${seconds.toFixed(1)} s`;
});

function shift(direction: 1 | -1): void {
  emit(
    'update:delayMs',
    nudgeDelay(props.delayMs, direction * LYRIC_NUDGE_STEP_MS),
  );
}
</script>

<template>
  <div class="lyric-nudge" role="group" aria-label="Lyric timing">
    <button
      class="nudge-button"
      type="button"
      :aria-label="`Show lyrics ${stepLabel} earlier`"
      @click="shift(-1)"
    >
      -{{ stepLabel }}
    </button>
    <span class="nudge-value" aria-live="polite">{{ valueLabel }}</span>
    <button
      class="nudge-button"
      type="button"
      :aria-label="`Show lyrics ${stepLabel} later`"
      @click="shift(1)"
    >
      +{{ stepLabel }}
    </button>
    <button
      v-if="props.canSyncFirstLine"
      class="nudge-button nudge-sync"
      type="button"
      @click="emit('syncFirstLine')"
    >
      Sync First Line
    </button>
  </div>
</template>

<style scoped>
.lyric-nudge {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding: 6px 12px;
  border-radius: 999px;
  background: var(--color-fill);
  color: var(--color-text-secondary);
  font-size: 14px;
  justify-self: start;
}

.nudge-button {
  min-height: 36px;
  padding: 0 12px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill-strong);
  color: var(--color-text);
  font: inherit;
}

.nudge-button:hover {
  background: var(--color-text-tertiary);
}

.nudge-value {
  min-width: 4.5em;
  text-align: center;
  font-variant-numeric: tabular-nums;
}
</style>
