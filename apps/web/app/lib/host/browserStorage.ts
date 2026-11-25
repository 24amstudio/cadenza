/** The browser's local storage, or null where the browser blocks it. */
export function browserStorage(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}
