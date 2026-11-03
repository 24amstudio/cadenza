<script setup lang="ts">
import { ref } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';

// The Host applies volume once the slider is released. Dragging stays local so the Host receives one command per
// adjustment instead of one per pixel.
const props = defineProps<{ percent: number; disabled: boolean }>();
const emit = defineEmits<{ change: [percent: number] }>();

const draft = ref<number | null>(null);

function onInput(event: Event): void {
  if (!(event.target instanceof HTMLInputElement)) return;
  draft.value = Number(event.target.value);
}

function onCommit(): void {
  if (draft.value === null) return;
  const value = draft.value;
  draft.value = null;
  emit('change', value);
}

function shownPercent(): number {
  return draft.value ?? props.percent;
}
</script>

<template>
  <label class="volume">
    <AppIcon name="speaker" />
    <input
      type="range"
      min="0"
      max="100"
      step="1"
      :value="shownPercent()"
      :disabled="disabled"
      aria-label="Volume"
      :aria-valuetext="`${shownPercent()} percent`"
      :style="{ '--progress': `${shownPercent()}%` }"
      @input="onInput"
      @change="onCommit"
    />
  </label>
</template>

<style scoped>
.volume {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--color-text-secondary);
  font-size: 16px;
}

.volume input {
  width: 108px;
  height: 16px;
  margin: 0;
  background: transparent;
  appearance: none;
  cursor: pointer;
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
