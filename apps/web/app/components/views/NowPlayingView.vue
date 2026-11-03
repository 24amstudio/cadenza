<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import ArtworkImage from '~/components/common/ArtworkImage.vue';
import EmptyState from '~/components/common/EmptyState.vue';
import ProgressScrubber from '~/components/player/ProgressScrubber.vue';
import TransportControls from '~/components/player/TransportControls.vue';
import QueueRow from '~/components/queue/QueueRow.vue';
import { useHostStore } from '~/stores/host';
import { useUiStore } from '~/stores/ui';

const host = useHostStore();
const ui = useUiStore();

const song = computed(() => host.current?.song ?? null);
const upNext = computed(() => host.queue.slice(0, 4));

const hasLyrics = computed(
  () => host.current !== null && host.lyricsStatus > 0,
);

const controlsDisabled = computed(
  () => !host.canControl || host.busyAction !== null,
);

// Sampled artwork tints the background. It is a decorative layer, so it stays out of the accessibility tree.
const ambientStyle = computed(() => {
  const image = host.artworkFor(song.value?.artworkUrl ?? null);

  return image === null ? {} : { '--ambient-image': `url("${image}")` };
});
</script>

<template>
  <EmptyState
    v-if="song === null"
    icon="now"
    title="Nothing is playing"
    body="Start music in Music on Cadenza Host. The song, its lyrics, and what is next appear here."
  />

  <div v-else class="now-playing" :style="ambientStyle">
    <div class="hero">
      <ArtworkImage
        class="cover"
        :url="song.artworkUrl"
        :alt="`${song.title} by ${song.artist}`"
      />

      <div class="details">
        <div class="titles">
          <h1>{{ song.title }}</h1>
          <p class="artist">{{ song.artist }}</p>
          <p class="album">{{ song.album }}</p>
        </div>

        <ProgressScrubber
          labels
          :position-ms="host.positionMs"
          :duration-ms="song.durationMs"
          :disabled="!host.canControl"
          @seek="host.seekTo"
        />

        <div class="transport-row">
          <button
            v-if="hasLyrics"
            class="lyrics-button"
            type="button"
            aria-label="Show lyrics"
            @click="ui.showView('lyrics')"
          >
            <AppIcon name="lyrics" />
          </button>
          <TransportControls
            :is-playing="host.isPlaying"
            :disabled="controlsDisabled"
            @previous="host.skipPrevious"
            @toggle="host.togglePlayback"
            @next="host.skipNext"
          />
        </div>

        <p class="requester">Requested by {{ host.current?.requesterName }}</p>
      </div>
    </div>

    <section class="up-next" aria-labelledby="up-next-heading">
      <header class="section-header">
        <h2 id="up-next-heading">Up Next</h2>
        <button
          v-if="host.queue.length > upNext.length"
          class="text-button"
          type="button"
          @click="ui.showView('up-next')"
        >
          Show all
        </button>
      </header>
      <ol v-if="upNext.length > 0" class="queue-list">
        <QueueRow v-for="entry in upNext" :key="entry.id" :entry="entry" />
      </ol>
      <p v-else class="quiet">Nothing else is queued.</p>
    </section>
  </div>
</template>

<style scoped>
.now-playing {
  position: relative;
  isolation: isolate;
  display: grid;
  gap: 40px;
  max-width: 1120px;
  margin: 0 auto;
}

.now-playing::before {
  content: '';
  position: absolute;
  inset: -60px -80px auto;
  z-index: -1;
  height: 560px;
  background: var(--ambient-image) center / cover no-repeat;
  filter: blur(80px) saturate(1.5);
  opacity: 0.32;
  mask-image: linear-gradient(black 30%, transparent);
  -webkit-mask-image: linear-gradient(black 30%, transparent);
  pointer-events: none;
}

.hero {
  display: grid;
  grid-template-columns: minmax(240px, 360px) minmax(0, 1fr);
  align-items: end;
  gap: clamp(28px, 5vw, 64px);
}

.cover {
  box-shadow: 0 40px 70px -34px var(--color-shadow);
}

.details {
  display: grid;
  gap: 26px;
  min-width: 0;
}

.titles {
  display: grid;
  gap: 6px;
}

h1 {
  font-family: var(--font-display);
  font-size: clamp(30px, 4.4vw, 46px);
  font-weight: 750;
  letter-spacing: -0.025em;
  line-height: 1.08;
  overflow-wrap: anywhere;
}

.artist {
  color: var(--color-accent);
  font-size: 20px;
  font-weight: 600;
}

.album {
  color: var(--color-text-secondary);
  font-size: 16px;
}

.transport-row {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 18px;
}

.lyrics-button {
  display: grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill);
  color: var(--color-text);
  font-size: 19px;
}

.lyrics-button:hover {
  background: var(--color-fill-strong);
}

.requester {
  color: var(--color-text-tertiary);
  font-size: 13px;
}

.up-next {
  display: grid;
  gap: 8px;
}

.section-header {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 12px;
  padding: 0 12px;
}

h2 {
  font-family: var(--font-display);
  font-size: 22px;
  font-weight: 700;
  letter-spacing: -0.015em;
}

.text-button {
  border: 0;
  background: transparent;
  color: var(--color-accent);
  font-size: 14px;
  font-weight: 600;
}

.queue-list {
  display: grid;
  gap: 2px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.quiet {
  padding: 0 12px;
  color: var(--color-text-secondary);
}

@media (max-width: 899px) {
  .hero {
    grid-template-columns: minmax(0, 1fr);
    align-items: center;
  }

  .cover {
    width: min(78vw, 340px);
    justify-self: center;
  }

  .details {
    text-align: center;
  }

  .titles {
    justify-items: center;
  }

  .transport-row {
    justify-content: center;
  }
}
</style>
