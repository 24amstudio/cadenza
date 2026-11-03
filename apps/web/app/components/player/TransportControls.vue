<script setup lang="ts">
import AppIcon from '~/components/common/AppIcon.vue';

defineProps<{ isPlaying: boolean; disabled: boolean; compact?: boolean }>();

const emit = defineEmits<{
  previous: [];
  toggle: [];
  next: [];
}>();
</script>

<template>
  <div class="transport" :class="{ compact }">
    <button
      class="transport-button"
      type="button"
      aria-label="Previous"
      :disabled="disabled"
      @click="emit('previous')"
    >
      <AppIcon name="previous" />
    </button>
    <button
      class="play-button"
      type="button"
      :aria-label="isPlaying ? 'Pause' : 'Play'"
      :disabled="disabled"
      @click="emit('toggle')"
    >
      <AppIcon :name="isPlaying ? 'pause' : 'play'" />
    </button>
    <button
      class="transport-button"
      type="button"
      aria-label="Next"
      :disabled="disabled"
      @click="emit('next')"
    >
      <AppIcon name="next" />
    </button>
  </div>
</template>

<style scoped>
.transport {
  display: flex;
  align-items: center;
  gap: 18px;
}

.transport-button {
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: var(--color-text);
  font-size: 22px;
  transition:
    background-color 160ms var(--ease-standard),
    opacity 160ms;
}

.transport-button:hover:not(:disabled) {
  background: var(--color-fill);
}

.play-button {
  display: grid;
  place-items: center;
  width: 60px;
  height: 60px;
  border: 0;
  border-radius: 999px;
  background: var(--color-accent);
  color: var(--color-on-accent);
  font-size: 24px;
  box-shadow: 0 10px 26px -10px var(--color-accent);
  transition:
    transform 160ms var(--ease-standard),
    background-color 160ms;
}

.play-button:hover:not(:disabled) {
  background: var(--color-accent-hover);
}

.play-button:active:not(:disabled) {
  transform: scale(0.96);
}

.play-button .icon {
  margin-left: 2px;
}

.compact {
  gap: 10px;
}

.compact .transport-button {
  width: 34px;
  height: 34px;
  font-size: 18px;
}

.compact .play-button {
  width: 40px;
  height: 40px;
  font-size: 18px;
  box-shadow: none;
}

.compact .play-button .icon {
  margin-left: 1px;
}
</style>
