<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import type { LyricDocument } from '~/lib/protocol/types';
import { activeLineIndices, lyricsLevel, wordFills } from '~/lib/lyrics';
import {
  nextSingLine,
  singPageClockMs,
  type SingPageState,
} from '~/lib/sing/singPage';
import { connectSingPage } from '~/lib/sing/singPageSocket';

interface ReceivedState {
  state: SingPageState;
  receivedAtMs: number;
}

const token =
  typeof window === 'undefined'
    ? ''
    : (new URLSearchParams(window.location.search).get('token') ?? '');

const received = ref<ReceivedState | null>(null);
const lyrics = ref<LyricDocument | null>(null);
const connected = ref(false);
const now = ref(0);
let frameId = 0;
let disconnect: (() => void) | null = null;

const matchingLyrics = computed<LyricDocument | null>(() => {
  const document = lyrics.value;
  const state = received.value?.state;

  return document !== null && state !== undefined && document.occurrenceId === state.occurrenceId
    ? document
    : null;
});

const level = computed(() => lyricsLevel(matchingLyrics.value));

const clockMs = computed(() => {
  const current = received.value;

  return current === null
    ? 0
    : singPageClockMs(current.state, current.receivedAtMs, now.value);
});

const sounding = computed(() => {
  const document = matchingLyrics.value;

  if (document === null || level.value < 2) return [];

  return activeLineIndices(document.lines, clockMs.value).flatMap((index) => {
    const line = document.lines[index];

    return line === undefined ? [] : [line];
  });
});

const soundingFills = computed(() =>
  sounding.value.map((line) => wordFills(line, clockMs.value, true)),
);

const upcoming = computed(() => {
  const document = matchingLyrics.value;

  return document !== null && level.value >= 2
    ? nextSingLine(document.lines, clockMs.value)
    : null;
});

const untimedLines = computed(() =>
  level.value === 1 ? (matchingLyrics.value?.lines ?? []) : [],
);

const status = computed(() => {
  if (token === '') return 'Open this page from Cadenza Host.';
  if (!connected.value) {
    return received.value === null
      ? 'Connecting to Cadenza Host…'
      : 'Reconnecting to Cadenza Host…';
  }
  if (received.value === null) return 'Waiting for a song.';
  if (matchingLyrics.value !== null && level.value === 0) {
    return 'No lyrics for this song.';
  }

  return '';
});

function tick(): void {
  if (received.value?.state.playing) now.value = performance.now();
  frameId = requestAnimationFrame(tick);
}

onMounted(() => {
  frameId = requestAnimationFrame(tick);
  if (token === '') return;

  const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';

  disconnect = connectSingPage(
    `${scheme}://${window.location.host}/sing/live?token=${encodeURIComponent(token)}`,
    {
      onState: (state, receivedAtMs) => {
        received.value = { state, receivedAtMs };
        now.value = receivedAtMs;
      },
      onLyrics: (document) => {
        lyrics.value = document;
      },
      onConnection: (value) => {
        connected.value = value;
      },
    },
  );
});

onBeforeUnmount(() => {
  cancelAnimationFrame(frameId);
  disconnect?.();
});
</script>

<template>
  <main class="sing" aria-label="Sing lyrics">
    <header class="sing-head">
      <template v-if="received !== null">
        <p class="sing-song">{{ received.state.title }}</p>
        <p class="sing-artist">{{ received.state.artist }}</p>
      </template>
    </header>

    <section v-if="level >= 2" class="sing-stage" aria-label="Lyrics">
      <div
        v-for="(line, lineIndex) in sounding"
        :key="line.id"
        class="sing-line"
      >
        <template v-if="line.words.length > 0">
          <span
            v-for="(word, wordIndex) in line.words"
            :key="wordIndex"
            class="sing-word"
            :style="{
              '--fill': `${soundingFills[lineIndex]?.[wordIndex] ?? 0}%`,
            }"
            >{{ word.text }}</span
          >
        </template>
        <template v-else>{{ line.text }}</template>
        <p v-if="line.translation" class="sing-translation">
          {{ line.translation }}
        </p>
      </div>
      <p v-if="upcoming !== null" class="sing-line sing-line--next">
        {{ upcoming.text }}
      </p>
    </section>

    <section v-else-if="level === 1" class="sing-stage" aria-label="Lyrics">
      <p v-for="(line, index) in untimedLines" :key="index" class="sing-line">
        {{ line.text }}
      </p>
    </section>

    <div v-else class="sing-stage" />

    <p v-if="status !== ''" class="sing-status" role="status">
      {{ status }}
    </p>
  </main>
</template>

<style scoped>
.sing {
  position: fixed;
  inset: 0;
  box-sizing: border-box;
  display: grid;
  grid-template-rows: auto minmax(0, 1fr) auto;
  gap: 24px;
  padding: clamp(16px, 4vw, 56px);
  background: #000;
  color: #f5f5f5;
  overflow: hidden;
}

.sing-head {
  min-width: 0;
}

.sing-song {
  margin: 0;
  font-size: clamp(1rem, 2vw, 1.5rem);
  font-weight: 700;
}

.sing-artist {
  margin: 0;
  font-size: clamp(0.9rem, 1.6vw, 1.2rem);
  opacity: 0.62;
}

.sing-stage {
  min-height: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 0.6em;
  overflow: hidden;
  text-align: center;
}

.sing-line {
  margin: 0;
  max-width: 100%;
  font-size: clamp(1.75rem, 5vw, 5rem);
  font-weight: 700;
  line-height: 1.18;
  text-wrap: balance;
}

.sing-line--next {
  opacity: 0.42;
  font-size: clamp(1.1rem, 2.6vw, 2.4rem);
  font-weight: 600;
}

.sing-word {
  background-image: linear-gradient(
    90deg,
    #fff var(--fill),
    rgba(255, 255, 255, 0.34) var(--fill)
  );
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
  -webkit-box-decoration-break: clone;
  box-decoration-break: clone;
}

.sing-translation {
  margin: 0.25em 0 0;
  font-size: clamp(1rem, 2vw, 1.75rem);
  font-weight: 500;
  opacity: 0.7;
}

.sing-status {
  margin: 0;
  font-size: 1rem;
  opacity: 0.6;
  text-align: center;
}
</style>
