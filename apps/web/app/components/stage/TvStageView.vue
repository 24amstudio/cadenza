<script setup lang="ts">
import { renderSVG } from 'uqr';
import {
  computed,
  onBeforeUnmount,
  onMounted,
  reactive,
  ref,
  watch,
} from 'vue';
import { activeLineIndices } from '~/lib/lyrics';
import { DRIFT_INTERVAL_MS, driftOffset } from '~/lib/oledDrift';
import { lyricPositionMs } from '~/lib/stage/stageClock';
import { StageController, type StageState } from '~/lib/stage/stageController';

// The 10-foot stage. The TV shows the approved track's artwork, motion loop, and synced lyrics. It takes its keys from a
// TV remote and draws its own pairing prompt until a Host or a paired Remote approves it.

const LIP_SYNC_KEY = 'cadenza.stage.lipSyncMs.v1';
const LIP_SYNC_STEP_MS = 10;
const LIP_SYNC_MAX_MS = 250;
const IDLE_HIDE_MS = 3_000;

type MotionSlot = 'a' | 'b';

const activeIndices = ref<number[]>([]);
const chromeVisible = ref(true);
const driftStep = ref(0);
const lipSyncMs = ref(readLipSync());
const notice = ref<string | null>(null);
const activeMotion = ref<MotionSlot>('a');
const video = ref<HTMLVideoElement | null>(null);
const motionA = ref<HTMLVideoElement | null>(null);
const motionB = ref<HTMLVideoElement | null>(null);

const touch = typeof navigator !== 'undefined' && navigator.maxTouchPoints > 0;

const state = reactive<StageState>({
  phase: 'connecting',
  pin: null,
  pinExpiresAt: null,
  suite: null,
  video: null,
  nextTrackId: null,
  audioUnlocked: false,
  playing: false,
  error: null,
});

let controller: StageController | null = null;
let frameHandle = 0;
let idleTimer: ReturnType<typeof setTimeout> | null = null;
let noticeTimer: ReturnType<typeof setTimeout> | null = null;
let driftTimer: ReturnType<typeof setInterval> | null = null;
let wakeLock: WakeLockSentinel | null = null;

// The motion slot that is loading the next track's loop. It becomes active once its first frame can play.
let loadingMotion: MotionSlot | null = null;

function readLipSync(): number {
  try {
    const value = Number(globalThis.localStorage?.getItem(LIP_SYNC_KEY) ?? 0);

    return Number.isFinite(value)
      ? Math.min(LIP_SYNC_MAX_MS, Math.max(0, value))
      : 0;
  } catch {
    return 0;
  }
}

function saveLipSync(value: number): void {
  try {
    globalThis.localStorage?.setItem(LIP_SYNC_KEY, String(value));
  } catch {
    // The offset applies for this visit only.
  }
}

const lines = computed(() => state.suite?.lines ?? []);

const activeLines = computed(() =>
  activeIndices.value.flatMap((index) => {
    const line = lines.value[index];

    return line ? [line] : [];
  }),
);

const nextLine = computed(() => {
  const last = activeIndices.value[activeIndices.value.length - 1];

  return last === undefined ? undefined : lines.value[last + 1];
});

// The QR code opens this Host's Remote with the PIN, where a paired Remote approves the TV in one tap.
const approvalCode = computed(() => {
  if (state.pin === null || typeof location === 'undefined') return null;

  return renderSVG(`${location.origin}/?stage=${state.pin}`, {
    border: 2,
    ecc: 'M',
  });
});

const pinSeconds = computed(() => {
  if (state.pinExpiresAt === null) return null;

  return Math.max(0, Math.ceil((state.pinExpiresAt - Date.now()) / 1_000));
});

const artwork = computed(() => state.suite?.artworkUrl ?? null);
const motion = computed(() => state.suite?.motionUrl ?? null);
const quality = computed(() => state.suite?.quality ?? null);

const driftStyle = computed(() => {
  const offset = driftOffset(driftStep.value);

  return {
    transform: `translate3d(${offset.x * 18}px, ${offset.y * 18}px, 0)`,
  };
});

