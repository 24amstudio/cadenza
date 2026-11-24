<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import LyricLines from '~/components/lyrics/LyricLines.vue';
import LyricNudge from '~/components/lyrics/LyricNudge.vue';
import { lyricsLevel } from '~/lib/lyrics';
import { lyricClockMs, syncFirstLineDelay } from '~/lib/lyricNudge';
import { useHostStore } from '~/stores/host';
import { usePreferencesStore } from '~/stores/preferences';

const props = withDefaults(defineProps<{ immersive?: boolean }>(), {
  immersive: false,
});

const emit = defineEmits<{ expand: [] }>();

const host = useHostStore();
const preferences = usePreferencesStore();

const root = ref<HTMLElement | null>(null);
const level = computed(() => lyricsLevel(host.lyricsDocument));

// The timing nudge belongs to one occurrence, so the next song starts with no delay.
const delayMs = ref(0);

watch(
  () => host.lyricsDocument?.occurrenceId,
  () => {
    delayMs.value = 0;
  },
);

const lyricPositionMs = computed(() =>
  lyricClockMs(host.positionMs, delayMs.value),
);

// LyricLines reads this on every animation frame, so it stays a reader rather than a computed value.
function lyricLivePositionMs(): number {
  return lyricClockMs(host.livePositionMs(), delayMs.value);
}

const firstTimedLineStartMs = computed(
  () => host.lyricsDocument?.lines[0]?.startMs ?? null,
);

function syncFirstLine(): void {
  if (firstTimedLineStartMs.value === null) return;
  delayMs.value = syncFirstLineDelay(
    firstTimedLineStartMs.value,
    host.positionMs,
  );
}

// A tapped line carries lyric time, so the playback position it seeks to is that time plus the delay.
function seekLyric(lyricMs: number): void {
  host.seekTo(lyricMs + delayMs.value);
}

// Brings the panel to the top of the page. The lyrics inside then follow playback in their own scroll box.
function reveal(): void {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  root.value?.scrollIntoView({
    behavior: reduced ? 'auto' : 'smooth',
    block: 'start',
  });
}

defineExpose({ reveal });
</script>

<template>
  <section
    ref="root"
    class="lyrics-panel"
    :class="{ immersive: props.immersive }"
    :aria-labelledby="props.immersive ? undefined : 'lyrics-heading'"
    :aria-label="props.immersive ? 'Lyrics' : undefined"
  >
    <header v-if="!props.immersive" class="section-header">
      <h2 id="lyrics-heading">Lyrics</h2>
      <button
        class="icon-button"
        type="button"
        aria-label="Full screen"
        @click="emit('expand')"
      >
        <AppIcon name="fullscreen" />
      </button>
    </header>

    <LyricNudge
      v-if="level >= 2"
      :delay-ms="delayMs"
      :can-sync-first-line="firstTimedLineStartMs !== null"
      @update:delay-ms="delayMs = $event"
      @sync-first-line="syncFirstLine"
    />

    <Transition name="fade" mode="out-in">
      <div v-if="host.lyricsLoading" key="loading" class="lyrics-loading">
        <p class="visually-hidden" role="status">
          Cadenza Host is getting the lyrics for this song.
        </p>
        <span class="lyrics-bar skeleton" aria-hidden="true"></span>
        <span class="lyrics-bar skeleton" aria-hidden="true"></span>
        <span class="lyrics-bar skeleton" aria-hidden="true"></span>
        <span class="lyrics-bar skeleton" aria-hidden="true"></span>
      </div>
      <div v-else-if="host.lyricsDocument" key="lyrics" class="lyrics-scroll">
        <LyricLines
          :lines="host.lyricsDocument.lines"
          :position-ms="lyricPositionMs"
          :live-position-ms="lyricLivePositionMs"
          :playing="host.isPlaying"
          :timed="level >= 2"
          :word-timed="level === 3"
          :size="preferences.lyricsSize"
          @seek="seekLyric"
        />
      </div>
    </Transition>
    <p v-if="host.lyricsDocument?.source === 'lrclib'" class="provider">
      Lyrics from LRCLIB
    </p>
  </section>
