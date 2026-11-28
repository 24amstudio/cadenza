<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import ArtworkImage from '~/components/common/ArtworkImage.vue';
import { ambientWakeDistancePx } from '~/lib/ambient';
import { DRIFT_INTERVAL_MS, driftOffset } from '~/lib/oledDrift';
import { useHostStore } from '~/stores/host';
import { usePreferencesStore } from '~/stores/preferences';
import { useUiStore } from '~/stores/ui';

const host = useHostStore();
const preferences = usePreferencesStore();
const ui = useUiStore();

const song = computed(() => host.current?.song ?? null);
const mode = computed(() => preferences.ambientMode);
const coverUrl = computed(() => song.value?.artworkUrl ?? null);
const cover = computed(() => host.artworkFor(coverUrl.value));
const motionUrl = computed(() => host.motionUrl);

const reduceMotion = window.matchMedia(
  '(prefers-reduced-motion: reduce)',
).matches;

const showMotion = computed(
  () =>
    mode.value === 'alive' &&
    motionUrl.value !== null &&
    !reduceMotion &&
    !preferences.reduceEffects,
);

watch(
  coverUrl,
  (url) => {
    if (url !== null) host.requestArtwork(url);
  },
  { immediate: true },
);

const clockFormat = new Intl.DateTimeFormat(undefined, {
  hour: 'numeric',
  minute: '2-digit',
});

const now = ref(new Date());
const clock = computed(() => clockFormat.format(now.value));
let clockTimer: ReturnType<typeof setTimeout> | null = null;

function scheduleClock(): void {
  clockTimer = setTimeout(
    () => {
      now.value = new Date();
      scheduleClock();
    },
    60_000 - (Date.now() % 60_000),
  );
}

const step = ref(0);

const offsetStyle = computed(() => {
  const { x, y } = driftOffset(step.value);

  return { transform: `translate(${x}px, ${y}px)` };
});

let driftTimer: ReturnType<typeof setInterval> | null = null;

const surface = ref<HTMLElement | null>(null);
let returnFocus: HTMLElement | null = null;
let travelled = 0;
let active = true;
let wakeLock: WakeLockSentinel | null = null;

function leave(): void {
  ui.closeAmbient();
}

function onPointerDown(): void {
  leave();
}

function onPointerMove(event: PointerEvent): void {
  travelled += Math.abs(event.movementX) + Math.abs(event.movementY);

  if (travelled > ambientWakeDistancePx) leave();
}

function onKeyDown(): void {
  leave();
}

watch(song, (current) => {
  if (current === null) leave();
});

onMounted(async () => {
  returnFocus =
    document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
  surface.value?.focus();

  window.addEventListener('pointerdown', onPointerDown);
  window.addEventListener('pointermove', onPointerMove);
  window.addEventListener('keydown', onKeyDown);

  driftTimer = setInterval(() => {
    step.value += 1;
  }, DRIFT_INTERVAL_MS);
  scheduleClock();

  try {
    wakeLock = (await navigator.wakeLock?.request('screen')) ?? null;
  } catch {
    wakeLock = null;
  }

  if (!active) void wakeLock?.release();
});

onUnmounted(() => {
  active = false;
  window.removeEventListener('pointerdown', onPointerDown);
  window.removeEventListener('pointermove', onPointerMove);
  window.removeEventListener('keydown', onKeyDown);

  if (driftTimer !== null) clearInterval(driftTimer);

  if (clockTimer !== null) clearTimeout(clockTimer);

  void wakeLock?.release();
  returnFocus?.focus();
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="song"
      ref="surface"
      class="ambient"
      :class="`mode-${mode}`"
      role="dialog"
      aria-modal="true"
      aria-label="Ambient mode"
      tabindex="-1"
    >
      <div v-if="mode === 'alive'" class="backdrop" aria-hidden="true">
        <img v-if="cover !== null" class="backdrop-cover" :src="cover" alt="" />
        <video
          v-if="showMotion && motionUrl !== null"
          :key="motionUrl"
          class="backdrop-motion"
          :src="motionUrl"
          autoplay
          loop
          muted
          playsinline
          disablepictureinpicture
        />
      </div>

      <div class="content" :style="offsetStyle">
        <ArtworkImage
          v-if="mode === 'artwork'"
          class="cover"
          :url="coverUrl"
          :alt="`${song.title} artwork`"
        />
        <time class="clock" :datetime="now.toISOString()">{{ clock }}</time>
        <div class="song">
          <p class="title">{{ song.title }}</p>
          <p class="artist">{{ song.artist }}</p>
          <p v-if="mode === 'alive' && song.album.trim() !== ''" class="album">
            {{ song.album }}
          </p>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.ambient {
  position: fixed;
  inset: 0;
  z-index: 1000;
  display: grid;
  place-items: center;
  overflow: hidden;
  background: #000;
  color: #f2f2f7;
  outline: none;
}

.backdrop {
  position: absolute;
  inset: 0;
}

.backdrop-cover,
.backdrop-motion {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  transform: scale(1.15);
  filter: blur(48px) saturate(1.15);
}

.backdrop::after {
  content: '';
  position: absolute;
  inset: 0;
  background: rgb(0 0 0 / 0.5);
}

.content {
  position: relative;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: clamp(14px, 3vh, 28px);
  max-width: 100%;
  padding: 24px;
  text-align: center;
  transition: transform 1s ease;
}

.cover {
  width: min(46vh, 72vw, 380px);
  border-radius: 14px;
}

.clock {
  font-size: clamp(72px, 20vmin, 220px);
  font-weight: 200;
  line-height: 1;
  font-variant-numeric: tabular-nums;
  letter-spacing: -0.02em;
}

.song {
  max-width: 100%;
  min-width: 0;
}

.title {
  margin: 0;
  font-size: clamp(20px, 4.2vmin, 52px);
  font-weight: 600;
  color: #e5e5ea;
}

.artist {
  margin: 6px 0 0;
  font-size: clamp(16px, 3vmin, 34px);
  color: #aeaeb2;
}

.album {
  margin: 4px 0 0;
  font-size: clamp(14px, 2.4vmin, 26px);
  color: #8e8e93;
}
</style>
