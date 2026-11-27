<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import {
  notificationAccess,
  requestNotificationAccess,
  showNotification,
  type NotificationAccess,
} from '~/lib/browserNotifications';
import { isValidRemoteName } from '~/lib/host/endpoint';
import { identityOf } from '~/lib/library/identity';
import { browserLocalStorage } from '~/lib/library/keyValue';
import {
  LYRIC_NUDGE_STEP_MS,
  lyricDelayLabel,
  nudgeDelay,
  syncFirstLineDelay,
} from '~/lib/lyricNudge';
import { lyricsLevel } from '~/lib/lyrics';
import { setTasteDigestOptIn, tasteDigestOptedIn } from '~/lib/tasteDigest';
import { useHostStore } from '~/stores/host';
import {
  usePreferencesStore,
  type LyricsSize,
  type ThemePreference,
} from '~/stores/preferences';

const host = useHostStore();
const preferences = usePreferencesStore();

// Lyric timing belongs to the playing song and is saved on the Host, so these controls act on the current track only.
const lyricIdentity = computed(() => {
  const song = host.current?.song;

  return song === undefined ? null : identityOf(song);
});

const timedLyrics = computed(() => lyricsLevel(host.lyricsDocument) >= 2);
const lyricDelayMs = computed(() => host.lyricsDocument?.userOffsetMs ?? 0);

const firstTimedLineStartMs = computed(
  () => host.lyricsDocument?.lines[0]?.startMs ?? null,
);

const lyricTimingReady = computed(
  () => timedLyrics.value && lyricIdentity.value !== null && host.connected,
);

const lyricStepLabel = `${LYRIC_NUDGE_STEP_MS / 1000} s`;

function saveLyricDelay(delayMs: number): void {
  const identity = lyricIdentity.value;

  if (identity === null) return;
  host.setLyricOffset(identity, Math.max(-5000, Math.min(5000, delayMs)));
}

function nudgeLyrics(direction: 1 | -1): void {
  saveLyricDelay(
    nudgeDelay(lyricDelayMs.value, direction * LYRIC_NUDGE_STEP_MS),
  );
}

function syncFirstLyricLine(): void {
  const startMs = firstTimedLineStartMs.value;

  if (startMs === null) return;
  saveLyricDelay(syncFirstLineDelay(startMs, host.positionMs));
}

const themes: { value: ThemePreference; label: string }[] = [
  { value: 'system', label: 'System' },
  { value: 'light', label: 'Light' },
  { value: 'dark', label: 'Dark' },
];

const lyricsSizes: { value: LyricsSize; label: string }[] = [
  { value: 'standard', label: 'Standard' },
  { value: 'large', label: 'Large' },
  { value: 'extra-large', label: 'Extra large' },
];

const nameDraft = ref(host.remoteName);
const confirmingForget = ref(false);

watch(
  () => host.remoteName,
  (name) => {
    nameDraft.value = name;
  },
);

const nameChanged = computed(() => nameDraft.value.trim() !== host.remoteName);

const nameValid = computed(() => isValidRemoteName(nameDraft.value));

const canSaveName = computed(
  () => host.connected && nameChanged.value && nameValid.value,
);

// The version this page is served with, and what the Host says about an update it has found.
const hostUpdateText = computed(() => {
  const update = host.hostUpdate;

  const version = host.hostVersion
    ? `Cadenza Host ${host.hostVersion}`
    : 'Cadenza Host';

  if (update === null) return version;

  switch (update.state) {
    case 'checking':
      return 'Checking for an update';
    case 'ready':
      return `${version}. Version ${update.version ?? 'update'} is ready.`;
    case 'installing':
      return 'Installing the update. Cadenza Host restarts.';
    case 'current':
      return `${version}. Up to date.`;
    default:
      return update.message ?? version;
  }
});

function updateHost(): void {
  host.requestHostUpdate(
    host.hostUpdate?.state === 'ready' ? 'install' : 'check',
  );
}

