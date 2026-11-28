import { defineStore } from 'pinia';
import { computed, ref, watch } from 'vue';
import { useRuntimeConfig } from '#app';
import { createCredentialStore } from '~/lib/host/credentials';
import { browserStorage } from '~/lib/host/browserStorage';
import { lanAudioSocketUrl, socketUrlFor } from '~/lib/host/endpoint';
import {
  clampToBounds,
  defaultRemoteAudioSettings,
  remoteAudioBounds,
  type RemoteAudioSettings,
  type RemoteAudioHostSetup,
  type RemoteAudioStreamMode,
} from '~/lib/remoteAudio/config';
import {
  RemoteAudioReceiver,
  remoteAudioSocketUrl,
  type RemoteAudioStatus,
} from '~/lib/remoteAudio/receiver';
import { useHostStore } from '~/stores/host';

const settingsKey = 'cadenza.web.remoteAudio';

const idleStatus: RemoteAudioStatus = {
  state: 'idle',
  socketOpen: false,
  linkHealthy: false,
  calibrationState: 'not_required',
  clockDriftPpm: 0,
  droppedStaleFrames60s: 0,
  playoutDroppedFrames: 0,
  networkJitterMs: null,
  dropoutMs60s: 0,
  transmitting: false,
  networkRttMs: null,
  processingRttMs: null,
  quality: null,
  qualityReason: 'steady',
  message: '',
  setup: null,
  roomStatus: 'not_measured',
};

// The settings are a per-viewer convenience. Streaming always starts off, because it needs a user gesture to open audio.
function loadSettings(): RemoteAudioSettings {
  try {
    const stored = browserStorage()?.getItem(settingsKey);

    if (!stored) return { ...defaultRemoteAudioSettings };

    // SAFETY: every field is read below with a default or a clamp, so a stored value of the wrong shape is ignored.
    const parsed = JSON.parse(stored) as Partial<RemoteAudioSettings>;

    return {
      ...defaultRemoteAudioSettings,
      streamMode: parsed.streamMode ?? defaultRemoteAudioSettings.streamMode,
      crossoverHz: clampToBounds(
        parsed.crossoverHz ?? remoteAudioBounds.crossoverHz.default,
        remoteAudioBounds.crossoverHz,
      ),
      subGainDb: clampToBounds(
        parsed.subGainDb ?? remoteAudioBounds.subGainDb.default,
        remoteAudioBounds.subGainDb,
      ),
      phaseInvert: parsed.phaseInvert === true,
      manualDistanceOffsetMs: clampToBounds(
        parsed.manualDistanceOffsetMs ??
          remoteAudioBounds.manualDistanceOffsetMs.default,
        remoteAudioBounds.manualDistanceOffsetMs,
      ),
    };
  } catch {
    return { ...defaultRemoteAudioSettings };
  }
}

function saveSettings(settings: RemoteAudioSettings): void {
  try {
    browserStorage()?.setItem(
      settingsKey,
      JSON.stringify({ ...settings, enabled: false }),
    );
  } catch {
    // A full or blocked store only loses the remembered settings.
  }
}

