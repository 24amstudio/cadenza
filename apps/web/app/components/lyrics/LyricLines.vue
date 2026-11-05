<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue';
import { activeLineIndices, wordFills } from '~/lib/lyrics';
import type { LyricLine } from '~/lib/protocol/types';
import { lyricsScales, type LyricsSize } from '~/stores/preferences';

const props = defineProps<{
  lines: LyricLine[];
  positionMs: number;
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

const wordFillsByLine = computed(() =>
  props.lines.map((line, index) =>
    props.wordTimed
      ? wordFills(line, props.positionMs, index === newestIndex.value)
      : [],
  ),
);

// 'active' is a sounding line, 'near' is one line away from one, and 'far' is anything else.
function tierOf(index: number): 'plain' | 'active' | 'near' | 'far' {
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
      :class="[tierOf(index), { sweeping: index === newestIndex }]"
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
            :style="{
              '--fill': `${wordFillsByLine[index]?.[wordIndex] ?? 0}%`,
            }"
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
/* Animated colour stops need a registered property, so the sweep across a word can ease between position updates. */
@property --fill {
  syntax: '<percentage>';
  inherits: false;
  initial-value: 0%;
}

.lyrics {
  --ease-lyric: cubic-bezier(0.22, 1, 0.36, 1);
  display: grid;
  gap: 12px;
  max-width: min(100%, 1200px);
  margin: 0 auto;
  padding: 36vh 0 40vh;
}

.line {
  padding: 24px 0;
  transform-origin: left center;
  transition:
    opacity 700ms var(--ease-lyric),
    filter 700ms var(--ease-lyric),
    transform 900ms var(--ease-lyric);
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

.plain {
  opacity: 1;
}

.lyrics.timed .near {
  opacity: 0.55;
  filter: blur(1.5px);
  transform: scale(0.985);
}

.lyrics.timed .far {
  opacity: 0.3;
  filter: blur(3px);
  transform: scale(0.96);
}

.lyrics.timed .active {
  opacity: 1;
  filter: none;
  transform: scale(1.04);
}

.lyrics.timed .active .line-text {
  color: var(--color-text);
}

/* Sung words fill from the left in the text colour; words still to come stay in the tertiary colour. */
.lyrics.timed .word {
  background-image: linear-gradient(
    90deg,
    var(--color-text) var(--fill),
    var(--color-text-tertiary) var(--fill)
  );
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

/* Only the sweeping line animates its fill. Position updates arrive every 250 ms, so the sweep eases over that step. */
.lyrics.timed .line.sweeping .word {
  transition: --fill 250ms linear;
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
  .word {
    transition: none;
  }
}
</style>