const statusLabel = computed(() => {
  switch (host.phase) {
    case 'connected':
      return 'Connected';
    case 'reconnecting':
      return 'Reconnecting';
    case 'connecting':
      return 'Connecting';
    case 'pairing':
      return 'Pairing';
    case 'pairing-failed':
      return 'Pairing failed';
    case 'bluetooth-idle':
      return 'Not connected';
    default:
      return 'Not paired';
  }
});

function saveName(): void {
  if (!canSaveName.value) return;
  host.renameRemote(nameDraft.value.trim());
}

function forget(): void {
  confirmingForget.value = false;
  host.forgetBrowser();
}

const songAlertAccess = ref<NotificationAccess>(notificationAccess());

// The site's permission can change in the browser while this page is open, so it is read again when the page regains focus.
function refreshSongAlertAccess(): void {
  songAlertAccess.value = notificationAccess();
}

onMounted(() => window.addEventListener('focus', refreshSongAlertAccess));

onUnmounted(() => window.removeEventListener('focus', refreshSongAlertAccess));

// Off until the listener turns it on. The digest is read at each connect, so a change applies from the next one.
const tasteOptIn = ref(tasteDigestOptedIn(browserLocalStorage()));

function toggleTasteOptIn(): void {
  tasteOptIn.value = !tasteOptIn.value;
  setTasteDigestOptIn(browserLocalStorage(), tasteOptIn.value);
}

const songAlertNote = computed(() => {
  switch (songAlertAccess.value) {
    case 'unsupported':
      return 'This browser cannot show notifications for this page. Notifications need HTTPS or localhost.';
    case 'denied':
      return "Notifications are blocked for this site. Allow them in your browser's site settings, then turn this on again.";
    default:
      return 'Show a system notification when a different song starts.';
  }
});

// The browser opens its permission prompt only from a click, so turning alerts on starts here. The confirmation is a
// system notification, so it also shows whether the browser delivers song alerts.
async function toggleSongAlerts(): Promise<void> {
  if (preferences.songNotifications) {
    preferences.setSongNotifications(false);

    return;
  }

  songAlertAccess.value = await requestNotificationAccess();

  if (songAlertAccess.value !== 'granted') return;

  preferences.setSongNotifications(true);
  showNotification(
    'Song changes are on',
    'Cadenza Remote will notify you when a different song starts.',
  );
}
</script>

