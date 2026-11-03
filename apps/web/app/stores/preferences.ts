import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

export type ThemePreference = 'system' | 'light' | 'dark';

const storageKey = 'cadenza.web.theme';

function isThemePreference(value: string | null): value is ThemePreference {
  return value === 'system' || value === 'light' || value === 'dark';
}

function readTheme(): ThemePreference {
  try {
    const value = localStorage.getItem(storageKey);

    return isThemePreference(value) ? value : 'system';
  } catch {
    return 'system';
  }
}

function writeTheme(value: ThemePreference): void {
  try {
    localStorage.setItem(storageKey, value);
  } catch {
    // The choice still applies for this page session.
  }
}

export const usePreferencesStore = defineStore('preferences', () => {
  const theme = ref<ThemePreference>(readTheme());

  watch(
    theme,
    (value) => {
      writeTheme(value);

      // "system" removes the override so the CSS media query decides.
      if (value === 'system') delete document.documentElement.dataset.theme;
      else document.documentElement.dataset.theme = value;
    },
    { immediate: true },
  );

  function setTheme(value: ThemePreference): void {
    theme.value = value;
  }

  return { theme, setTheme };
});
