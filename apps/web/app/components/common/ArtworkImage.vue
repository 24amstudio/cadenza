<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import { useHostStore } from '~/stores/host';

// Artwork is requested from the Host, which owns provider access. The browser never contacts artwork providers.
const props = withDefaults(
  defineProps<{ url: string | null; alt: string; motionUrl?: string | null }>(),
  { motionUrl: null },
);

const host = useHostStore();
const status = computed(() => host.artworkStatusFor(props.url));
const source = computed(() => host.artworkFor(props.url));

// Motion loops over the still image once its first frame is ready. The still image stays under it, and reduced motion
// keeps only the still image.
const motionReady = ref(false);

const reducedMotion = window.matchMedia(
  '(prefers-reduced-motion: reduce)',
).matches;

watch(
  () => props.url,
  (url) => {
    if (url !== null) host.requestArtwork(url);
  },
  { immediate: true },
);

watch(
  () => props.motionUrl,
  () => {
    motionReady.value = false;
  },
);
</script>

<template>
  <div class="artwork">
    <Transition name="fade" mode="out-in">
      <div v-if="status === 'ready'" key="image" class="artwork-stack">
        <!-- A new image, such as the full image after its preview, crossfades over the old one. -->
        <Transition name="fade">
          <img
            :key="source ?? undefined"
            class="artwork-image"
            :src="source ?? undefined"
            :alt="alt"
          />
        </Transition>
      </div>
      <div
        v-else-if="status === 'loading'"
        key="loading"
        class="artwork-loading skeleton"
        role="img"
        :aria-label="`Loading artwork for ${alt}`"
      />
      <div
        v-else
        key="placeholder"
        class="artwork-placeholder"
        role="img"
        :aria-label="alt"
      >
        <AppIcon name="now" />
      </div>
    </Transition>
    <video
      v-if="motionUrl !== null && !reducedMotion"
      :key="motionUrl"
      class="artwork-motion"
      :class="{ ready: motionReady }"
      :src="motionUrl"
      autoplay
      loop
      muted
      playsinline
      disablepictureinpicture
      aria-hidden="true"
      @canplay="motionReady = true"
    />
  </div>
</template>

<style scoped>
.artwork {
  position: relative;
  width: 100%;
  aspect-ratio: 1;
  overflow: hidden;
  border-radius: var(--radius-artwork);
  background: var(--color-fill);
}

.artwork-loading,
.artwork-placeholder {
  width: 100%;
  height: 100%;
}

.artwork-stack {
  position: absolute;
  inset: 0;
}

.artwork-image {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.artwork-placeholder {
  display: grid;
  place-items: center;
  color: var(--color-text-tertiary);
  font-size: 34%;
}

.artwork-motion {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  opacity: 0;
  pointer-events: none;
  transition: opacity 500ms var(--ease-standard);
}

.artwork-motion.ready {
  opacity: 1;
}
</style>