function motionElement(slot: MotionSlot): HTMLVideoElement | null {
  return slot === 'a' ? motionA.value : motionB.value;
}

// Motion loops crossfade between two elements. The idle one loads the next clip, and it becomes visible in one frame
// once it can play, so the picture never shows a blank frame between tracks.
watch(motion, (url) => {
  if (!url) return;
  loadingMotion = activeMotion.value === 'a' ? 'b' : 'a';
  const element = motionElement(loadingMotion);

  if (!element) return;
  element.src = url;
  element.load();
});

function onMotionReady(slot: MotionSlot): void {
  if (slot !== loadingMotion) return;
  loadingMotion = null;
  activeMotion.value = slot;
  void motionElement(slot)
    ?.play()
    .catch(() => {});
  motionElement(slot === 'a' ? 'b' : 'a')?.pause();
}

function positionNow(): number {
  if (state.video && video.value && !video.value.paused)
    return video.value.currentTime * 1_000;

  if (!controller || !state.suite) return 0;

  return controller.clock.positionAt(performance.now(), state.suite.durationMs);
}

function frameLoop(): void {
  const position = positionNow();
  const nudge = state.video?.userOffsetMs ?? 0;

  const indices = activeLineIndices(
    lines.value,
    lyricPositionMs(position, lipSyncMs.value, nudge),
  );

  if (indices.join(',') !== activeIndices.value.join(','))
    activeIndices.value = indices;
  frameHandle = requestAnimationFrame(frameLoop);
}

function wake(): void {
  if (!('wakeLock' in navigator) || wakeLock) return;
  navigator.wakeLock
    .request('screen')
    .then((sentinel) => {
      wakeLock = sentinel;
      sentinel.addEventListener('release', () => (wakeLock = null));
    })
    .catch(() => {});
}

function releaseWake(): void {
  void wakeLock?.release();
  wakeLock = null;
}

watch(
  () => state.playing,
  (playing) => {
    if (playing) wake();
    else releaseWake();
  },
);

function flash(message: string): void {
  notice.value = message;

  if (noticeTimer !== null) clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => (notice.value = null), 1_600);
}

function showChrome(): void {
  chromeVisible.value = true;

  if (idleTimer !== null) clearTimeout(idleTimer);

  if (touch) return;
  idleTimer = setTimeout(() => (chromeVisible.value = false), IDLE_HIDE_MS);
}

function togglePlayback(): void {
  controller?.command(state.playing ? 'playback.pause' : 'playback.resume');
}

function nudgeLipSync(direction: 1 | -1): void {
  lipSyncMs.value = Math.min(
    LIP_SYNC_MAX_MS,
    Math.max(0, lipSyncMs.value + direction * LIP_SYNC_STEP_MS),
  );
  saveLipSync(lipSyncMs.value);
  flash(`Lip sync ${lipSyncMs.value} ms`);
}

function onKey(event: KeyboardEvent): void {
  showChrome();
  void controller?.unlock();

  switch (event.key) {
    case 'Enter':
    case ' ':
    case 'MediaPlayPause':
      togglePlayback();
      break;
    case 'MediaPlay':
      controller?.command('playback.resume');
      break;
    case 'MediaPause':
      controller?.command('playback.pause');
      break;
    case 'ArrowRight':
    case 'MediaTrackNext':
      controller?.command('playback.skip');
      break;
    case 'ArrowLeft':
    case 'MediaTrackPrevious':
      controller?.command('playback.previous');
      break;
    case 'ArrowUp':
      nudgeLipSync(1);
      break;
    case 'ArrowDown':
      nudgeLipSync(-1);
      break;
    default:
      return;
  }

  event.preventDefault();
}

function onPointer(): void {
  showChrome();
  void controller?.unlock();
}

onMounted(() => {
  controller = new StageController(() => {
    if (controller) Object.assign(state, controller.state);
  });
  Object.assign(state, controller.state);
  controller.start();
  frameHandle = requestAnimationFrame(frameLoop);
  window.addEventListener('keydown', onKey);
  window.addEventListener('pointerdown', onPointer);
  driftTimer = setInterval(() => (driftStep.value += 1), DRIFT_INTERVAL_MS);
  showChrome();
});