export const useRemoteAudioStore = defineStore('remoteAudio', () => {
  const host = useHostStore();
  const baseURL = useRuntimeConfig().app.baseURL;
  const settings = ref<RemoteAudioSettings>(loadSettings());
  const status = ref<RemoteAudioStatus>({ ...idleStatus });
  const running = ref(false);
  let receiver: RemoteAudioReceiver | null = null;
  /** The last setup the Host sent, so an echo of the same values does not rewrite the local settings. */
  let lastHostSetup = '';

  /** The LAN socket for this Remote, or null when no Wi-Fi address is known. Bluetooth never streams audio. */
  const audioSocketUrl = computed<string | null>(() => {
    if (window.location.protocol === 'http:') {
      return remoteAudioSocketUrl(socketUrlFor(window.location.href));
    }

    const lan = createCredentialStore(browserStorage()).read()?.lan;

    return lan ? remoteAudioSocketUrl(lanAudioSocketUrl(lan)) : null;
  });

  // Bluetooth is only started when no Wi-Fi socket welcomes, so a linked Bluetooth state means audio has no Wi-Fi path.
  const wifiAvailable = computed(
    () => host.bluetoothState !== 'linked' && audioSocketUrl.value !== null,
  );

  // A Remote that falls back to Bluetooth stops its Wi-Fi stream, and Music returns to the Mac.
  watch(
    () => host.bluetoothState,
    (state) => {
      if (state === 'linked' && running.value) {
        stop('Bluetooth cannot stream audio, so Wi-Fi streaming stopped.');
      }
    },
  );

  /** Starts streaming in a mode. Each call after the first only sends the new settings. */
  async function choose(mode: RemoteAudioStreamMode): Promise<void> {
    update({ streamMode: mode, enabled: true });

    if (receiver !== null) {
      receiver.sendConfig(settings.value);

      return;
    }

    const url = audioSocketUrl.value;
    const credential = createCredentialStore(browserStorage()).read();

    if (url === null || credential === null) {
      status.value = {
        ...idleStatus,
        state: 'failed',
        message: 'Open Cadenza Web on the same Wi-Fi network as Cadenza Host.',
      };

      return;
    }

    receiver = new RemoteAudioReceiver(
      url,
      { clientId: credential.remoteId, token: credential.token },
      (next) => {
        status.value = next;

        if (next.setup !== null) adoptHostSetup(next.setup);
      },
    );
    running.value = true;

    try {
      await receiver.start(baseURL);
      receiver.sendConfig(settings.value);
    } catch (error) {
      stop(
        error instanceof Error
          ? error.message
          : 'The audio output could not start.',
      );
    }
  }

  /**
   * Asks the Host to measure a new output environment. The Host drops the saved room and measures it while the split
   * plays, so this needs a running stream.
   */
  function newEnvironment(): void {
    if (receiver === null) {
      status.value = {
        ...status.value,
        message:
          'Start streaming to this device before setting up a new environment.',
      };

      return;
    }

    if (!receiver.sendCommand('new_environment')) {
      status.value = {
        ...status.value,
        message:
          'The Host is still connecting. Try again once the stream is live.',
      };
    }
  }

  /** The Host owns the setup, so its values replace the local ones. Only a change is written, which ends the echo. */
  function adoptHostSetup(setup: RemoteAudioHostSetup): void {
    const key = JSON.stringify(setup);

    if (key === lastHostSetup) return;

    lastHostSetup = key;
    settings.value = {
      ...settings.value,
      enabled: setup.enabled,
      streamMode: setup.streamMode,
      crossoverHz: setup.crossoverHz,
      subGainDb: setup.subGainDb,
      phaseInvert: setup.phaseInvert,
      manualDistanceOffsetMs: setup.manualDistanceOffsetMs,
    };
    saveSettings(settings.value);
  }

  /** Stops streaming, and tells the Host to return Music to the Mac. */
  function stop(message = ''): void {
    receiver?.stop();
    receiver = null;
    running.value = false;
    update({ enabled: false });
    status.value = { ...idleStatus, message };
  }

  /** Applies a settings change. Each bound is enforced here, so the Host never receives an out-of-range value. */
  function update(patch: Partial<RemoteAudioSettings>): void {
    settings.value = {
      ...settings.value,
      ...patch,
      crossoverHz: clampToBounds(
        patch.crossoverHz ?? settings.value.crossoverHz,
        remoteAudioBounds.crossoverHz,
      ),
      subGainDb: clampToBounds(
        patch.subGainDb ?? settings.value.subGainDb,
        remoteAudioBounds.subGainDb,
      ),
      manualDistanceOffsetMs: clampToBounds(
        patch.manualDistanceOffsetMs ?? settings.value.manualDistanceOffsetMs,
        remoteAudioBounds.manualDistanceOffsetMs,
      ),
    };
    saveSettings(settings.value);

    if (receiver !== null && running.value) {
      receiver.sendConfig(settings.value);
    }
  }

  return {
    settings,
    status,
    running,
    wifiAvailable,
    choose,
    stop,
    update,
    newEnvironment,
  };
});
