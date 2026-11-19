<script setup lang="ts">
import {
  computed,
  nextTick,
  onMounted,
  onUnmounted,
  ref,
  shallowRef,
  watch,
} from 'vue';
import {
  activeLineIndices,
  sweepEdgeWidth,
  sweepTargets,
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

// The newest active line is the one that started last. The view keeps it centred.
const newestIndex = computed(() => activeIndices.value.at(-1) ?? -1);

// Every word that is sounding sweeps, in every active line. The keys follow the live clock, so a sweep starts on the
// frame its word starts. The sets are replaced only when their members change, so most frames cause no render.
const sweepingKeys = shallowRef<ReadonlySet<string>>(new Set());

// A word that stops sweeping finishes over a short ease, so a handoff between overlapping lines does not snap.
const finishingKeys = shallowRef<ReadonlySet<string>>(new Set());

let sweepSignature = '';
let sweepingLines = new Set<number>();

function wordClass(lineIndex: number, wordIndex: number): string | undefined {
  const key = `${lineIndex}:${wordIndex}`;

  if (sweepingKeys.value.has(key)) return 'sweeping';

  return finishingKeys.value.has(key) ? 'finishing' : undefined;
}

function publishSweeps(targets: { line: number; word: number }[]): void {
  const keys = targets.map((target) => `${target.line}:${target.word}`);
  const signature = keys.join(' ');

  if (signature === sweepSignature) return;
  sweepSignature = signature;
  const next = new Set(keys);

  finishingKeys.value = new Set(
    [...sweepingKeys.value].filter((key) => !next.has(key)),
  );
  sweepingKeys.value = next;
}

// Word elements by line, read once per set of lines rather than on every frame.
let wordElements: HTMLElement[][] = [];

function collectWordElements(): void {
  const root = container.value;

  wordElements =
    root === null
      ? []
      : Array.from(root.querySelectorAll<HTMLElement>('.line'), (line) =>
          Array.from(line.querySelectorAll<HTMLElement>('.word')),
        );
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

function writeLine(
  lineIndex: number,
  position: number,
  sweeping: boolean,
): void {
  const line = props.lines[lineIndex];
  const elements = wordElements[lineIndex];

  if (line === undefined || elements === undefined) return;
  const fills = wordFills(line, position, sweeping);

  elements.forEach((element, wordIndex) => {
    const fill = fills[wordIndex] ?? 0;

    writeWordFill(element, fill, sweeping ? sweepEdgeWidth(fill) : 0);
  });
}

// A frame touches only the lines that sweep now and the ones that swept on the last frame, which settle to whole words.
// Every line is written when the lines or the position tick change, which also covers a seek.
function syncWordFills(everyLine: boolean): void {
  if (container.value === null || !props.wordTimed) return;

  const position = props.livePositionMs();
  const targets = sweepTargets(props.lines, position);

  publishSweeps(targets);
  const sweeping = new Set(targets.map((target) => target.line));

  const touched = everyLine
    ? props.lines.keys()
    : new Set([...sweeping, ...sweepingLines]);

  for (const lineIndex of touched) {
    writeLine(lineIndex, position, sweeping.has(lineIndex));
  }

  sweepingLines = sweeping;
}

// One frame loop drives the sweep while the music plays and the page is visible. Otherwise the view syncs on each
// position or line change instead, so a paused or hidden page does no per-frame work.
let frameRequest: number | null = null;

function frameLoop(): void {
  syncWordFills(false);
  frameRequest = requestAnimationFrame(frameLoop);
}

function startFrames(): void {
  if (frameRequest === null && props.wordTimed && !document.hidden) {
    frameRequest = requestAnimationFrame(frameLoop);
  }
}

function stopFrames(): void {
  if (frameRequest !== null) cancelAnimationFrame(frameRequest);
  frameRequest = null;
}

function onVisibilityChange(): void {
  if (document.hidden) {
    stopFrames();

    return;
  }

  syncWordFills(true);

  if (props.playing) startFrames();
}

watch(
  () => props.playing,
  (playing) => {
    if (playing) {
      startFrames();

      return;
    }

    stopFrames();
    syncWordFills(true);
  },
);

watch(
  [() => props.lines, () => props.wordTimed],
  () => {
    collectWordElements();
    sweepSignature = '';
    sweepingLines = new Set();
    syncWordFills(true);

    if (props.playing) startFrames();
  },
  { flush: 'post' },
);

watch(
  () => props.positionMs,
  () => {
    syncWordFills(true);
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

// 'active' is a sounding line, 'near' is one line away from one, and 'far' is anything else. Worked out once per
// position change for all lines, not once per line and binding.
const tiers = computed<LyricTier[]>(() => {
  if (!props.timed) return props.lines.map(() => 'plain');

  const active = new Set(activeIndices.value);

  return props.lines.map((_line, index) => {
    if (active.has(index)) return 'active';

    return active.has(index - 1) || active.has(index + 1) ? 'near' : 'far';
  });
});

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
  collectWordElements();
  syncWordFills(true);

  if (props.playing) startFrames();
  document.addEventListener('visibilitychange', onVisibilityChange);
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
  document.removeEventListener('visibilitychange', onVisibilityChange);
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
      :class="[tiers[index], { 'align-end': line.align === 'end' }]"
      :style="{ '--lyric-tier': tierNumbers[tiers[index] ?? 'far'] }"
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

/* A second voice sits on the right. Its words still sweep and recede like any other line, and it grows from its own edge. */
.line.align-end {
  text-align: right;
  transform-origin: right center;
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
   every frame from the playback clock. Every sounding word blends across --soft on either side of its fill, so its edge is
   soft, and words on overlapping lines or voices sweep together. Words that are not sounding change at once. */
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

/* A word that stops sweeping completes over 150 ms, so it does not snap to whole. */
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
