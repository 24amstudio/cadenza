<script setup lang="ts">
import { computed, onMounted, onUnmounted, watch } from 'vue';
import AppSidebar from '~/components/app/AppSidebar.vue';
import ConnectionBanner from '~/components/app/ConnectionBanner.vue';
import MobileTabBar from '~/components/app/MobileTabBar.vue';
import ToastRegion from '~/components/app/ToastRegion.vue';
import PlayerBar from '~/components/player/PlayerBar.vue';
import PairingView from '~/components/pairing/PairingView.vue';
import NowPlayingView from '~/components/views/NowPlayingView.vue';
import SettingsView from '~/components/views/SettingsView.vue';
import UpNextView from '~/components/views/UpNextView.vue';
import { showNotification } from '~/lib/browserNotifications';
import { createSongChangeDetector, documentTitle } from '~/lib/songAlerts';
import { useHostStore } from '~/stores/host';
import { usePreferencesStore } from '~/stores/preferences';
import { useUiStore } from '~/stores/ui';

const host = useHostStore();
const ui = useUiStore();

// Creating the store applies the saved theme at startup, not only when Settings opens.
const preferences = usePreferencesStore();

// The tab title names the song that is playing, so a background tab still shows it.
watch(
  () => host.current?.song ?? null,
  (song) => {
    document.title = documentTitle(song);
  },
  { immediate: true },
);

// A new play after a known one is announced. The first play seen only sets the baseline, so opening the page or
// reconnecting does not alert about a song that was already playing.
const songChanged = createSongChangeDetector();

watch(
  () => host.current?.occurrenceId ?? null,
  (occurrenceId) => {
    if (!songChanged.observe(occurrenceId) || !preferences.songNotifications) {
      return;
    }

    const song = host.current?.song;

    if (song !== undefined) showNotification(song.title, song.artist);
  },
);

// Pairing starts a new session, so the first song from another Host is a baseline rather than a change.
watch(
  () => host.phase,
  (phase) => {
    if (phase === 'pairing') songChanged.reset();
  },
);

// Until a Host is paired, the page is only the pairing surface. Once paired, the player stays visible even while
// reconnecting so the last known state remains readable. A Bluetooth session that ended needs a click to reopen, so
// it also returns to that surface.
const needsPairing = computed(() =>
  ['unpaired', 'pairing', 'pairing-failed', 'bluetooth-idle'].includes(
    host.phase,
  ),
);

// The full-screen player needs a song to show. Pairing has no full-screen mode.
const immersive = computed(
  () => ui.immersive && host.current !== null && !needsPairing.value,
);

// Sidebar, player, and tab bar are left out while the full-screen player is open.
const showChrome = computed(() => !needsPairing.value && !immersive.value);

// Escape leaves the full-screen player, as the exit control does.
function onKeydown(event: KeyboardEvent): void {
  if (event.key === 'Escape' && ui.immersive) ui.setImmersive(false);
}

onMounted(() => {
  window.addEventListener('keydown', onKeydown);
  host.start();
});

onUnmounted(() => {
  window.removeEventListener('keydown', onKeydown);
});
</script>

<template>
  <div
    class="app-shell"
    :class="{ 'is-pairing': needsPairing, 'is-immersive': immersive }"
  >
    <AppSidebar v-if="showChrome" class="sidebar" />

    <main class="content">
      <PairingView v-if="needsPairing" />
      <template v-else>
        <ConnectionBanner />
        <NowPlayingView
          v-if="ui.view === 'now-playing'"
          :immersive="immersive"
        />
        <UpNextView v-else-if="ui.view === 'up-next'" />
        <SettingsView v-else />
      </template>
    </main>

    <div v-if="showChrome" class="player-slot">
      <PlayerBar />
    </div>
    <MobileTabBar v-if="showChrome" class="tabs" />
    <ToastRegion />
  </div>
</template>

<style scoped>
.app-shell {
  display: grid;
  height: 100dvh;
  grid-template-columns: 232px minmax(0, 1fr);
  grid-template-rows: minmax(0, 1fr) auto;
  grid-template-areas:
    'sidebar content'
    'sidebar player';
  background: var(--color-canvas);
}

.app-shell.is-pairing {
  grid-template-columns: minmax(0, 1fr);
  grid-template-areas: 'content';
}

.sidebar {
  grid-area: sidebar;
}

.content {
  grid-area: content;
  min-height: 0;
  overflow-y: auto;
  padding: 28px clamp(18px, 4vw, 48px) 48px;
  scroll-padding-top: 24px;
}

.is-pairing .content {
  padding: 0;
}

.player-slot {
  grid-area: player;
}

.tabs {
  display: none;
}

@media (max-width: 719px) {
  .app-shell,
  .app-shell.is-pairing {
    grid-template-columns: minmax(0, 1fr);
    grid-template-rows: minmax(0, 1fr) auto auto;
    grid-template-areas:
      'content'
      'player'
      'tabs';
  }

  .sidebar {
    display: none;
  }

  .content {
    padding: 18px 16px 32px;
  }

  .tabs {
    display: grid;
    grid-area: tabs;
  }
}

/* Full screen takes the whole window. The chrome is not rendered, so the content area gets all of it. */
.app-shell.is-immersive {
  background: #0a0708;
  grid-template-columns: minmax(0, 1fr);
  grid-template-rows: minmax(0, 1fr);
  grid-template-areas: 'content';
}

.is-immersive .content {
  overflow: hidden;
  padding: 20px clamp(18px, 3vw, 40px);
}
</style>
