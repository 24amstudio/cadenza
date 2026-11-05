<script setup lang="ts">
import { computed, ref, watch } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import { isValidRemoteName } from '~/lib/host/endpoint';
import { useHostStore } from '~/stores/host';
import {
  usePreferencesStore,
  type LyricsSize,
  type ThemePreference,
} from '~/stores/preferences';

const host = useHostStore();
const preferences = usePreferencesStore();

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
