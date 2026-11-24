<script setup lang="ts">
import { onMounted, ref } from 'vue';
import AppShell from '~/components/app/AppShell.vue';
import MediaSessionBridge from '~/components/app/MediaSessionBridge.vue';
import SharedLinkDialog from '~/components/app/SharedLinkDialog.vue';
import { sharedSongId } from '~/lib/shareLink';

// An Apple Music link shared into the installed Remote arrives as the share target's query. It is read once, then the
// query is removed so a reload does not offer it again.
const sharedSong = ref<string | null>(null);

onMounted(() => {
  const params = new URLSearchParams(window.location.search);

  const shared = [params.get('url'), params.get('text'), params.get('title')]
    .filter((value): value is string => value !== null && value.length > 0)
    .join(' ');

  if (shared.length > 0) sharedSong.value = sharedSongId(shared);

  if (params.size > 0) {
    window.history.replaceState(null, '', window.location.pathname);
  }
});
</script>

<template>
  <AppShell />
  <MediaSessionBridge />
  <SharedLinkDialog
    v-if="sharedSong !== null"
    :song-id="sharedSong"
    @close="sharedSong = null"
  />
</template>
