<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import ArtworkImage from '~/components/common/ArtworkImage.vue';
import EmptyState from '~/components/common/EmptyState.vue';
import LyricsPanel from '~/components/lyrics/LyricsPanel.vue';
import ProgressScrubber from '~/components/player/ProgressScrubber.vue';
import TransportControls from '~/components/player/TransportControls.vue';
import QueueRow from '~/components/queue/QueueRow.vue';
import { useHostStore } from '~/stores/host';
import { useUiStore } from '~/stores/ui';

defineProps<{ immersive: boolean }>();

const host = useHostStore();
const ui = useUiStore();

const song = computed(() => host.current?.song ?? null);
const upNext = computed(() => host.queue.slice(0, 4));

const hasLyrics = computed(
  () => host.current !== null && host.lyricsStatus > 0,
);

// The panel stays while lyrics load, so a song change does not remove it. It is absent when the song has no lyrics.
const showLyrics = computed(
  () => host.current !== null && (host.lyricsLoading || host.lyricsStatus > 0),
);

const lyricsPanel = ref<InstanceType<typeof LyricsPanel> | null>(null);

// The lyrics button and the player bar ask for the lyrics. The page scrolls to the panel once it has rendered.
watch(
  () => ui.lyricsRequested,
  (requested) => {
    if (!requested) return;

    ui.takeLyricsRequest();
    void nextTick(() => lyricsPanel.value?.reveal());
  },
  { immediate: true },
);

// Leaving full screen for the queue has to leave the chrome visible too, or the navigation would be hidden.
function openQueue(): void {
  ui.setImmersive(false);
  ui.showView('up-next');
}

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

  <div
    v-else
    class="now-playing"
    :class="{ immersive, 'without-lyrics': immersive && !showLyrics }"
    :style="ambientStyle"
  >
    <button
      v-if="immersive"
      class="exit-button"
      type="button"
      aria-label="Exit full screen"
      @click="ui.setImmersive(false)"
    >
      <AppIcon name="collapse" />
    </button>

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
          class="scrubber"
          labels
          :position-ms="host.positionMs"
          :duration-ms="song.durationMs"
          :disabled="!host.canControl"
          @seek="host.seekTo"
        />

        <div class="transport-row">
          <button
            v-if="hasLyrics && !immersive"
            class="lyrics-button"
            type="button"
            aria-label="Show lyrics"
            @click="ui.revealLyrics()"
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

    <LyricsPanel
      v-if="showLyrics"
      ref="lyricsPanel"
      :immersive="immersive"
      @expand="ui.setImmersive(true)"
    />

    <div v-if="immersive" class="immersive-tools">
      <span class="tool active" role="img" aria-label="Lyrics are showing">
        <AppIcon name="lyrics" />
      </span>
      <button
        class="tool"
        type="button"
        aria-label="Up Next"
        @click="openQueue"
      >
        <AppIcon name="queue" />
      </button>
    </div>

    <section
      v-if="!immersive"
      class="up-next"
      aria-labelledby="up-next-heading"
    >
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
}

