<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import {
  activeLineIndices,
  sweepEdgeWidth,
  sweepTarget,
  wordFills,
} from '~/lib/lyrics';
import type { LyricLine } from '~/lib/protocol/types';
import { lyricsScales, type LyricsSize } from '~/stores/preferences';

const props = defineProps<{
  lines: LyricLine[];
  positionMs: number;
  // Read on every animation frame for the sweep. The tick-driven positionMs only drives the line tiers and the follow.
  livePositionMs: () => number;
  playing: boolean;
  timed: boolean;
  wordTimed: boolean;
  size: LyricsSize;
}>();

const emit = defineEmits<{ seek: [positionMs: number] }>();

const scale = computed(() => lyricsScales[props.size]);

// Timed lines are the only seek targets. Untimed lyrics have no position to jump to.
function seekToLine(line: LyricLine): void {
  if (props.timed) emit('seek', line.startMs);
}

const container = ref<HTMLElement | null>(null);

// Every sounding line is active. A background vocal overlaps its main line, so both can be active at once.
const activeIndices = computed(() =>
  props.timed ? activeLineIndices(props.lines, props.positionMs) : [],
);

// The newest active line is the one that started last. The view keeps it centred, and it is the only line that sweeps.
const newestIndex = computed(() => activeIndices.value.at(-1) ?? -1);

// The sweeping word is the only word that animates. Overlapping lines show their other words whole, with no sweep.
// Its key follows the live clock, so the sweep moves to the next word on the frame that word starts.
const liveSweepKey = ref<string | null>(null);

// The word that stops sweeping finishes over a short ease, so a handoff between overlapping lines does not snap.
const finishingKey = ref<string | null>(null);

watch(liveSweepKey, (_next, previous) => {
  finishingKey.value = previous ?? null;
});

function wordClass(lineIndex: number, wordIndex: number): string | undefined {
  const key = `${lineIndex}:${wordIndex}`;

  if (key === liveSweepKey.value) return 'sweeping';

  return key === finishingKey.value ? 'finishing' : undefined;
}

// Word fills are written to the elements from the live clock. Vue does not bind them, so a re-render cannot overwrite
// a frame's value. A value is written only when it changes.
const writtenFills = new WeakMap<HTMLElement, string>();

function writeWordFill(element: HTMLElement, fill: number, edge: number): void {
  const value = `${fill} ${edge}`;

  if (writtenFills.get(element) === value) return;
  writtenFills.set(element, value);
  element.style.setProperty('--fill', `${fill}%`);
  element.style.setProperty('--soft', `${edge}%`);
}

function syncWordFills(): void {
  const root = container.value;

  if (root === null || !props.wordTimed) return;

  const position = props.livePositionMs();
  const target = sweepTarget(props.lines, position);

  liveSweepKey.value = target === null ? null : `${target.line}:${target.word}`;

  const lineElements = root.querySelectorAll<HTMLElement>('.line');

  props.lines.forEach((line, lineIndex) => {
    const lineElement = lineElements.item(lineIndex);

    if (lineElement === null) return;

    const isSweepLine = target?.line === lineIndex;
    const fills = wordFills(line, position, isSweepLine);

    lineElement
      .querySelectorAll<HTMLElement>('.word')
      .forEach((wordElement, wordIndex) => {
        const fill = fills[wordIndex] ?? 0;
        const sweeping = isSweepLine && target?.word === wordIndex;

        writeWordFill(wordElement, fill, sweeping ? sweepEdgeWidth(fill) : 0);
      });
  });
}

// One frame loop drives the sweep while the music plays. Paused views sync on each position or line change instead.
let frameRequest: number | null = null;

function frameLoop(): void {
  syncWordFills();
  frameRequest = requestAnimationFrame(frameLoop);
}

function startFrames(): void {
  if (frameRequest === null && props.wordTimed) {
    frameRequest = requestAnimationFrame(frameLoop);
  }
}

function stopFrames(): void {
  if (frameRequest !== null) cancelAnimationFrame(frameRequest);
  frameRequest = null;
}

watch(
  () => props.playing,
  (playing) => {
    if (playing) {
      startFrames();

      return;
    }

    stopFrames();
    syncWordFills();
  },
);

watch(
  [() => props.lines, () => props.positionMs],
  () => {
    syncWordFills();
  },
  { flush: 'post' },
);

type LyricTier = 'plain' | 'active' | 'near' | 'far';

