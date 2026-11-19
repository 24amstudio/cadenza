<script setup lang="ts">
import { computed, onBeforeUnmount, ref } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';

// The slider shows the level at once. While it is dragged or stepped, the level goes to the Host at most every 200 ms,
// and the store folds levels that arrive while a command is in flight into the newest one.
const props = defineProps<{
  percent: number;
  muted: boolean;
  disabled: boolean;
  // Only the mute button, for a bar with no room for the slider.
  compact?: boolean;
  // The slider takes the width of its row.
  wide?: boolean;
}>();

const emit = defineEmits<{ change: [percent: number]; toggleMute: [] }>();

const sendIntervalMs = 200;
const draft = ref<number | null>(null);
let lastSentAt = 0;
let lastSent: number | null = null;
let trailing: ReturnType<typeof setTimeout> | null = null;

const shown = computed(() => draft.value ?? props.percent);

const valueText = computed(() =>
  shown.value === 0 ? 'Muted' : `${shown.value} percent`,
);

function send(value: number): void {
  if (value === lastSent) return;
  lastSent = value;
  lastSentAt = performance.now();
  emit('change', value);
}

function clearTrailing(): void {
  if (trailing !== null) clearTimeout(trailing);
  trailing = null;
}

function onInput(event: Event): void {
  if (!(event.target instanceof HTMLInputElement)) return;
  const value = Number(event.target.value);
  draft.value = value;
  const wait = sendIntervalMs - (performance.now() - lastSentAt);

  if (wait <= 0) {
    clearTrailing();
    send(value);

    return;
  }

  clearTrailing();
  trailing = setTimeout(() => {
    trailing = null;

    if (draft.value !== null) send(draft.value);
  }, wait);
}

// Releasing the thumb, or a key press, ends the adjustment with the final level.
function onCommit(): void {
  clearTrailing();

  if (draft.value !== null) send(draft.value);
  draft.value = null;
  lastSent = null;
}

onBeforeUnmount(clearTrailing);
</script>

<template>
  <div
    class="volume"
    :class="{ wide, compact }"
    role="group"
    aria-label="Volume"
  >
    <button
      class="mute"
      type="button"
      :aria-label="muted ? 'Unmute' : 'Mute'"
      :aria-pressed="muted"
      :disabled="disabled"
      @click="emit('toggleMute')"
    >
      <AppIcon :name="muted ? 'speaker-muted' : 'speaker'" />
    </button>
    <input
      v-if="!compact"
      type="range"
      min="0"
      max="100"
      step="1"
      :value="shown"
      :disabled="disabled"
      aria-label="Volume"
      :aria-valuetext="valueText"
      :style="{ '--progress': `${shown}%` }"
      @input="onInput"
      @change="onCommit"
    />
  </div>
</template>

<style scoped>
.volume {
  display: flex;
  align-items: center;
  gap: 6px;
  color: var(--color-text-secondary);
  font-size: 16px;
}

.volume.wide {
  width: 100%;
}

.mute {
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: inherit;
  font-size: 18px;
}

.mute:hover:not(:disabled) {
  background: var(--color-fill);
  color: var(--color-text);
}

.mute:disabled {
  opacity: 0.5;
}

.volume input {
  width: 96px;
  height: 20px;
  margin: 0;
  background: transparent;
  appearance: none;
  cursor: pointer;
}

.volume.wide input {
  flex: 1;
  width: auto;
  min-width: 0;
}

.volume input:disabled {
  opacity: 0.5;
  cursor: default;
}

.volume input::-webkit-slider-runnable-track {
  height: 4px;
  border-radius: 999px;
  background:
    linear-gradient(var(--color-text-secondary), var(--color-text-secondary))
      0 / var(--progress) 100% no-repeat,
    var(--color-fill-strong);
}

.volume input::-webkit-slider-thumb {
  width: 12px;
  height: 12px;
  margin-top: -4px;
  border: 0;
  border-radius: 999px;
  background: var(--color-text);
  appearance: none;
}

.volume input::-moz-range-track {
  height: 4px;
  border-radius: 999px;
  background: var(--color-fill-strong);
}

.volume input::-moz-range-progress {
  height: 4px;
  border-radius: 999px;
  background: var(--color-text-secondary);
}

.volume input::-moz-range-thumb {
  width: 12px;
  height: 12px;
  border: 0;
  background: var(--color-text);
}
</style>
