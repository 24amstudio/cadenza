import { defineStore } from 'pinia';
import { ref } from 'vue';

// Routine results appear as a short toast. Failures that need a decision use the page's own surfaces instead.
const displayMs = 3_200;

export const useNoticesStore = defineStore('notices', () => {
  const message = ref<string | null>(null);
  let timer: ReturnType<typeof setTimeout> | null = null;

  function show(text: string): void {
    message.value = text;

    if (timer !== null) clearTimeout(timer);
    timer = setTimeout(() => {
      message.value = null;
      timer = null;
    }, displayMs);
  }

  function dismiss(): void {
    if (timer !== null) clearTimeout(timer);
    timer = null;
    message.value = null;
  }

  return { message, show, dismiss };
});