// The value the CSS eases between: 0 for active, 1 for near, 2 for far.
const tierNumbers: Record<LyricTier, number> = {
  plain: 0,
  active: 0,
  near: 1,
  far: 2,
};

// 'active' is a sounding line, 'near' is one line away from one, and 'far' is anything else.
function tierOf(index: number): LyricTier {
  if (!props.timed) return 'plain';

  if (activeIndices.value.includes(index)) return 'active';

  const distance = Math.min(
    ...activeIndices.value.map((active) => Math.abs(index - active)),
  );

  return distance === 1 ? 'near' : 'far';
}

// Following eases over about a second rather than jumping, and the user's own scroll takes over until the next line.
const followDurationMs = 950;
let followFrame: number | null = null;

function scrollerOf(element: HTMLElement): HTMLElement | null {
  let node = element.parentElement;

  while (node !== null) {
    const { overflowY } = getComputedStyle(node);

    if (
      (overflowY === 'auto' || overflowY === 'scroll') &&
      node.scrollHeight > node.clientHeight
    ) {
      return node;
    }

    node = node.parentElement;
  }

  return null;
}

function stopFollowing(): void {
  if (followFrame !== null) cancelAnimationFrame(followFrame);
  followFrame = null;
}

function prefersReducedMotion(): boolean {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

function follow(animated: boolean): void {
  const target =
    container.value?.querySelector<HTMLElement>('.line[data-newest]');

  const scroller =
    container.value === null ? null : scrollerOf(container.value);

  if (target === null || target === undefined || scroller === null) return;

  const targetRect = target.getBoundingClientRect();
  const scrollerRect = scroller.getBoundingClientRect();

  const to =
    scroller.scrollTop +
    (targetRect.top - scrollerRect.top) -
    (scroller.clientHeight - targetRect.height) / 2;

  stopFollowing();

  if (!animated || prefersReducedMotion()) {
    scroller.scrollTop = to;

    return;
  }

  const from = scroller.scrollTop;
  const distance = to - from;

  if (Math.abs(distance) < 1) return;
  const started = performance.now();

  const step = (now: number): void => {
    const progress = Math.min(1, (now - started) / followDurationMs);

    scroller.scrollTop = from + distance * (1 - (1 - progress) ** 4);
    followFrame = progress < 1 ? requestAnimationFrame(step) : null;
  };

  followFrame = requestAnimationFrame(step);
}

let userScroller: HTMLElement | null = null;
let resizeObserver: ResizeObserver | null = null;

watch(newestIndex, async () => {
  await nextTick();
  follow(true);
});

onMounted(() => {
  syncWordFills();

  if (props.playing) startFrames();
  follow(false);
  userScroller = container.value ? scrollerOf(container.value) : null;
  userScroller?.addEventListener('wheel', stopFollowing, { passive: true });
  userScroller?.addEventListener('touchstart', stopFollowing, {
    passive: true,
  });

  // The box changes height when the layout does, such as entering full screen. The newest line is centred again.
  if (userScroller) {
    resizeObserver = new ResizeObserver(() => follow(false));
    resizeObserver.observe(userScroller);
  }
});

onUnmounted(() => {
  stopFrames();
  stopFollowing();
  resizeObserver?.disconnect();
  userScroller?.removeEventListener('wheel', stopFollowing);
  userScroller?.removeEventListener('touchstart', stopFollowing);
});
</script>

<template>
  <div
    ref="container"
    class="lyrics"
    :class="[{ timed }, `size-${size}`]"
    :style="{ '--lyrics-scale': scale }"
  >
    <div
      v-for="(line, index) in lines"
      :key="line.id"
      class="line"
      :class="tierOf(index)"
      :style="{ '--lyric-tier': tierNumbers[tierOf(index)] }"
      :data-newest="index === newestIndex ? 'true' : undefined"
      :role="timed ? 'button' : undefined"
      :tabindex="timed ? 0 : undefined"
      @click="seekToLine(line)"
      @keydown.enter="seekToLine(line)"
      @keydown.space.prevent="seekToLine(line)"
    >
      <p class="line-text">
        <template v-if="wordTimed && line.words.length > 0">
          <span
            v-for="(word, wordIndex) in line.words"
            :key="`${line.id}-${wordIndex}`"
            class="word"
            :class="wordClass(index, wordIndex)"
            >{{ word.text }}</span
          >
        </template>
        <template v-else>{{ line.text }}</template>
      </p>
      <p v-if="line.translation" class="translation">{{ line.translation }}</p>
    </div>
  </div>
</template>

<style scoped>
/* The tier is registered so it can ease as one value. Opacity, blur and scale all follow that value. */
@property --lyric-tier {
  syntax: '<number>';
  inherits: false;
  initial-value: 0;
}

/* Animated colour stops need a registered property, so the sweep across a word can ease between position updates. */
@property --fill {
  syntax: '<percentage>';
  inherits: false;
  initial-value: 0%;
}

.lyrics {
  --ease-lyric: cubic-bezier(0.22, 1, 0.36, 1);
  --lyric-near-opacity: 0.55;
  --lyric-far-opacity: 0.3;
  --lyric-near-blur: 1.5px;
  --lyric-far-blur: 3px;
  --lyric-active-scale: 1.04;
  --lyric-near-scale: 0.985;
  --lyric-far-scale: 0.96;
  display: grid;
  gap: 12px;
  max-width: min(100%, 1200px);
  margin: 0 auto;
  padding: 36vh 0 40vh;
}

/* Only the tier eases. Opacity, blur and scale derive from it, so a line that changes tier mid-transition keeps one
   running animation instead of one per property. The derived values are piecewise linear: active at 0, near at 1, far at 2. */
.line {
  padding: 24px 0;
  transform-origin: left center;
  transition: --lyric-tier 700ms var(--ease-lyric);
}

.lyrics.timed .line {
  --lyric-near-step: min(var(--lyric-tier), 1);
  --lyric-far-step: max(var(--lyric-tier) - 1, 0);
  opacity: calc(
    1 + (var(--lyric-near-opacity) - 1) * var(--lyric-near-step) +
      (var(--lyric-far-opacity) - var(--lyric-near-opacity)) *
      var(--lyric-far-step)
  );
  filter: blur(
    calc(
      var(--lyric-near-blur) * var(--lyric-near-step) +
        (var(--lyric-far-blur) - var(--lyric-near-blur)) * var(--lyric-far-step)
    )
  );
  transform: scale(
    calc(
      var(--lyric-active-scale) +
        (var(--lyric-near-scale) - var(--lyric-active-scale)) *
        var(--lyric-near-step) +
        (var(--lyric-far-scale) - var(--lyric-near-scale)) *
        var(--lyric-far-step)
    )
  );
}

/* Reduced effects keep the opacity recede and drop the scale, which is the only transform on a line. */
:root[data-effects='reduced'] .lyrics.timed .line {
  transform: none;
}

.line-text {
  font-family: var(--font-display);
  font-size: calc(clamp(24px, 4.2vw, 34px) * var(--lyrics-scale, 1));
  font-weight: 700;
  line-height: 1.18;
  letter-spacing: -0.015em;
  overflow-wrap: anywhere;
  transition: color 700ms var(--ease-lyric);
}

.lyrics.size-extra-large .line-text {
  font-weight: 400;
}

.translation {
  margin-top: 4px;
  color: var(--color-text-secondary);
  font-size: calc(17px * var(--lyrics-scale, 1));
  transition: opacity 700ms var(--ease-lyric);
}

.line[role='button'] {
  cursor: pointer;
  border-radius: var(--radius-control);
}

.line[role='button']:hover .line-text {
  color: var(--color-text);
}

.lyrics.timed .active .line-text {
  color: var(--color-text);
}

/* Sung words fill from the left in the text colour; words still to come stay in the tertiary colour. The fill is written
   every frame from the playback clock. The sweeping word blends across --soft on either side of its fill, so its edge is
   soft. Every other word changes at once, so overlapping lines do not sweep together. */
.lyrics.timed .word {
  background-image: linear-gradient(
    90deg,
    var(--color-text) max(0%, calc(var(--fill) - var(--soft, 0%))),
    var(--color-text-tertiary) min(100%, calc(var(--fill) + var(--soft, 0%)))
  );
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

/* A word that stops sweeping completes over 150 ms, so a handoff between overlapping lines does not snap. */
.lyrics.timed .word.finishing {
  transition: --fill 150ms ease-out;
}

/* Phones show less text at once, so the wider desktop spacing would scatter the lyrics. */
@media (max-width: 719px) {
  .lyrics {
    gap: 4px;
  }

  .line {
    padding: 4px 0;
  }
}

@media (prefers-reduced-motion: reduce) {
  .line,
  .line-text,
  .translation,
  .lyrics.timed .word.sweeping,
  .lyrics.timed .word.finishing {
    transition: none;
  }
}
</style>
