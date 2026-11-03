<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import { formatClock, progressRatio } from '~/lib/playback';

// The thumb holds the dragged or submitted position until the Host reports a position near it, so the bar does not
// snap back between release and the next state update.
const props = defineProps<{
  positionMs: number;
  durationMs: number | null;
  disabled: boolean;
  labels?: boolean;
}>();

const emit = defineEmits<{ seek: [positionMs: number] }>();

const draft = ref<number | null>(null);
const committed = ref<number | null>(null);
let committedTimer: ReturnType<typeof setTimeout> | null = null;

const duration = computed(() => props.durationMs ?? 0);

const shownMs = computed(() => {
  const value = draft.value ?? committed.value ?? props.positionMs;

  return Math.min(value, duration.value);
});

const ratio = computed(() => progressRatio(shownMs.value, props.durationMs));
const remainingMs = computed(() => Math.max(0, duration.value - shownMs.value));

watch(
  () => props.positionMs,
  (value) => {
    if (committed.value !== null && Math.abs(value - committed.value) < 1_500) {
      clearCommitted();
    }
  },
);

function onInput(event: Event): void {
  if (!(event.target instanceof HTMLInputElement)) return;
  draft.value = (Number(event.target.value) / 1000) * duration.value;
}

function onCommit(): void {
  if (draft.value === null) return;
  const target = Math.round(draft.value);
  draft.value = null;
  committed.value = target;

  if (committedTimer !== null) clearTimeout(committedTimer);
  committedTimer = setTimeout(clearCommitted, 3_000);
  emit('seek', target);
}

function clearCommitted(): void {
  committed.value = null;

  if (committedTimer !== null) clearTimeout(committedTimer);
  committedTimer = null;
}
</script>

<template>
  <div class="scrubber" :class="{ labelled: labels }">
    <input
      class="track"
      type="range"
      min="0"
      max="1000"
      step="1"
      :value="Math.round(ratio * 1000)"
      :disabled="disabled || durationMs === null"
      :style="{ '--progress': `${ratio * 100}%` }"
      aria-label="Playback position"
      :aria-valuetext="`${formatClock(shownMs)} of ${formatClock(duration)}`"
      @input="onInput"
      @change="onCommit"
    />
    <div v-if="labels" class="times" aria-hidden="true">
      <span>{{ formatClock(shownMs) }}</span>
      <span>-{{ formatClock(remainingMs) }}</span>
    </div>
  </div>
</template>

<style scoped>
.scrubber {
  display: grid;
  gap: 8px;
  width: 100%;
}

.track {
  --track-height: 4px;
  width: 100%;
  height: 16px;
  margin: 0;
  background: transparent;
  appearance: none;
  cursor: pointer;
}

.track:disabled {
  cursor: default;
  opacity: 0.5;
}

.track::-webkit-slider-runnable-track {
  height: var(--track-height);
  border-radius: 999px;
  background:
    linear-gradient(var(--color-text), var(--color-text)) 0 / var(--progress)
      100% no-repeat,
    var(--color-fill-strong);
}

.track::-webkit-slider-thumb {
  width: 12px;
  height: 12px;
  margin-top: -4px;
  border: 0;
  border-radius: 999px;
  background: var(--color-text);
  appearance: none;
  opacity: 0;
  transition: opacity 140ms;
}

.track::-moz-range-track {
  height: var(--track-height);
  border-radius: 999px;
  background: var(--color-fill-strong);
}

.track::-moz-range-progress {
  height: var(--track-height);
  border-radius: 999px;
  background: var(--color-text);
}

.track::-moz-range-thumb {
  width: 12px;
  height: 12px;
  border: 0;
  background: var(--color-text);
  opacity: 0;
}

.track:hover::-webkit-slider-thumb,
.track:focus-visible::-webkit-slider-thumb,
.track:active::-webkit-slider-thumb {
  opacity: 1;
}

.track:hover::-moz-range-thumb,
.track:focus-visible::-moz-range-thumb {
  opacity: 1;
}

.times {
  display: flex;
  justify-content: space-between;
  color: var(--color-text-secondary);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
}
</style>
