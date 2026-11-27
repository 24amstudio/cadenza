<script setup lang="ts">
import { computed } from 'vue';
import {
  remoteAudioBounds,
  type RemoteAudioStreamMode,
} from '~/lib/remoteAudio/config';
import { useRemoteAudioStore } from '~/stores/remoteAudio';

// Streams the Mac's audio over Wi-Fi to this device. Pure transfer sends full-range stereo, and the split sends the
// Host's low-pass sub to the Mac and the high-pass mains here. Bluetooth never carries audio.
const audio = useRemoteAudioStore();

const split = computed(() => audio.settings.streamMode === 'crossover_split');

const pureMode = computed(
  () => audio.settings.streamMode !== 'crossover_split',
);

const pureStreamMode = computed(() =>
  audio.settings.streamMode === 'pure_transfer_mirror'
    ? 'pure_transfer_mirror'
    : 'pure_transfer_exclusive',
);

const syncLocked = computed(() =>
  ['electronic_locked', 'acoustic_locked'].includes(
    audio.status.calibrationState,
  ),
);

const roomText = computed(() => {
  switch (audio.status.roomStatus) {
    case 'measuring':
      return 'Measuring the room for 2 seconds';
    case 'measured':
      return 'Room measured';
    case 'needs_microphone':
      return 'Allow microphone access on the Mac to measure the room';
    case 'failed':
      return 'The room measurement failed';
    default:
      return 'Room not measured yet';
  }
});

const roomMeasured = computed(
  () => audio.status.calibrationState === 'acoustic_locked',
);

function choose(mode: RemoteAudioStreamMode): void {
  void audio.choose(mode);
}

function setNumber(
  key: 'crossoverHz' | 'subGainDb' | 'manualDistanceOffsetMs',
  event: Event,
): void {
  if (!(event.target instanceof HTMLInputElement)) return;

  audio.update({ [key]: Number(event.target.value) });
}
</script>

<template>
  <section class="remote-audio" aria-label="Wi-Fi audio">
    <div class="remote-audio-head">
      <p class="remote-audio-title">Stream over Wi-Fi</p>
      <span v-if="!audio.wifiAvailable" class="badge">Wi-Fi only</span>
    </div>
    <p v-if="!audio.wifiAvailable" class="remote-audio-note">
      Bluetooth cannot carry audio. Open Cadenza Web on the same Wi-Fi network
      as Cadenza Host to stream.
    </p>

    <div class="remote-audio-modes">
      <button
        type="button"
        class="remote-audio-button"
        :aria-pressed="audio.running && pureMode"
        :disabled="!audio.wifiAvailable"
        @click="choose(pureStreamMode)"
      >
        Stream to this device
      </button>
      <button
        type="button"
        class="remote-audio-button"
        :aria-pressed="audio.running && split"
        :disabled="!audio.wifiAvailable"
        @click="choose('crossover_split')"
      >
        Subwoofer split
      </button>
    </div>

    <div
      v-if="pureMode && audio.wifiAvailable"
      class="remote-audio-modes"
      role="group"
      aria-label="Mac output"
    >
      <button
        type="button"
        class="remote-audio-button"
        :aria-pressed="audio.settings.streamMode === 'pure_transfer_exclusive'"
        @click="choose('pure_transfer_exclusive')"
      >
        Mute Mac
      </button>
      <button
        type="button"
        class="remote-audio-button"
        :aria-pressed="audio.settings.streamMode === 'pure_transfer_mirror'"
        @click="choose('pure_transfer_mirror')"
      >
        Play on both
      </button>
    </div>

    <div v-if="split && audio.wifiAvailable" class="remote-audio-tune">
      <p class="remote-audio-sync" :data-locked="syncLocked">
        {{
          roomMeasured
            ? 'Room acoustic locked'
            : syncLocked
              ? 'Electronic sync locked'
              : 'Waiting for sync'
        }}
        <template v-if="audio.status.linkHealthy"> · Wi-Fi healthy</template>
      </p>
      <label class="remote-audio-slider">
        <span>Crossover {{ audio.settings.crossoverHz }} Hz</span>
        <input
          type="range"
          :min="remoteAudioBounds.crossoverHz.min"
          :max="remoteAudioBounds.crossoverHz.max"
          step="1"
          :value="audio.settings.crossoverHz"
          @input="setNumber('crossoverHz', $event)"
        />
      </label>
      <label class="remote-audio-slider">
        <span>Sub gain {{ audio.settings.subGainDb }} dB</span>
        <input
          type="range"
          :min="remoteAudioBounds.subGainDb.min"
          :max="remoteAudioBounds.subGainDb.max"
          step="0.5"
          :value="audio.settings.subGainDb"
          @input="setNumber('subGainDb', $event)"
        />
      </label>
      <label class="remote-audio-check">
        <input
          type="checkbox"
          :checked="audio.settings.phaseInvert"
          @change="
            audio.update({
              phaseInvert: ($event.target as HTMLInputElement).checked,
            })
          "
        />
        Invert sub phase (180°)
      </label>
      <label class="remote-audio-slider">
        <span
          >Distance trim {{ audio.settings.manualDistanceOffsetMs }} ms</span
        >
        <input
          type="range"
          :min="remoteAudioBounds.manualDistanceOffsetMs.min"
          :max="remoteAudioBounds.manualDistanceOffsetMs.max"
          step="0.5"
          :value="audio.settings.manualDistanceOffsetMs"
          @input="setNumber('manualDistanceOffsetMs', $event)"
        />
      </label>
    </div>

    <div class="remote-audio-modes">
      <p class="remote-audio-message">{{ roomText }}</p>

      <button
        type="button"
        class="remote-audio-button"
        :disabled="!audio.running"
        @click="audio.newEnvironment()"
      >
        Set up new LPF output environment
      </button>
    </div>

    <div class="remote-audio-foot">
      <button
        v-if="audio.running"
        type="button"
        class="remote-audio-button"
        @click="audio.stop()"
      >
        Stop streaming
      </button>
      <p class="remote-audio-message" role="status">
        {{ audio.status.message }}
      </p>
    </div>
  </section>
</template>

<style scoped>
.remote-audio {
  display: grid;
  gap: 8px;
  padding-top: 10px;
  border-top: 1px solid var(--color-separator);
}

.remote-audio-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.remote-audio-title {
  color: var(--color-text);
  font-weight: 600;
}

.badge {
  padding: 2px 8px;
  border-radius: 999px;
  background: var(--color-fill);
  color: var(--color-text-secondary);
  font-size: 12px;
}

.remote-audio-note,
.remote-audio-message {
  color: var(--color-text-secondary);
  font-size: 13px;
}

.remote-audio-modes {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.remote-audio-button {
  min-height: 32px;
  padding: 0 10px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill-strong);
  color: var(--color-text);
  font: inherit;
  font-size: 13px;
}

.remote-audio-button[aria-pressed='true'] {
  background: var(--color-accent);
  color: var(--color-surface);
}

.remote-audio-button:disabled {
  color: var(--color-text-tertiary);
}

.remote-audio-tune {
  display: grid;
  gap: 8px;
}

.remote-audio-sync {
  color: var(--color-text-secondary);
  font-size: 13px;
}

.remote-audio-sync[data-locked='true'] {
  color: var(--color-text);
}

.remote-audio-slider {
  display: grid;
  gap: 4px;
  color: var(--color-text);
  font-size: 13px;
}

.remote-audio-check {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--color-text);
  font-size: 13px;
}

.remote-audio-foot {
  display: grid;
  gap: 6px;
}
</style>
