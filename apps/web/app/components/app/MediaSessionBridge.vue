<script setup lang="ts">
import { onMounted, onUnmounted, watch } from 'vue';
import { nowPlayingMetadata } from '~/lib/mediaSession';
import { useHostStore } from '~/stores/host';

// Connects the browser's media session to Host playback, so the operating system's media keys and now-playing surface
// control the Mac. It renders nothing, and browsers without a media session are left alone.
const host = useHostStore();

function session(): MediaSession | null {
  return typeof navigator === 'undefined'
    ? null
    : (navigator.mediaSession ?? null);
}

function registerActions(): void {
  const media = session();

  if (media === null) return;

  media.setActionHandler('play', () => {
    if (!host.isPlaying) host.togglePlayback();
  });
  media.setActionHandler('pause', () => {
    if (host.isPlaying) host.togglePlayback();
  });
  media.setActionHandler('nexttrack', () => host.skipNext());
  media.setActionHandler('previoustrack', () => host.skipPrevious());
  media.setActionHandler('seekto', (details) => {
    if (details.seekTime !== undefined) host.seekTo(details.seekTime * 1000);
  });
}

function clearActions(): void {
  const media = session();

  if (media === null) return;

  for (const action of [
    'play',
    'pause',
    'nexttrack',
    'previoustrack',
    'seekto',
  ] as const) {
    media.setActionHandler(action, null);
  }
}

watch(
  () => host.current?.song ?? null,
  (song) => {
    const media = session();
    const metadata = nowPlayingMetadata(song);

    if (
      media === null ||
      metadata === null ||
      typeof MediaMetadata === 'undefined'
    ) {
      if (media !== null) media.metadata = null;

      return;
    }

    media.metadata = new MediaMetadata(metadata);
  },
  { immediate: true },
);

watch(
  () => host.isPlaying,
  (playing) => {
    const media = session();

    if (media !== null) media.playbackState = playing ? 'playing' : 'paused';
  },
  { immediate: true },
);

onMounted(registerActions);

onUnmounted(clearActions);
</script>

<template>
  <span hidden />
</template>
