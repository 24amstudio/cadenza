<script setup lang="ts">
import { onMounted, onUnmounted, ref } from 'vue';
import { DRIFT_INTERVAL_MS, driftOffset } from '~/lib/oledDrift';

// A full-screen black surface for OLED displays. Its text drifts a few pixels every 45 seconds, and the screen is kept
// awake while it is open. Escape or the close button ends it.
const props = defineProps<{ title: string; artist: string }>();
const emit = defineEmits<{ close: [] }>();

const step = ref(0);
const closeButton = ref<HTMLButtonElement | null>(null);
let timer: ReturnType<typeof setInterval> | null = null;
let wakeLock: WakeLockSentinel | null = null;

function offsetStyle() {
  const { x, y } = driftOffset(step.value);

  return { transform: `translate(${x}px, ${y}px)` };
}

function onKey(event: KeyboardEvent): void {
  if (event.key === 'Escape') emit('close');
}

onMounted(async () => {
  timer = setInterval(() => {
    step.value += 1;
  }, DRIFT_INTERVAL_MS);
  window.addEventListener('keydown', onKey);
  closeButton.value?.focus();

  try {
    wakeLock = (await navigator.wakeLock?.request('screen')) ?? null;
  } catch {
    // The browser refused the wake lock. The ambient surface still works, so there is nothing to report.
    wakeLock = null;
  }
});

onUnmounted(() => {
  if (timer !== null) clearInterval(timer);
  window.removeEventListener('keydown', onKey);
  void wakeLock?.release();
});
</script>

<template>
  <div
    class="ambient"
    role="dialog"
    aria-modal="true"
    aria-label="OLED ambient mode"
  >
    <div class="ambient-content" :style="offsetStyle()">
      <p class="ambient-title">{{ props.title }}</p>
      <p class="ambient-artist">{{ props.artist }}</p>
    </div>
    <button
      ref="closeButton"
      type="button"
      class="ambient-close"
      @click="emit('close')"
    >
      Close
    </button>
  </div>
</template>

<style scoped>
.ambient {
  position: fixed;
  inset: 0;
  z-index: 1000;
  display: grid;
  place-items: center;
  background: #000;
  color: #8e8e93;
}

.ambient-content {
  text-align: center;
  transition: transform 1s ease;
}

.ambient-title {
  margin: 0;
  font-size: clamp(24px, 5vw, 56px);
  font-weight: 600;
}

.ambient-artist {
  margin: 8px 0 0;
  font-size: clamp(16px, 3vw, 28px);
}

.ambient-close {
  position: fixed;
  top: 16px;
  right: 16px;
  min-height: 44px;
  padding: 0 14px;
  border: 1px solid #3a3a3c;
  border-radius: 10px;
  background: transparent;
  color: #8e8e93;
  font: inherit;
  cursor: pointer;
}
</style>
