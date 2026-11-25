<script setup lang="ts">
import { onBeforeUnmount, ref, watch } from 'vue';
import { hostUnderPressure } from '~/lib/host/hostBudget';
import { useHostStore } from '~/stores/host';

// A muted, looping motion video behind an artist's header. The Host fetches it from Apple, so the browser never contacts
// Apple's motion CDN. Over Bluetooth, under thermal pressure, or with reduced motion, the header keeps its artwork.
const props = defineProps<{ artistName: string }>();

const host = useHostStore();
const videoUrl = ref<string | null>(null);

const reducedMotion = window.matchMedia(
  '(prefers-reduced-motion: reduce)',
).matches;

// Each change of artist starts a new attempt, so a video that arrives late cannot replace the artist on screen now.
let attempt = 0;

function release(): void {
  if (videoUrl.value !== null) URL.revokeObjectURL(videoUrl.value);
  videoUrl.value = null;
}

watch(
  () => props.artistName,
  async (artistName) => {
    release();
    const current = ++attempt;

    // The Host refuses an empty or over-long name, so the page never asks with one.
    if (
      artistName.trim() === '' ||
      artistName.length > 200 ||
      reducedMotion ||
      host.bluetoothState === 'linked' ||
      hostUnderPressure(host.snapshot?.hostBudget)
    )
      return;

    const video = await host.artistMotion(artistName);

    if (current !== attempt || video === null) return;

    videoUrl.value = URL.createObjectURL(
      new Blob([video], { type: 'video/mp4' }),
    );
  },
  { immediate: true },
);

onBeforeUnmount(() => {
  attempt++;
  release();
});
</script>

<template>
  <div v-if="videoUrl !== null" class="backdrop" aria-hidden="true">
    <video
      :src="videoUrl"
      autoplay
      loop
      muted
      playsinline
      disablepictureinpicture
    />
    <div class="scrim" />
  </div>
</template>

<style scoped>
.backdrop {
  position: absolute;
  inset: 0;
  z-index: 0;
  overflow: hidden;
  border-radius: 24px;
  pointer-events: none;
}

.backdrop video {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

/* The scrim fades into the page, so the artist's name stays readable over any frame of the video. */
.scrim {
  position: absolute;
  inset: 0;
  background: linear-gradient(
    to bottom,
    transparent 20%,
    var(--color-canvas) 100%
  );
}
</style>
