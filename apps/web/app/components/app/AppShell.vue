<script setup lang="ts">
import { computed, onMounted, watch } from 'vue';
import AppSidebar from '~/components/app/AppSidebar.vue';
import ConnectionBanner from '~/components/app/ConnectionBanner.vue';
import MobileTabBar from '~/components/app/MobileTabBar.vue';
import ToastRegion from '~/components/app/ToastRegion.vue';
import PlayerBar from '~/components/player/PlayerBar.vue';
import PairingView from '~/components/pairing/PairingView.vue';
import LyricsView from '~/components/views/LyricsView.vue';
import NowPlayingView from '~/components/views/NowPlayingView.vue';
import SettingsView from '~/components/views/SettingsView.vue';
import UpNextView from '~/components/views/UpNextView.vue';
import { useHostStore } from '~/stores/host';
import { usePreferencesStore } from '~/stores/preferences';
import { useUiStore } from '~/stores/ui';

const host = useHostStore();
const ui = useUiStore();

// Creating the store applies the saved theme at startup, not only when Settings opens.
usePreferencesStore();

// Until a Host is paired, the page is only the pairing surface. Once paired, the player stays visible even while
// reconnecting so the last known state remains readable.
const needsPairing = computed(() =>
  ['unpaired', 'pairing', 'pairing-failed'].includes(host.phase),
);

watch(
  () => host.lyricsStatus,
  (status) => {
    if (status === 0 && ui.view === 'lyrics') ui.showView('now-playing');
  },
);

onMounted(() => {
  host.start();
});
</script>

<template>
  <div class="app-shell" :class="{ 'is-pairing': needsPairing }">
    <AppSidebar v-if="!needsPairing" class="sidebar" />

    <main class="content">
      <PairingView v-if="needsPairing" />
      <template v-else>
        <ConnectionBanner />
        <NowPlayingView v-if="ui.view === 'now-playing'" />
        <LyricsView v-else-if="ui.view === 'lyrics'" />
        <UpNextView v-else-if="ui.view === 'up-next'" />
        <SettingsView v-else />
      </template>
    </main>

    <div v-if="!needsPairing" class="player-slot">
      <PlayerBar />
    </div>
    <MobileTabBar v-if="!needsPairing" class="tabs" />
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
</style>
