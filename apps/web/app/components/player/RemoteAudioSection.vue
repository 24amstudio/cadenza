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
  <section class="om-section" aria-labelledby="remote-audio-title">
    <div class="om-heading-row">
      <h3 id="remote-audio-title" class="om-heading">Stream over Wi-Fi</h3>
      <span v-if="!audio.wifiAvailable" class="om-badge">Wi-Fi only</span>
    </div>
    <p v-if="!audio.wifiAvailable" class="om-note">
      Bluetooth cannot carry audio. Open Cadenza Web on the same Wi-Fi network
      as Cadenza Host to stream.
    </p>

    <div class="om-segmented" role="group" aria-label="Stream mode">
      <button
        type="button"
        class="om-segment"
        :aria-pressed="audio.running && pureMode"
        :disabled="!audio.wifiAvailable"
        @click="choose(pureStreamMode)"
      >
        Stream to this device
      </button>
      <button
        type="button"
        class="om-segment"
        :aria-pressed="audio.running && split"
        :disabled="!audio.wifiAvailable"
        @click="choose('crossover_split')"
      >
        Subwoofer split
      </button>
    </div>

    <div
      v-if="pureMode && audio.wifiAvailable"
      class="om-segmented"
      role="group"
      aria-label="Mac output"
    >
      <button
        type="button"
        class="om-segment"
        :aria-pressed="audio.settings.streamMode === 'pure_transfer_exclusive'"
        @click="choose('pure_transfer_exclusive')"
      >
        Mute Mac
      </button>
      <button
        type="button"
        class="om-segment"
        :aria-pressed="audio.settings.streamMode === 'pure_transfer_mirror'"
        @click="choose('pure_transfer_mirror')"
      >
        Play on both
      </button>
    </div>

    <div v-if="split && audio.wifiAvailable" class="remote-audio-tune">
      <p class="om-status" :class="{ 'remote-audio-locked': syncLocked }">
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
        <span class="remote-audio-slider-head">
          <span>Crossover</span>
          <span class="remote-audio-value"
            >{{ audio.settings.crossoverHz }} Hz</span
          >
        </span>
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
        <span class="remote-audio-slider-head">
          <span>Sub gain</span>
          <span class="remote-audio-value"
            >{{ audio.settings.subGainDb }} dB</span
          >
        </span>
        <input
          type="range"
          :min="remoteAudioBounds.subGainDb.min"
          :max="remoteAudioBounds.subGainDb.max"
          step="0.5"
          :value="audio.settings.subGainDb"
          @input="setNumber('subGainDb', $event)"
        />
      </label>
      <label class="remote-audio-slider">
        <span class="remote-audio-slider-head">
          <span>Distance trim</span>
          <span class="remote-audio-value"
            >{{ audio.settings.manualDistanceOffsetMs }} ms</span
          >
        </span>
        <input
          type="range"
          :min="remoteAudioBounds.manualDistanceOffsetMs.min"
          :max="remoteAudioBounds.manualDistanceOffsetMs.max"
          step="0.5"
          :value="audio.settings.manualDistanceOffsetMs"
          @input="setNumber('manualDistanceOffsetMs', $event)"
        />
      </label>
      <label class="remote-audio-check">
        <span>Invert sub phase (180°)</span>
        <input
          type="checkbox"
          :checked="audio.settings.phaseInvert"
          @change="
            audio.update({
              phaseInvert: ($event.target as HTMLInputElement).checked,
            })
          "
        />
      </label>
    </div>

    <div class="remote-audio-room">
      <div class="om-row om-row-static">
        <span class="om-row-text">
          <span class="om-row-title">Room</span>
          <span class="om-row-sub">{{ roomText }}</span>
        </span>
      </div>
      <button
        type="button"
        class="om-action remote-audio-wide"
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
        class="om-action remote-audio-wide"
        @click="audio.stop()"
      >
        Stop streaming
      </button>
      <p class="om-status" role="status">{{ audio.status.message }}</p>
    </div>
  </section>
</template>

<style scoped>
.remote-audio-tune,
.remote-audio-room,
.remote-audio-foot {
  display: grid;
  gap: 10px;
}

.remote-audio-locked {
  color: var(--color-text);
}

.remote-audio-slider {
  display: grid;
  gap: 4px;
  color: var(--color-text);
  font-size: 13px;
}

.remote-audio-slider-head {
  display: flex;
  justify-content: space-between;
  gap: 8px;
}

.remote-audio-value {
  color: var(--color-text-secondary);
  font-variant-numeric: tabular-nums;
}

.remote-audio-slider input {
  width: 100%;
  accent-color: var(--color-accent);
}

.remote-audio-check {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  min-height: 36px;
  color: var(--color-text);
  font-size: 13px;
}

.remote-audio-check input {
  accent-color: var(--color-accent);
}

.remote-audio-wide {
  width: 100%;
}
</style>
