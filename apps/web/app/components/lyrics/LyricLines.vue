<script setup lang="ts">
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { activeLineIndex, activeWordIndex } from '~/lib/lyrics';
import type { LyricLine, LyricWord } from '~/lib/protocol/types';

const props = defineProps<{
  lines: LyricLine[];
  positionMs: number;
  timed: boolean;
  wordTimed: boolean;
}>();

const container = ref<HTMLElement | null>(null);

const activeIndex = computed(() =>
  props.timed ? activeLineIndex(props.lines, props.positionMs) : -1,
);

const activeWord = computed(() => {
  const line = props.lines[activeIndex.value];

  return line === undefined || !props.wordTimed
    ? -1
    : activeWordIndex(line, props.positionMs);
});

// Following starts as soon as the view opens and on every line change, without waiting for a manual scroll.
function follow(): void {
  container.value
    ?.querySelector('.line.active')
    ?.scrollIntoView({ block: 'center', behavior: 'smooth' });
}

watch(activeIndex, async () => {
  await nextTick();
  follow();
});

onMounted(() => {
  follow();
});

function lineClass(index: number): string {
  if (!props.timed) return 'plain';
  const distance = Math.abs(index - activeIndex.value);

  if (index === activeIndex.value) return 'active';

  return distance === 1 ? 'near' : 'far';
}

function wordClass(index: number): string {
  if (index < activeWord.value) return 'passed';

  if (index === activeWord.value) return 'current';

  return 'upcoming';
}

// Word text from the Host may or may not include its trailing space, so the separator is added only when missing.
function wordLabel(word: LyricWord): string {
  return /\s$/.test(word.text) ? word.text : `${word.text} `;
}
</script>

<template>
  <div ref="container" class="lyrics" :class="{ timed }">
    <div
      v-for="(line, index) in lines"
      :key="line.id"
      class="line"
      :class="lineClass(index)"
    >
      <p class="line-text">
        <template v-if="wordTimed && index === activeIndex">
          <span
            v-for="(word, wordIndex) in line.words"
            :key="`${line.id}-${wordIndex}`"
            class="word"
            :class="wordClass(wordIndex)"
            >{{ wordLabel(word) }}</span
          >
        </template>
        <template v-else>{{ line.text }}</template>
      </p>
      <p v-if="line.translation" class="translation">{{ line.translation }}</p>
    </div>
  </div>
</template>

<style scoped>
.lyrics {
  display: grid;
  gap: 6px;
  max-width: 680px;
  margin: 0 auto;
  padding: 36vh 0 40vh;
}

.line {
  padding: 8px 0;
  transition:
    opacity 420ms var(--ease-standard),
    filter 420ms var(--ease-standard),
    transform 420ms var(--ease-standard);
  transform-origin: left center;
}

.line-text {
  font-family: var(--font-display);
  font-size: clamp(24px, 4.2vw, 34px);
  font-weight: 700;
  line-height: 1.18;
  letter-spacing: -0.015em;
  overflow-wrap: anywhere;
}

.translation {
  margin-top: 4px;
  color: var(--color-text-secondary);
  font-size: 17px;
}

.plain {
  opacity: 1;
}

.lyrics.timed .near {
  opacity: 0.5;
  filter: blur(0.6px);
}

.lyrics.timed .far {
  opacity: 0.3;
  filter: blur(2px);
}

.lyrics.timed .active {
  opacity: 1;
  filter: none;
  transform: scale(1.02);
}

.lyrics.timed .active .line-text {
  color: var(--color-text);
}

.word {
  transition: opacity 240ms var(--ease-standard);
}

.word.upcoming {
  opacity: 0.38;
}

.word.current {
  color: var(--color-accent);
}

.word.passed {
  opacity: 1;
}

@media (prefers-reduced-motion: reduce) {
  .line,
  .word {
    transition: none;
  }
}
</style>
