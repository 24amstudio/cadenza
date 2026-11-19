// Favorites and history live in this browser only. Storage can be missing, blocked, or full, so every access is guarded.
// A value that cannot be written is still kept in memory, so the page keeps working for this visit.
export interface KeyValueStore {
  read(key: string): string | null;
  write(key: string, value: string): void;
}

// Only the two methods used here, so a test can supply storage that throws without faking the whole interface.
export type KeyValueStorage = Pick<Storage, 'getItem' | 'setItem'>;

// The storage provider returns null when the browser has no local storage, and may throw when access is blocked.
export function keyValueStore(
  storage: () => KeyValueStorage | null,
): KeyValueStore {
  const cache = new Map<string, string | null>();

  return {
    read(key) {
      if (!cache.has(key)) cache.set(key, readStored(storage, key));

      return cache.get(key) ?? null;
    },
    write(key, value) {
      cache.set(key, value);
      writeStored(storage, key, value);
    },
  };
}

export function browserLocalStorage(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

function readStored(
  storage: () => KeyValueStorage | null,
  key: string,
): string | null {
  try {
    return storage()?.getItem(key) ?? null;
  } catch {
    return null;
  }
}

function writeStored(
  storage: () => KeyValueStorage | null,
  key: string,
  value: string,
): void {
  try {
    storage()?.setItem(key, value);
  } catch {
    // Full or blocked. The value stays in memory for this visit.
  }
}
