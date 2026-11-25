// The receiver's view of the karaoke messages the Host sends over the Cadenza Cast namespace. The rules are pure, so
// they are tested without a Cast device. Text is bounded here, because the receiver draws whatever arrives.
export const karaokeNamespace = 'urn:x-cast:app.cadenza.karaoke';

const textLimit = 500;

/**
 * @typedef {{ mode: 'audio_only' | 'full_suite', title: string, line: string, next: string }} ReceiverState
 * @typedef {{ type?: unknown, title?: unknown, mode?: unknown, text?: unknown, next?: unknown }} KaraokeMessage
 */

/** @returns {ReceiverState} */
export function initialReceiverState() {
  return { mode: 'audio_only', title: '', line: '', next: '' };
}

/**
 * @param {ReceiverState} state
 * @param {unknown} message
 * @returns {ReceiverState}
 */
export function reduceKaraoke(state, message) {
  if (typeof message !== 'object' || message === null) return state;

  const { type, title, mode, text, next } = /** @type {KaraokeMessage} */ (
    message
  );

  switch (type) {
    case 'session':
      return {
        ...state,
        title: boundedText(title),
        mode: mode === 'full_suite' ? 'full_suite' : 'audio_only',
      };
    case 'line':
      return {
        ...state,
        line: boundedText(text),
        next: boundedText(next),
      };
    default:
      return state;
  }
}

/**
 * @param {unknown} value
 * @returns {string}
 */
function boundedText(value) {
  return typeof value === 'string' ? value.slice(0, textLimit) : '';
}