onBeforeUnmount(() => {
  cancelAnimationFrame(frameHandle);
  window.removeEventListener('keydown', onKey);
  window.removeEventListener('pointerdown', onPointer);

  if (driftTimer !== null) clearInterval(driftTimer);

  if (idleTimer !== null) clearTimeout(idleTimer);

  if (noticeTimer !== null) clearTimeout(noticeTimer);
  releaseWake();
  controller?.stop();
});
</script>

<template>
  <main
    class="stage"
    :class="{ 'chrome-hidden': !chromeVisible }"
    aria-label="Cadenza TV stage"
  >
    <div class="backdrop" aria-hidden="true">
      <img v-if="artwork" :src="artwork" alt="" class="artwork" />
      <video
        ref="motionA"
        class="motion"
        :class="{ active: activeMotion === 'a' }"
        muted
        loop
        playsinline
        @canplay="onMotionReady('a')"
      />
      <video
        ref="motionB"
        class="motion"
        :class="{ active: activeMotion === 'b' }"
        muted
        loop
        playsinline
        @canplay="onMotionReady('b')"
      />
    </div>

    <video
      v-if="state.video"
      ref="video"
      class="karaoke-video"
      :src="state.video.mediaUrl"
      autoplay
      playsinline
    />

    <section
      v-if="state.phase === 'pairing'"
      class="centered"
      aria-live="polite"
    >
      <p class="title">Approve this TV</p>
      <div
        v-if="approvalCode"
        class="qr"
        aria-hidden="true"
        v-html="approvalCode"
      />
      <p class="pin" aria-label="Pairing PIN">{{ state.pin }}</p>
      <p class="hint">
        Approve it in Cadenza on your Mac, or from a paired Cadenza Remote, and
        enter this code.
        <span v-if="pinSeconds !== null"
          >The code expires in {{ pinSeconds }} s.</span
        >
      </p>
    </section>

    <section
      v-else-if="state.suite === null"
      class="centered"
      aria-live="polite"
    >
      <p class="title">
        {{
          state.phase === 'offline'
            ? 'Reconnecting to Cadenza'
            : 'Waiting for music'
        }}
      </p>
      <p class="hint">
        {{
          state.phase === 'offline'
            ? 'This TV reconnects automatically when the Mac is back on the network.'
            : 'Play something on your Mac to start.'
        }}
      </p>
    </section>

    <section v-else class="now" :style="driftStyle">
      <div class="meta">
        <p class="track">{{ state.suite.title }}</p>
        <p class="artist">{{ state.suite.artist }}</p>
        <p v-if="quality" class="badge">{{ quality }}</p>
      </div>
      <div v-if="activeLines.length > 0" class="lyrics">
        <p
          v-for="line in activeLines"
          :key="line.id"
          class="line"
          :class="{
            end: line.align === 'end',
            center: line.align === 'center',
          }"
        >
          {{ line.text }}
        </p>
        <p v-if="activeLines[0]?.translation" class="translation">
          {{ activeLines[0].translation }}
        </p>
        <p v-if="nextLine" class="next">{{ nextLine.text }}</p>
      </div>
    </section>

    <div v-if="notice" class="notice" role="status">{{ notice }}</div>
    <div v-if="state.error" class="notice error" role="alert">
      {{ state.error }}
    </div>

    <nav v-if="touch && state.suite" class="transport" aria-label="Playback">
      <button
        type="button"
        aria-label="Previous"
        @click="controller?.command('playback.previous')"
      >
        Previous
      </button>
      <button
        type="button"
        :aria-label="state.playing ? 'Pause' : 'Play'"
        @click="togglePlayback"
      >
        {{ state.playing ? 'Pause' : 'Play' }}
      </button>
      <button
        type="button"
        aria-label="Next"
        @click="controller?.command('playback.skip')"
      >
        Next
      </button>
    </nav>
  </main>
</template>

