<script setup lang="ts">
import { computed, onMounted, useTemplateRef } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import ArtworkImage from '~/components/common/ArtworkImage.vue';
import BrowseSection from '~/components/browse/BrowseSection.vue';
import BrowseStatus from '~/components/browse/BrowseStatus.vue';
import type { BrowseTarget } from '~/lib/browse';
import { useBrowseRequest } from '~/stores/browse';
import { useUiStore } from '~/stores/ui';

// The page of one album, artist or playlist, opened over the current view. Back returns to what opened it.
const props = defineProps<{ target: BrowseTarget }>();

const ui = useUiStore();
const root = useTemplateRef<HTMLElement>('root');
const { entry, retry } = useBrowseRequest(() => props.target.request);

const page = computed(() => entry.value?.page ?? null);
const title = computed(() => page.value?.title ?? props.target.title ?? '');
const kind = computed(() => page.value?.kind ?? props.target.request.kind);

const kindLabel = computed(() =>
  kind.value === 'artist'
    ? 'Artist'
    : kind.value === 'album'
      ? 'Album'
      : 'Playlist',
);

// The page opens at its top, not where the page behind it was scrolled to.
onMounted(() => {
  root.value?.closest('main')?.scrollTo({ top: 0 });
});
</script>

<template>
  <article ref="root" class="browse" :aria-label="`${kindLabel} ${title}`">
    <button class="back" type="button" @click="ui.closeBrowse()">
      <AppIcon name="back" />
      Back
    </button>

    <header class="hero">
      <ArtworkImage
        class="cover"
        :class="{ round: kind === 'artist' }"
        :url="page?.artworkUrl || null"
        :alt="`${title} artwork`"
      />
      <div class="titles">
        <h1>{{ title }}</h1>
        <p v-if="page?.subtitle" class="subtitle">{{ page.subtitle }}</p>
        <p v-if="page?.detail" class="detail">{{ page.detail }}</p>
      </div>
    </header>

    <BrowseStatus
      :entry="entry"
      empty-title="Nothing here yet"
      empty-body="Cadenza Host found no songs for this page in Music."
      @retry="retry"
    />

    <BrowseSection
      v-for="section in page?.sections ?? []"
      :key="section.id"
      :section="section"
    />
  </article>
</template>

<style scoped>
.browse {
  display: grid;
  gap: 28px;
  max-width: 960px;
  margin: 0 auto;
}

.back {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  justify-self: start;
  min-height: 40px;
  padding: 0 14px 0 8px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill);
  color: var(--color-text);
  font-size: 14px;
  font-weight: 600;
}

.back:hover {
  background: var(--color-fill-strong);
}

.hero {
  display: grid;
  grid-template-columns: minmax(140px, 220px) minmax(0, 1fr);
  align-items: end;
  gap: clamp(18px, 4vw, 40px);
  padding: 0 12px;
}

.cover {
  box-shadow: 0 30px 50px -30px var(--color-shadow);
}

.cover.round {
  border-radius: 999px;
}

.titles {
  display: grid;
  gap: 6px;
  min-width: 0;
}

h1 {
  font-family: var(--font-display);
  font-size: clamp(28px, 4.4vw, 44px);
  font-weight: 750;
  letter-spacing: -0.025em;
  line-height: 1.08;
  overflow-wrap: anywhere;
}

.subtitle {
  color: var(--color-accent);
  font-size: 18px;
  font-weight: 600;
}

.detail {
  color: var(--color-text-secondary);
  font-size: 15px;
}

@media (max-width: 719px) {
  .hero {
    grid-template-columns: minmax(96px, 128px) minmax(0, 1fr);
    gap: 16px;
  }

  .subtitle {
    font-size: 16px;
  }
}
</style>
