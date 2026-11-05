<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import ArtworkImage from '~/components/common/ArtworkImage.vue';
import ProgressScrubber from '~/components/player/ProgressScrubber.vue';
import TransportControls from '~/components/player/TransportControls.vue';
import VolumeSlider from '~/components/player/VolumeSlider.vue';
import { useHostStore } from '~/stores/host';
import { useUiStore } from '~/stores/ui';

const host = useHostStore();
const ui = useUiStore();

const song = computed(() => host.current?.song ?? null);
const duration = computed(() => song.value?.durationMs ?? null);

const controlsDisabled = computed(
  () => !host.canControl || host.busyAction !== null,
);

const showLyricsToggle = computed(
  () => host.current !== null && host.lyricsStatus > 0,
);
</script>

<template>
  <footer class="player">
    <div class="player-progress">
      <ProgressScrubber
        :position-ms="host.positionMs"
        :duration-ms="duration"
        :disabled="!host.canControl"
        @seek="host.seekTo"
      />
    </div>

    <div class="now">
      <ArtworkImage
        v-if="song"
        class="thumb"
        :url="song.artworkUrl"
        :alt="`${song.title} artwork`"
      />
      <div v-else class="thumb thumb-empty">
        <AppIcon name="now" />
      </div>
      <div class="meta">
        <strong>{{ song?.title ?? 'Nothing playing' }}</strong>
        <span>
          {{
            song
              ? song.artist
              : host.connected
                ? 'Start music on Cadenza Host'
                : 'Waiting for Cadenza Host'
          }}
        </span>
      </div>
    </div>

    <div class="controls">
      <TransportControls
        compact
        :is-playing="host.isPlaying"
        :disabled="controlsDisabled"
        @previous="host.skipPrevious"
        @toggle="host.togglePlayback"
        @next="host.skipNext"
      />
    </div>

    <div class="utilities">
      <VolumeSlider
        class="volume"
        :percent="host.snapshot?.volume ?? 0"
        :disabled="!host.connected"
        @change="host.setVolume"
      />
      <button
        v-if="showLyricsToggle"
        class="utility-button"
        type="button"
        aria-label="Show lyrics"
        @click="ui.revealLyrics()"
      >
        <AppIcon name="lyrics" />
      </button>
    </div>
  </footer>
</template>

<style scoped>
.player {
  position: relative;
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);
  align-items: center;
  gap: 16px;
  height: 76px;
  padding: 0 20px;
  border-top: 1px solid var(--color-separator);
  background: var(--color-chrome);
  backdrop-filter: var(--chrome-blur);
  -webkit-backdrop-filter: var(--chrome-blur);
}

.player-progress {
  position: absolute;
  top: -8px;
  left: 0;
  right: 0;
  padding: 0 0;
}

.now {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
}

.thumb {
  flex: none;
  width: 48px;
  height: 48px;
  border-radius: 8px;
}

.thumb-empty {
  display: grid;
  place-items: center;
  background: var(--color-fill);
  color: var(--color-text-tertiary);
}

.meta {
  display: grid;
  min-width: 0;
}

.meta strong,
.meta span {
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}

.meta strong {
  font-size: 14px;
  font-weight: 600;
}

.meta span {
  color: var(--color-text-secondary);
  font-size: 13px;
}

.controls {
  display: flex;
  justify-content: center;
}

.utilities {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 14px;
}

.utility-button {
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 18px;
}

.utility-button:hover,
.utility-button.active {
  background: var(--color-fill);
  color: var(--color-accent);
}

@media (max-width: 719px) {
  .player {
    grid-template-columns: minmax(0, 1fr) auto auto;
    gap: 10px;
    height: 64px;
    padding: 0 12px;
  }

  .utilities .volume {
    display: none;
  }
}
</style>