<template>
  <div class="settings">
    <header class="page-header">
      <h1>Settings</h1>
    </header>

    <section class="group" aria-labelledby="appearance-title">
      <h2 id="appearance-title">Appearance</h2>
      <div class="row">
        <span>Theme</span>
        <div class="segmented" role="group" aria-label="Theme">
          <button
            v-for="theme in themes"
            :key="theme.value"
            type="button"
            :class="{ active: preferences.theme === theme.value }"
            :aria-pressed="preferences.theme === theme.value"
            @click="preferences.setTheme(theme.value)"
          >
            {{ theme.label }}
          </button>
        </div>
      </div>
      <div class="row">
        <span>Lyrics size</span>
        <div class="segmented" role="group" aria-label="Lyrics size">
          <button
            v-for="size in lyricsSizes"
            :key="size.value"
            type="button"
            :class="{ active: preferences.lyricsSize === size.value }"
            :aria-pressed="preferences.lyricsSize === size.value"
            @click="preferences.setLyricsSize(size.value)"
          >
            {{ size.label }}
          </button>
        </div>
      </div>
      <div class="row">
        <span id="reduce-effects-label">Reduce animations and effects</span>
        <button
          class="switch"
          type="button"
          role="switch"
          aria-labelledby="reduce-effects-label"
          :aria-checked="preferences.reduceEffects"
          @click="preferences.setReduceEffects(!preferences.reduceEffects)"
        >
          <span class="switch-thumb" aria-hidden="true"></span>
        </button>
      </div>
    </section>

    <section class="group" aria-labelledby="lyric-timing-title">
      <h2 id="lyric-timing-title">Lyric timing</h2>
      <div class="row">
        <span id="lyric-timing-label">Shift lyrics</span>
        <div
          class="timing-controls"
          role="group"
          aria-labelledby="lyric-timing-label"
        >
          <button
            class="quiet-button"
            type="button"
            :aria-label="`Show lyrics ${lyricStepLabel} earlier`"
            :disabled="!lyricTimingReady"
            @click="nudgeLyrics(-1)"
          >
            -{{ lyricStepLabel }}
          </button>
          <span class="timing-value" aria-live="polite">{{
            lyricDelayLabel(lyricDelayMs)
          }}</span>
          <button
            class="quiet-button"
            type="button"
            :aria-label="`Show lyrics ${lyricStepLabel} later`"
            :disabled="!lyricTimingReady"
            @click="nudgeLyrics(1)"
          >
            +{{ lyricStepLabel }}
          </button>
        </div>
      </div>
      <div class="row">
        <span>First timed line</span>
        <button
          class="quiet-button"
          type="button"
          :disabled="!lyricTimingReady || firstTimedLineStartMs === null"
          @click="syncFirstLyricLine"
        >
          Sync first line
        </button>
      </div>
      <p class="footnote">
        <template v-if="lyricTimingReady">
          Timing applies to the song that is playing and is saved on Cadenza
          Host, so every Remote shows it.
        </template>
        <template v-else-if="!host.connected">
          Connect to Cadenza Host to shift lyrics.
        </template>
        <template v-else>
          Timed lyrics for the playing song unlock these controls.
        </template>
      </p>
    </section>

    <section class="group" aria-labelledby="notifications-title">
      <h2 id="notifications-title">Notifications</h2>
      <div class="row">
        <span id="song-alerts-label">Song changes</span>
        <button
          class="switch"
          type="button"
          role="switch"
          aria-labelledby="song-alerts-label"
          :aria-checked="preferences.songNotifications"
          :disabled="songAlertAccess === 'unsupported'"
          @click="toggleSongAlerts"
        >
          <span class="switch-thumb" aria-hidden="true"></span>
        </button>
      </div>
      <p class="footnote" aria-live="polite">{{ songAlertNote }}</p>
    </section>

    <section class="group" aria-labelledby="taste-title">
      <h2 id="taste-title">Taste</h2>
      <div class="row">
        <span id="taste-label">Share taste on connect</span>
        <button
          class="switch"
          type="button"
          role="switch"
          aria-labelledby="taste-label"
          :aria-checked="tasteOptIn"
          @click="toggleTasteOptIn"
        >
          <span class="switch-thumb" aria-hidden="true"></span>
        </button>
      </div>
      <p class="footnote">
        Sends your most played artists and favorite songs when this browser
        connects. Your song list stays on this device.
      </p>
    </section>

    <section class="group" aria-labelledby="browser-title">
      <h2 id="browser-title">This browser</h2>
      <form class="row name-row" @submit.prevent="saveName">
        <label for="remote-name">Name on Cadenza Host</label>
        <div class="name-field">
          <input
            id="remote-name"
            v-model="nameDraft"
            type="text"
            maxlength="120"
            autocomplete="off"
            :aria-invalid="!nameValid"
          />
          <button class="save-button" type="submit" :disabled="!canSaveName">
            Save
          </button>
        </div>
      </form>
      <p v-if="!nameValid" class="field-error">Use 1 to 80 characters.</p>

      <div class="row">
        <span>Forget this Host</span>
        <div v-if="!confirmingForget">
          <button
            class="danger-button"
            type="button"
            @click="confirmingForget = true"
          >
            Forget
          </button>
        </div>
        <div v-else class="confirm">
          <button class="danger-button" type="button" @click="forget">
            Forget Host
          </button>
          <button
            class="quiet-button"
            type="button"
            @click="confirmingForget = false"
          >
            Cancel
          </button>
        </div>
      </div>
      <p class="footnote">
        Forgetting removes this Host from this browser. Remove this browser from
        Cadenza Host to stop it from reconnecting.
      </p>
    </section>

    <section class="group" aria-labelledby="host-title">
      <h2 id="host-title">Cadenza Host</h2>
      <div class="row">
        <span class="host-line">
          <AppIcon name="host" />
          {{ host.hostName ?? 'No Host paired' }}
        </span>
        <span class="status-text">{{ statusLabel }}</span>
      </div>
      <div v-if="host.phase === 'reconnecting'" class="row">
        <span>Connection</span>
        <button class="quiet-button" type="button" @click="host.retry()">
          <AppIcon name="refresh" />
          Try again
        </button>
      </div>
      <div
        v-if="host.connected && host.capabilities.includes('host.update')"
        class="row"
      >
        <span>{{ hostUpdateText }}</span>
        <button
          class="quiet-button"
          type="button"
          :disabled="host.hostUpdate?.state === 'installing'"
          @click="updateHost"
        >
          {{
            host.hostUpdate?.state === 'ready'
              ? 'Install update'
              : 'Check for update'
          }}
        </button>
      </div>
    </section>
  </div>
