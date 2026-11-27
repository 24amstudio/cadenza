// The browser timer behind the Host client's callbacks. The returned function cancels it.
export function scheduleTask(
  callback: () => void,
  delayMs: number,
): () => void {
  const handle = setTimeout(callback, delayMs);

  return () => clearTimeout(handle);
}
