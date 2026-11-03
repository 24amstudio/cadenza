import { defineStore } from 'pinia';
import { ref } from 'vue';
import type { AppView } from '~/lib/navigation';

export const useUiStore = defineStore('ui', () => {
  const view = ref<AppView>('now-playing');

  function showView(next: AppView): void {
    view.value = next;
  }

  return { view, showView };
});