</template>

<style scoped>
.settings {
  display: grid;
  gap: 28px;
  max-width: 640px;
  margin: 0 auto;
}

.page-header h1 {
  font-family: var(--font-display);
  font-size: 32px;
  font-weight: 750;
  letter-spacing: -0.02em;
}

.group {
  display: grid;
  gap: 4px;
  padding: 18px 20px;
  border-radius: var(--radius-panel);
  background: var(--color-surface);
}

h2 {
  margin: 0 0 8px;
  font-family: var(--font-display);
  font-size: 17px;
  font-weight: 650;
}

.row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  min-height: 46px;
  padding: 6px 0;
}

.name-row {
  flex-wrap: wrap;
}

.name-row label {
  flex: none;
}

.name-field {
  display: flex;
  flex: 1 1 260px;
  gap: 10px;
  justify-content: flex-end;
  min-width: 0;
}

input[type='text'] {
  flex: 1 1 200px;
  min-width: 0;
  height: 36px;
  padding: 0 12px;
  border: 1px solid var(--color-separator);
  border-radius: var(--radius-control);
  background: var(--color-fill);
  font-size: 15px;
}

input[aria-invalid='true'] {
  border-color: var(--color-danger);
}

.field-error {
  color: var(--color-danger);
  font-size: 13px;
}

.footnote {
  color: var(--color-text-tertiary);
  font-size: 13px;
  line-height: 1.45;
}

.segmented {
  display: inline-flex;
  padding: 3px;
  border-radius: 10px;
  background: var(--color-fill);
}

.segmented button {
  height: 30px;
  padding: 0 14px;
  border: 0;
  border-radius: 8px;
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 14px;
  font-weight: 560;
}

.segmented button.active {
  background: var(--color-surface);
  color: var(--color-text);
  box-shadow: 0 2px 8px -4px var(--color-shadow);
}

.timing-controls {
  display: flex;
  align-items: center;
  gap: 8px;
}

.timing-value {
  min-width: 4.5em;
  text-align: center;
  font-variant-numeric: tabular-nums;
}

.save-button,
.danger-button,
.quiet-button {
  height: 34px;
  padding: 0 16px;
  border: 0;
  border-radius: 999px;
  font-size: 14px;
  font-weight: 600;
}

.save-button {
  background: var(--color-accent);
  color: var(--color-on-accent);
}

.danger-button {
  background: transparent;
  color: var(--color-danger);
  box-shadow: inset 0 0 0 1px currentColor;
}

.quiet-button {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  background: var(--color-fill);
  color: var(--color-text);
}

.confirm {
  display: flex;
  gap: 8px;
}

.host-line {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  font-weight: 560;
}

.status-text {
  color: var(--color-text-secondary);
  font-size: 14px;
}

.switch {
  position: relative;
  flex: none;
  width: 51px;
  height: 31px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill-strong);
}

.switch[aria-checked='true'] {
  background: var(--color-accent);
}

.switch:disabled {
  opacity: 0.4;
}

.switch-thumb {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 27px;
  height: 27px;
  border-radius: 50%;
  background: #fff;
  box-shadow: 0 2px 6px rgb(0 0 0 / 0.25);
}

.switch[aria-checked='true'] .switch-thumb {
  transform: translateX(20px);
}

@media (max-width: 719px) {
  .row {
    align-items: flex-start;
    flex-direction: column;
  }

  .name-field {
    width: 100%;
    justify-content: stretch;
  }

  .name-field input {
    flex: 1;
  }
}
</style>
