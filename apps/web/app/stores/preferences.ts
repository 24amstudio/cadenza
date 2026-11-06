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

// Lyric text scale relative to the standard size. The default is 30% larger than the standard size.
export type LyricsSize = 'standard' | 'large' | 'extra-large';

export const lyricsScales: Record<LyricsSize, number> = {
  standard: 1,
  large: 1.3,
  'extra-large': 1.6,
};

const lyricsSizeKey = 'cadenza.web.lyricsSize';

function isLyricsSize(value: string | null): value is LyricsSize {
  return value !== null && Object.hasOwn(lyricsScales, value);
}

function readLyricsSize(): LyricsSize {
  try {
    const value = localStorage.getItem(lyricsSizeKey);

    return isLyricsSize(value) ? value : 'large';
  } catch {
    return 'large';
  }
}

function writeLyricsSize(value: LyricsSize): void {
  try {
    localStorage.setItem(lyricsSizeKey, value);
  } catch {
    // The choice still applies for this page session.
  }
}

const songNotificationsKey = 'cadenza.web.songNotifications';

// Off until the user turns it on in Settings, because the browser asks for permission only after that click.
function readSongNotifications(): boolean {
  try {
    return localStorage.getItem(songNotificationsKey) === 'true';
  } catch {
    return false;
  }
}

function writeSongNotifications(value: boolean): void {
  try {
    localStorage.setItem(songNotificationsKey, String(value));
  } catch {
    // The choice still applies for this page session.
  }
}

const reduceEffectsKey = 'cadenza.web.reduceEffects';

function readReduceEffects(): boolean {
  try {
    return localStorage.getItem(reduceEffectsKey) === 'true';
  } catch {
    return false;
  }
}

function writeReduceEffects(value: boolean): void {
  try {
    localStorage.setItem(reduceEffectsKey, String(value));
  } catch {
    // The choice still applies for this page session.
  }
}

export const usePreferencesStore = defineStore('preferences', () => {
  const theme = ref<ThemePreference>(readTheme());
  const lyricsSize = ref<LyricsSize>(readLyricsSize());
  const songNotifications = ref(readSongNotifications());
  const reduceEffects = ref(readReduceEffects());

  watch(lyricsSize, writeLyricsSize);
  watch(songNotifications, writeSongNotifications);

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

  // The attribute lets one stylesheet rule switch off transitions, animations and blur everywhere.
  watch(
    reduceEffects,
    (value) => {
      writeReduceEffects(value);

      if (value) document.documentElement.dataset.effects = 'reduced';
      else delete document.documentElement.dataset.effects;
    },
    { immediate: true },
  );

  function setTheme(value: ThemePreference): void {
    theme.value = value;
  }

  function setLyricsSize(value: LyricsSize): void {
    lyricsSize.value = value;
  }

  function setSongNotifications(value: boolean): void {
    songNotifications.value = value;
  }

  function setReduceEffects(value: boolean): void {
    reduceEffects.value = value;
  }

  return {
    theme,
    setTheme,
    lyricsSize,
    setLyricsSize,
    songNotifications,
    setSongNotifications,
    reduceEffects,
    setReduceEffects,
  };
});
