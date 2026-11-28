import { defineStore } from 'pinia';
import { computed, ref } from 'vue';
import type { BrowseTarget } from '~/lib/browse';
import type { AppView } from '~/lib/navigation';

// Pages opened from one another stay reachable with Back. The oldest are dropped past this depth.
const browseDepth = 20;

export const useUiStore = defineStore('ui', () => {
  const view = ref<AppView>('now-playing');

  // Album, artist and playlist pages open over the current view. Choosing a view in the navigation closes them all.
  const browseStack = ref<BrowseTarget[]>([]);
  const browseTarget = computed(() => browseStack.value.at(-1) ?? null);

  // Set by a control that wants the lyrics on screen. The Now Playing page scrolls to them and clears the request.
  const lyricsRequested = ref(false);

  // Full-screen Now Playing: the song data on the left and the lyrics filling the right.
  const immersive = ref(false);

  const ambientOpen = ref(false);

  function showView(next: AppView): void {
    view.value = next;
    browseStack.value = [];
  }

  function openBrowse(target: BrowseTarget): void {
    // The full-screen player has no navigation, so a page opened from it leaves full screen first.
    immersive.value = false;
    browseStack.value = [...browseStack.value, target].slice(-browseDepth);
  }

  function closeBrowse(): void {
    browseStack.value = browseStack.value.slice(0, -1);
  }

  function revealLyrics(): void {
    showView('now-playing');
    lyricsRequested.value = true;
  }

  function takeLyricsRequest(): void {
    lyricsRequested.value = false;
  }

  function setImmersive(next: boolean): void {
    immersive.value = next;
  }

  function openAmbient(): void {
    ambientOpen.value = true;
  }

  function closeAmbient(): void {
    ambientOpen.value = false;
  }

  return {
    view,
    showView,
    browseTarget,
    openBrowse,
    closeBrowse,
    lyricsRequested,
    revealLyrics,
    takeLyricsRequest,
    immersive,
    setImmersive,
    ambientOpen,
    openAmbient,
    closeAmbient,
  };
});