<style scoped>
.stage {
  position: fixed;
  inset: 0;
  overflow: hidden;
  background: #000;
  color: #f5f5f7;
  font-family: var(--font-display, system-ui), system-ui, sans-serif;
}

.stage.chrome-hidden {
  cursor: none;
}

.backdrop,
.motion,
.artwork,
.karaoke-video {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
}

.artwork,
.motion {
  object-fit: cover;
}

.artwork {
  filter: blur(40px) brightness(0.45);
  transform: scale(1.12);
}

.motion {
  opacity: 0;
}

.motion.active {
  opacity: 0.55;
}

.karaoke-video {
  object-fit: contain;
  background: #000;
}

.centered {
  position: absolute;
  inset: 0;
  display: grid;
  place-content: center;
  justify-items: center;
  gap: 1.25rem;
  text-align: center;
  padding: 0 16px;
}

.qr {
  width: clamp(160px, 22vh, 260px);
  height: clamp(160px, 22vh, 260px);
  border-radius: 16px;
  background: #fff;
  overflow: hidden;
}

.qr :deep(svg) {
  display: block;
  width: 100%;
  height: 100%;
}

.pin {
  font-size: clamp(5rem, 14vw, 11rem);
  font-weight: 700;
  letter-spacing: 0.12em;
  font-variant-numeric: tabular-nums;
  margin: 0;
}

.title {
  font-size: clamp(2rem, 4vw, 3.25rem);
  font-weight: 650;
  margin: 0;
}

.hint {
  color: rgb(245 245 247 / 0.7);
  font-size: clamp(1rem, 1.6vw, 1.5rem);
  max-width: 34ch;
  margin: 0;
}

.now {
  position: absolute;
  left: clamp(24px, 5vw, 80px);
  right: clamp(24px, 5vw, 80px);
  bottom: clamp(28px, 6vh, 96px);
  display: grid;
  gap: 1.5rem;
  transition: transform 0.6s var(--ease-standard, ease);
}

.meta {
  display: grid;
  gap: 0.35rem;
}

.track {
  font-size: clamp(1.75rem, 3.2vw, 2.75rem);
  font-weight: 650;
  margin: 0;
}

.artist {
  color: rgb(245 245 247 / 0.7);
  font-size: clamp(1.1rem, 1.8vw, 1.6rem);
  margin: 0;
}

.badge {
  justify-self: start;
  margin: 0.25rem 0 0;
  padding: 0.25rem 0.75rem;
  border-radius: 999px;
  background: rgb(255 255 255 / 0.14);
  font-size: clamp(0.85rem, 1.2vw, 1.1rem);
}

.lyrics {
  display: grid;
  gap: 0.4rem;
}

.line {
  margin: 0;
  font-size: clamp(2rem, 4.6vw, 4rem);
  font-weight: 700;
  line-height: 1.12;
  text-shadow: 0 2px 18px rgb(0 0 0 / 0.55);
}

.line.end {
  text-align: right;
}

.line.center {
  text-align: center;
}

.translation {
  margin: 0;
  color: rgb(245 245 247 / 0.78);
  font-size: clamp(1.25rem, 2.4vw, 2rem);
}

.next {
  margin: 0;
  color: rgb(245 245 247 / 0.45);
  font-size: clamp(1.25rem, 2.2vw, 1.9rem);
}

.notice {
  position: absolute;
  top: 24px;
  right: 24px;
  padding: 0.6rem 1rem;
  border-radius: 12px;
  background: rgb(20 20 24 / 0.8);
  font-size: 1rem;
}

.notice.error {
  color: #ff8a8a;
}

.transport {
  position: absolute;
  left: 50%;
  bottom: 24px;
  transform: translateX(-50%);
  display: flex;
  gap: 12px;
  transition: opacity 0.3s var(--ease-standard, ease);
}

.transport button {
  min-width: 96px;
  min-height: 56px;
  border: none;
  border-radius: 999px;
  background: rgb(255 255 255 / 0.14);
  color: inherit;
  font-size: 1.1rem;
}

.chrome-hidden .transport {
  opacity: 0;
  pointer-events: none;
}
</style>
