import { defineStore } from 'pinia';
import { ref } from 'vue';
import type { AppView } from '~/lib/navigation';

export const useUiStore = defineStore('ui', () => {
  const view = ref<AppView>('now-playing');

  // Set by a control that wants the lyrics on screen. The Now Playing page scrolls to them and clears the request.
  const lyricsRequested = ref(false);

  // Full-screen Now Playing: the song data on the left and the lyrics filling the right.
  const immersive = ref(false);

  function showView(next: AppView): void {
    view.value = next;
  }

  function revealLyrics(): void {
    view.value = 'now-playing';
    lyricsRequested.value = true;
  }

  function takeLyricsRequest(): void {
    lyricsRequested.value = false;
  }

  function setImmersive(next: boolean): void {
    immersive.value = next;
  }

  return {
    view,
    showView,
    lyricsRequested,
    revealLyrics,
    takeLyricsRequest,
    immersive,
    setImmersive,
  };
});
