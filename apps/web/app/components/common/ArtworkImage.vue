<script setup lang="ts">
import { computed, watch } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import { useHostStore } from '~/stores/host';

// Artwork is requested from the Host, which owns provider access. The browser never contacts artwork providers.
const props = defineProps<{ url: string | null; alt: string }>();

const host = useHostStore();
const source = computed(() => host.artworkFor(props.url));

watch(
  () => props.url,
  (url) => {
    if (url !== null) host.requestArtwork(url);
  },
  { immediate: true },
);
</script>

<template>
  <div class="artwork">
    <img v-if="source" class="artwork-image" :src="source" :alt="alt" />
    <div v-else class="artwork-placeholder" role="img" :aria-label="alt">
      <AppIcon name="now" />
    </div>
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

.artwork-image,
.artwork-placeholder {
  width: 100%;
  height: 100%;
}

.artwork-image {
  object-fit: cover;
}

.artwork-placeholder {
  display: grid;
  place-items: center;
  color: var(--color-text-tertiary);
  font-size: 34%;
}
</style>
