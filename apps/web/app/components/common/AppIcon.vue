<script setup lang="ts">
import { computed } from 'vue';

export type IconName =
  | 'play'
  | 'pause'
  | 'previous'
  | 'next'
  | 'lyrics'
  | 'queue'
  | 'now'
  | 'settings'
  | 'speaker'
  | 'refresh'
  | 'qr'
  | 'host'
  | 'check'
  | 'fullscreen'
  | 'collapse';

// Paths are drawn on a 24-unit grid. Transport glyphs are solid; everything else is a 1.8-unit outline.
const iconPaths: Record<IconName, string[]> = {
  play: [
    'M8 5.6v12.8c0 .8.9 1.3 1.6.9l10.2-6.4c.6-.4.6-1.3 0-1.7L9.6 4.7C8.9 4.3 8 4.8 8 5.6Z',
  ],
  pause: ['M7 5.5h3.5v13H7zM13.5 5.5H17v13h-3.5z'],
  previous: [
    'M6 5.5h2.2v13H6zM18.8 6.2v11.6c0 .8-.9 1.3-1.6.9l-8.9-5.8a1 1 0 0 1 0-1.8l8.9-5.8c.7-.4 1.6.1 1.6.9Z',
  ],
  next: [
    'M16 5.5h2.2v13H16zM5.2 6.2v11.6c0 .8.9 1.3 1.6.9l8.9-5.8a1 1 0 0 0 0-1.8L6.8 5.3c-.7-.4-1.6.1-1.6.9Z',
  ],
  lyrics: ['M4.5 5.5h15v10h-8.2l-3.8 3v-3h-3Z', 'M8 9.5h8', 'M8 12.5h5'],
  queue: [
    'M4 6.5h9',
    'M4 11.5h9',
    'M4 16.5h5',
    'M16.5 14.2v-4.4a.6.6 0 0 1 .9-.5l3.6 2.2a.6.6 0 0 1 0 1l-3.6 2.2a.6.6 0 0 1-.9-.5Z',
  ],
  now: [
    'M9 17.5V6.2l10-2v11.3',
    'M9 17.5a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0',
    'M19 15.5a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0',
  ],
  settings: [
    'M4 7h9',
    'M17 7h3',
    'M4 17h3',
    'M11 17h9',
    'M15 7a2 2 0 1 1-4 0a2 2 0 1 1 4 0Z',
    'M9 17a2 2 0 1 1-4 0a2 2 0 1 1 4 0Z',
  ],
  speaker: [
    'M4 9.5h3.2L12 6v12l-4.8-3.5H4Z',
    'M15.5 9.2a4 4 0 0 1 0 5.6',
    'M18.2 6.6a7.8 7.8 0 0 1 0 10.8',
  ],
  refresh: ['M19 12a7 7 0 1 1-2.1-5', 'M19 4.8V8.6h-3.8'],
  qr: [
    'M4 4h6v6H4z',
    'M14 4h6v6h-6z',
    'M4 14h6v6H4z',
    'M14 14h2v2h-2z',
    'M18 14h2v6h-6v-2',
  ],
  host: ['M3.5 5.5h17v11h-17z', 'M9 19.5h6', 'M12 16.5v3'],
  check: ['M5 12.5l4.5 4.5L19 7.5'],
  fullscreen: [
    'M4 9V4.5h4.5',
    'M15.5 4.5H20V9',
    'M20 15v4.5h-4.5',
    'M8.5 19.5H4V15',
  ],
  collapse: ['M6 9.5l6 6 6-6'],
};

const solid = new Set<IconName>(['play', 'pause', 'previous', 'next']);

const props = defineProps<{ name: IconName }>();

const paths = computed(() => iconPaths[props.name]);
const filled = computed(() => solid.has(props.name));
</script>

<template>
  <svg
    class="icon"
    :class="{ solid: filled }"
    viewBox="0 0 24 24"
    aria-hidden="true"
    focusable="false"
  >
    <path v-for="d in paths" :key="d" :d="d" />
  </svg>
</template>

<style scoped>
.icon {
  width: 1em;
  height: 1em;
  flex: none;
  fill: none;
  stroke: currentColor;
  stroke-width: 1.8;
  stroke-linecap: round;
  stroke-linejoin: round;
}

.icon.solid {
  fill: currentColor;
  stroke: none;
}
</style>