/* The colour spans the full width of the page. The page clips it at its edges, so it can be wider than the content. */
.now-playing::before {
  content: '';
  position: absolute;
  top: -60px;
  left: 50%;
  width: 100vw;
  transform: translateX(-50%);
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

.lyrics-button,
.exit-button {
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

.lyrics-button:hover,
.exit-button:hover {
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

/* Full screen is always dark, like the Apple Music player, whatever the theme. */
.now-playing.immersive {
  --color-text: #fff;
  --color-text-secondary: rgb(255 255 255 / 0.72);
  --color-text-tertiary: rgb(255 255 255 / 0.46);
  --color-fill: rgb(255 255 255 / 0.14);
  --color-fill-strong: rgb(255 255 255 / 0.24);
  color-scheme: dark;
  color: var(--color-text);
  box-sizing: border-box;
  grid-template-columns: 96px minmax(0, 1fr) auto;
  grid-template-rows: auto minmax(0, 1fr) auto auto auto;
  grid-template-areas:
    'cover titles exit'
    'lyrics lyrics lyrics'
    'scrubber scrubber scrubber'
    'transport transport transport'
    'tools tools tools';
  align-items: center;
  gap: clamp(12px, 2.4vh, 26px);
  height: 100%;
  max-width: none;
  margin: 0;
}

/* The artwork colours the whole screen, with a dark scrim so the white text stays readable. */
.now-playing.immersive::before {
  inset: -40px;
  width: auto;
  transform: none;
  height: auto;
  opacity: 0.95;
  filter: blur(56px) saturate(1.35);
  mask-image: none;
  -webkit-mask-image: none;
  background:
    linear-gradient(rgb(0 0 0 / 0.18), rgb(0 0 0 / 0.5)),
    var(--ambient-image) center / cover no-repeat;
}

/* The hero and details become plain grid items, so the header, the lyrics, and the controls each take their own row. */
.now-playing.immersive > .hero,
.now-playing.immersive .details {
  display: contents;
}

.now-playing.immersive .cover {
  grid-area: cover;
  width: 96px;
  justify-self: start;
}

.now-playing.immersive .titles {
  grid-area: titles;
  gap: 4px;
  min-width: 0;
  justify-items: start;
}

.now-playing.immersive h1 {
  font-size: 26px;
  line-height: 1.2;
}

.now-playing.immersive .artist {
  color: var(--color-text-secondary);
  font-size: 18px;
}

.now-playing.immersive .album,
.now-playing.immersive .requester {
  display: none;
}

.now-playing.immersive .exit-button {
  grid-area: exit;
}

/* Space between the song header and the first lyric line on wide screens. The phone layout sets its own spacing below. */
.now-playing.immersive > .lyrics-panel {
  grid-area: lyrics;
  height: 100%;
  min-height: 0;
  padding-top: 24px;
  box-sizing: border-box;
}

.now-playing.immersive .scrubber {
  grid-area: scrubber;
}

.now-playing.immersive .transport-row {
  grid-area: transport;
  justify-content: center;
}

.now-playing.immersive .immersive-tools {
  grid-area: tools;
  display: flex;
  justify-content: center;
  gap: 72px;
}

.tool {
  display: grid;
  place-items: center;
  width: 44px;
  height: 44px;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 24px;
}

.tool.active {
  background: var(--color-fill);
  color: var(--color-text);
}

/* Full screen transport: plain white glyphs with no filled circle, sized for a wide screen. */
.now-playing.immersive :deep(.transport) {
  gap: 72px;
}

.now-playing.immersive :deep(.transport-button) {
  width: 96px;
  height: 96px;
  font-size: 64px;
}

.now-playing.immersive :deep(.play-button) {
  width: 120px;
  height: 120px;
  background: transparent;
  box-shadow: none;
  color: var(--color-text);
  font-size: 84px;
}

/* Without lyrics the artwork takes the middle of the screen, with the controls under it. */
.now-playing.immersive.without-lyrics {
  grid-template-columns: minmax(0, 1fr);
  grid-template-rows: auto minmax(0, 1fr) auto auto auto auto;
  grid-template-areas:
    'exit'
    'cover'
    'titles'
    'scrubber'
    'transport'
    'tools';
}

.now-playing.immersive.without-lyrics .exit-button {
  justify-self: end;
}

.now-playing.immersive.without-lyrics .cover {
  width: min(38vh, 420px);
  justify-self: center;
  align-self: center;
}

.now-playing.immersive.without-lyrics .titles {
  justify-items: center;
  text-align: center;
}

.now-playing.immersive.without-lyrics .scrubber {
  width: min(100%, 640px);
  justify-self: center;
}

/* Phone full screen follows Apple Music: a compact header, the lyrics filling the middle, then the progress and transport. */
@media (max-width: 899px) {
  .now-playing.immersive {
    grid-template-columns: 48px minmax(0, 1fr) auto;
    grid-template-rows: auto minmax(0, 1fr) auto auto;
    grid-template-areas:
      'cover titles exit'
      'lyrics lyrics lyrics'
      'scrubber scrubber scrubber'
      'transport transport transport';
    align-items: center;
    gap: 14px;
    padding-top: 0;
  }

  .now-playing.immersive .cover {
    width: 48px;
  }

  .now-playing.immersive .titles {
    gap: 2px;
  }

  .now-playing.immersive h1 {
    font-size: 20px;
  }

  .now-playing.immersive .artist {
    font-size: 15px;
  }

  .now-playing.immersive .immersive-tools {
    display: none;
  }

  /* Equal space above and below the lyrics keeps them centred between the header and the progress bar. The space is
     kept small so more lines fit, and the top and bottom of the lyric box fade. */
  .now-playing.immersive > .lyrics-panel {
    padding: 14px 0;
    box-sizing: border-box;
  }

  .now-playing.immersive :deep(.transport) {
    gap: 26px;
  }

  .now-playing.immersive :deep(.transport-button) {
    width: 56px;
    height: 56px;
    font-size: 30px;
  }

  .now-playing.immersive :deep(.play-button) {
    width: 76px;
    height: 76px;
    font-size: 32px;
  }

  .now-playing.immersive.without-lyrics {
    grid-template-rows: auto minmax(0, 1fr) auto auto auto;
    grid-template-areas:
      'exit'
      'cover'
      'titles'
      'scrubber'
      'transport';
  }

  .now-playing.immersive.without-lyrics .cover {
    width: min(78vw, 340px);
  }

  .now-playing.immersive.without-lyrics h1 {
    font-size: clamp(24px, 6vw, 30px);
  }

  .now-playing.immersive.without-lyrics .artist {
    font-size: 18px;
  }

  .now-playing.immersive.without-lyrics .scrubber {
    width: auto;
  }
}
</style>
