import {
  initialReceiverState,
  karaokeNamespace,
  reduceKaraoke,
} from './karaoke-state.js';

// The Cast receiver plays Widevine HLS / local MP4 video streams with a lower-third True Karaoke overlay, or falls back
// to Karaoke Theater Mode (artwork/motion backdrop + centered synced lyrics).
const context = cast.framework.CastReceiverContext.getInstance();
const playerManager = context.getPlayerManager();

const stage = document.getElementById('stage');
const titleEl = document.getElementById('title');
const artistEl = document.getElementById('artist');
const artworkEl = /** @type {HTMLImageElement} */ (
  document.getElementById('artwork')
);
const motionEl = /** @type {HTMLVideoElement} */ (
  document.getElementById('motion')
);
const lineEl = document.getElementById('line');
const translationEl = document.getElementById('translation');
const nextEl = document.getElementById('next');

let state = initialReceiverState();

function render() {
  if (stage) stage.dataset.mode = state.mode;
  if (titleEl) titleEl.textContent = state.title;
  if (artistEl) artistEl.textContent = state.artist;
  if (lineEl) lineEl.textContent = state.line;
  if (translationEl) translationEl.textContent = state.translation;
  if (nextEl) nextEl.textContent = state.next;

  if (artworkEl) {
    if (state.artworkUrl) {
      if (artworkEl.src !== state.artworkUrl) artworkEl.src = state.artworkUrl;
      artworkEl.hidden = false;
    } else {
      artworkEl.removeAttribute('src');
      artworkEl.hidden = true;
    }
  }

  if (motionEl) {
    if (state.motionUrl) {
      if (motionEl.src !== state.motionUrl) motionEl.src = state.motionUrl;
      motionEl.hidden = false;
    } else {
      motionEl.removeAttribute('src');
      motionEl.hidden = true;
    }
  }
}

playerManager.setMediaPlaybackInfoHandler((loadRequestData, playbackConfig) => {
  const customData = loadRequestData?.media?.customData;
  if (customData && typeof customData.licenseUrl === 'string') {
    playbackConfig.protectionSystem = cast.framework.ContentProtection.WIDEVINE;
    playbackConfig.licenseUrl = customData.licenseUrl;
    playbackConfig.licenseRequestHandler = (requestInfo) => {
      requestInfo.headers = requestInfo.headers ?? {};
      if (typeof customData.mediaUserToken === 'string') {
        requestInfo.headers['Media-User-Token'] = customData.mediaUserToken;
      }
      if (typeof customData.developerToken === 'string') {
        requestInfo.headers.Authorization = `Bearer ${customData.developerToken}`;
      }
    };
  }
  return playbackConfig;
});

context.addCustomMessageListener(karaokeNamespace, (event) => {
  state = reduceKaraoke(state, event.data);
  render();
});

render();
context.start();