</template>

<style scoped>
.lyrics-panel {
  display: grid;
  gap: 8px;
}

/* Bars stand in for lines of lyrics, with the lengths of a typical verse. */
.lyrics-loading {
  display: grid;
  gap: 14px;
  padding: 12px 0;
}

.lyrics-bar {
  width: 72%;
  height: 20px;
  border-radius: 999px;
}

.lyrics-bar:nth-of-type(2) {
  width: 88%;
}

.lyrics-bar:nth-of-type(3) {
  width: 60%;
}

.lyrics-bar:nth-of-type(4) {
  width: 78%;
}

.section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 0 12px;
}

h2 {
  font-family: var(--font-display);
  font-size: 22px;
  font-weight: 700;
  letter-spacing: -0.015em;
}

.icon-button {
  display: grid;
  place-items: center;
  width: 36px;
  height: 36px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill);
  color: var(--color-text);
  font-size: 18px;
}

.icon-button:hover {
  background: var(--color-fill-strong);
}

.provider {
  padding: 0 12px;
  color: var(--color-text-tertiary);
  font-size: 13px;
}

/* The lyric list scrolls inside a fixed window, so the rest of the page keeps its place while the lyrics follow. */
/* The active line scales slightly, so horizontal overflow is clipped rather than shown as a scrollbar. */
.lyrics-scroll {
  height: clamp(300px, 58vh, 620px);
  overflow-x: hidden;
  overflow-y: auto;
}

/* The lyric list uses the full width of the page, so its lines line up with the artwork above. */
.lyrics-panel :deep(.lyrics) {
  max-width: none;
  margin: 0;
}

/* Full screen: the lyrics fill the column beside the song data. */
.lyrics-panel.immersive {
  grid-template-rows: minmax(0, 1fr) auto;
  height: 100%;
  min-height: 0;
}

/* Full screen shows no scrollbar. The top and bottom 48 px of the box fade, so cut-off lines have no hard edge. */
.lyrics-panel.immersive .lyrics-scroll {
  height: 100%;
  min-height: 0;
  scrollbar-width: none;
  mask-image: linear-gradient(
    transparent,
    #000 48px,
    #000 calc(100% - 48px),
    transparent
  );
  -webkit-mask-image: linear-gradient(
    transparent,
    #000 48px,
    #000 calc(100% - 48px),
    transparent
  );
}

.lyrics-panel.immersive .lyrics-scroll::-webkit-scrollbar {
  display: none;
}

/* The list keeps 64 px above and below, so the first and last lines sit clear of the 48 px edge fade. Mid-song the active
   line still sits in the middle, because there are lines on both sides. The list runs the full width and starts at the
   left edge, as in the wide-screen full-screen player. */
.lyrics-panel.immersive :deep(.lyrics) {
  padding: 64px 0;
  max-width: none;
  margin: 0;
  /* Full screen keeps the lines above and below the active one readable, so more of the song shows at once. */
  --lyric-near-opacity: 0.62;
  --lyric-near-blur: 0.5px;
  --lyric-far-opacity: 0.42;
  --lyric-far-blur: 1.2px;
}

/* On a phone the text is large enough to read at a glance, and the lines have room between them. */
@media (max-width: 899px) {
  .lyrics-panel.immersive :deep(.line-text) {
    font-size: 40px;
  }

  .lyrics-panel.immersive :deep(.line) {
    padding: 9px 0;
  }
}
/* Wide-screen full screen sets the lines closer together, as the reference player does. */
@media (min-width: 900px) {
  .lyrics-panel.immersive :deep(.lyrics) {
    gap: 8px;
  }

  .lyrics-panel.immersive :deep(.line) {
    padding: 12px 0;
  }
}
</style>
