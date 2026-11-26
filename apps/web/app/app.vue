<script setup lang="ts">
import { onMounted, ref } from 'vue';
import AppShell from '~/components/app/AppShell.vue';
import MediaSessionBridge from '~/components/app/MediaSessionBridge.vue';
import SharedLinkDialog from '~/components/app/SharedLinkDialog.vue';
import TvStageView from '~/components/stage/TvStageView.vue';
import { sharedSongId } from '~/lib/shareLink';
import { useHostStore } from '~/stores/host';

// `/tv` is the 10-foot stage for a TV browser. Every other path is the Remote.
const isStage =
  typeof window !== 'undefined' && /^\/tv\/?$/.test(window.location.pathname);

// An Apple Music link shared into the installed Remote arrives as the share target's query. It is read once, then the
// query is removed so a reload does not offer it again.
const sharedSong = ref<string | null>(null);

onMounted(() => {
  const params = new URLSearchParams(window.location.search);

  const shared = [params.get('url'), params.get('text'), params.get('title')]
    .filter((value): value is string => value !== null && value.length > 0)
    .join(' ');

  if (shared.length > 0) sharedSong.value = sharedSongId(shared);

  // The TV's QR code links here with its PIN. A paired Remote approves that TV, and only the PIN is read from the URL.
  const stagePin = params.get('stage');

  if (stagePin !== null && /^[0-9]{4}$/.test(stagePin))
    useHostStore().approveStage(stagePin);

  if (params.size > 0) {
    window.history.replaceState(null, '', window.location.pathname);
  }
});
</script>

<template>
  <TvStageView v-if="isStage" />
  <template v-else>
    <AppShell />
    <MediaSessionBridge />
    <SharedLinkDialog
      v-if="sharedSong !== null"
      :song-id="sharedSong"
      @close="sharedSong = null"
    />
  </template>
</template>
