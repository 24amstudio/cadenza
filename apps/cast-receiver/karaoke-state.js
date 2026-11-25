// The receiver's view of the karaoke messages the Host sends over the Cadenza Cast namespace. The rules are pure, so
// they are tested without a Cast device. Text and URLs are bounded and validated here.
export const karaokeNamespace = 'urn:x-cast:app.cadenza.karaoke';

const textLimit = 500;
const urlLimit = 2048;
const validModes = new Set([
  'audio_only',
  'full_suite',
  'theater',
  'karaoke_video',
]);

/**
 * @typedef {'audio_only' | 'full_suite' | 'theater' | 'karaoke_video'} ReceiverMode
 * @typedef {{
 *   mode: ReceiverMode,
 *   title: string,
 *   artist: string,
 *   artworkUrl: string | null,
 *   motionUrl: string | null,
 *   lipSyncOffsetMs: number,
 *   line: string,
 *   next: string,
 *   translation: string
 * }} ReceiverState
 * @typedef {{
 *   type?: unknown,
 *   title?: unknown,
 *   artist?: unknown,
 *   mode?: unknown,
 *   artworkUrl?: unknown,
 *   motionUrl?: unknown,
 *   lipSyncOffsetMs?: unknown,
 *   text?: unknown,
 *   next?: unknown,
 *   translation?: unknown
 * }} KaraokeMessage
 */

/** @returns {ReceiverState} */
export function initialReceiverState() {
  return {
    mode: 'audio_only',
    title: '',
    artist: '',
    artworkUrl: null,
    motionUrl: null,
    lipSyncOffsetMs: 0,
    line: '',
    next: '',
    translation: '',
  };
}

/**
 * @param {ReceiverState} state
 * @param {unknown} message
 * @returns {ReceiverState}
 */
export function reduceKaraoke(state, message) {
  if (typeof message !== 'object' || message === null) return state;

  const {
    type,
    title,
    artist,
    mode,
    artworkUrl,
    motionUrl,
    lipSyncOffsetMs,
    text,
    next,
    translation,
  } = /** @type {KaraokeMessage} */ (message);

  switch (type) {
    case 'session':
      return {
        ...state,
        title: boundedText(title),
        artist: boundedText(artist),
        mode: normalizeMode(mode),
        artworkUrl: safeUrl(artworkUrl),
        motionUrl: safeUrl(motionUrl),
        lipSyncOffsetMs: clampOffset(lipSyncOffsetMs),
      };
    case 'line':
      return {
        ...state,
        line: boundedText(text),
        next: boundedText(next),
        translation: boundedText(translation),
      };
    default:
      return state;
  }
}

/**
 * @param {unknown} value
 * @returns {ReceiverMode}
 */
function normalizeMode(value) {
  return typeof value === 'string' && validModes.has(value)
    ? /** @type {ReceiverMode} */ (value)
    : 'audio_only';
}

/**
 * @param {unknown} value
 * @returns {string}
 */
function boundedText(value) {
  return typeof value === 'string' ? value.slice(0, textLimit) : '';
}

/**
 * @param {unknown} value
 * @returns {string | null}
 */
function safeUrl(value) {
  if (
    typeof value !== 'string' ||
    value.length === 0 ||
    value.length > urlLimit
  )
    return null;

  try {
    const parsed = new URL(value);

    return parsed.protocol === 'http:' || parsed.protocol === 'https:'
      ? parsed.toString()
      : null;
  } catch {
    return null;
  }
}

/**
 * @param {unknown} value
 * @returns {number}
 */
function clampOffset(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 0;

  return Math.max(-500, Math.min(500, Math.round(value)));
}
