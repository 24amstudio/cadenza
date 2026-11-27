<script setup lang="ts">
import { computed, ref } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import { castDisplayLabel, castPresentationLabel } from '~/lib/cast';
import type { CastPresentation } from '~/lib/protocol/types';
import { useHostStore } from '~/stores/host';

// Chooses the Mac's audio output. Music plays to the default output, so the choice routes Music's audio there.
// The controls open in a popover from the speaker button, so the player bar keeps a single icon.
const host = useHostStore();
const panelOpen = ref(false);

function onPanelToggle(event: Event): void {
  // SAFETY: the panel's only toggle listener receives the ToggleEvent its popover dispatches, which carries newState.
  panelOpen.value = (event as ToggleEvent).newState === 'open';
}

const outputs = computed(() => host.snapshot?.audioOutputs ?? []);
const cast = computed(() => host.snapshot?.cast ?? null);
const transmit = computed(() => cast.value?.transmit ?? null);

const videoOutput = computed(
  () => host.snapshot?.videoOutput ?? 'host_display',
);

const sending = computed(
  () =>
    transmit.value?.state === 'starting' ||
    transmit.value?.state === 'transmitting',
);

const selected = computed(
  () => outputs.value.find((output) => output.isDefault)?.id ?? '',
);

function choose(event: Event): void {
  if (!(event.target instanceof HTMLSelectElement)) return;

  host.setOutput(event.target.value);
}

function isSendingTo(name: string): boolean {
  return sending.value && transmit.value?.device === name;
}

// The name a person recognizes. The device ID that commands carry is not shown.
function labelOf(name: string | null): string {
  return (
    cast.value?.devices.find((device) => device.name === name)?.label ??
    name ??
    ''
  );
}

function sendAudio(name: string): void {
  host.setCastTransmit(name, true);
}

function stopAudio(): void {
  host.setCastTransmit(transmit.value?.device ?? '', false);
}

// The karaoke line is drawn in one place: over Music's window on this Mac, or on a Cast device.
function chooseLyricTarget(target: 'host_display' | 'cast_transmitter'): void {
  host.setVideoOutput(target);
}

const lipSyncOffsetMs = computed(() => host.snapshot?.lipSyncOffsetMs ?? 0);

// The AVR delay moves karaoke lines later or earlier, in steps of 50 ms, within the Host's limit of 500 ms.
function nudgeLipSync(step: number): void {
  host.setLipSyncOffset(
    Math.max(-500, Math.min(500, lipSyncOffsetMs.value + step)),
  );
}

function choosePresentation(value: CastPresentation): void {
  host.setCastPresentation(value);
}

const presentations: { value: CastPresentation; label: string }[] = [
  { value: 'auto', label: 'Auto' },
  { value: 'audio_only', label: 'Audio Only' },
  { value: 'full_suite', label: 'Full Suite' },
];
</script>

<template>
  <div class="output-menu">
    <button
      type="button"
      class="output-trigger"
      popovertarget="output-panel"
      aria-label="Audio output and karaoke"
      :aria-expanded="panelOpen"
    >
      <AppIcon name="speaker" />
    </button>
    <div
      id="output-panel"
      class="output-panel"
      popover="auto"
      aria-label="Audio output and karaoke"
      @toggle="onPanelToggle"
    >
      <select
        v-if="outputs.length > 0"
        class="output-select"
        aria-label="Audio output"
        :value="selected"
        :disabled="!host.connected"
        @change="choose"
      >
        <option v-for="output in outputs" :key="output.id" :value="output.id">
          {{ output.name }}
        </option>
      </select>
      <section class="cast" aria-label="Karaoke lyrics">
        <p class="cast-title">Karaoke lyrics on</p>
        <button
          class="cast-button"
          type="button"
          :aria-pressed="videoOutput === 'host_display'"
          :disabled="!host.connected"
          @click="chooseLyricTarget('host_display')"
        >
          This Mac
        </button>
        <button
          class="cast-button"
          type="button"
          :aria-pressed="videoOutput === 'cast_transmitter'"
          :disabled="!host.connected"
          @click="chooseLyricTarget('cast_transmitter')"
        >
          Cast device
        </button>
        <p v-if="videoOutput === 'cast_transmitter'" class="cast-note">
          Karaoke lyrics display on the active Cast receiver rather than on this
          Mac.
        </p>
        <p class="cast-title">AVR lip-sync offset, {{ lipSyncOffsetMs }} ms</p>
        <button
          class="cast-button"
          type="button"
          :disabled="!host.connected"
          @click="nudgeLipSync(-50)"
        >
          Earlier 50 ms
        </button>
        <button
          class="cast-button"
          type="button"
          :disabled="!host.connected"
          @click="nudgeLipSync(50)"
        >
          Later 50 ms
        </button>
      </section>
      <section
        v-if="cast && (cast.pendingStages.length > 0 || cast.stages.length > 0)"
        class="cast"
        aria-label="Cadenza TV"
      >
        <p class="cast-title">Cadenza TV</p>
        <ul class="cast-devices">
          <li
            v-for="pending in cast.pendingStages"
            :key="pending.receiverId"
            class="cast-device"
          >
            <span>{{ pending.name }}, PIN {{ pending.pin }}</span>
            <button
              class="cast-button"
              type="button"
              :disabled="!host.connected"
              @click="host.approveStage(pending.pin)"
            >
              Approve
            </button>
          </li>
          <li
            v-for="stage in cast.stages"
            :key="stage.receiverId"
            class="cast-device"
          >
            <span
              >{{ stage.name }},
              {{
                stage.transmitting ? 'Playing audio' : 'Full Cadenza Suite'
              }}</span
            >
            <button
              class="cast-button"
              type="button"
              :disabled="!host.connected"
              @click="
                host.setCastTransmit(
                  `stage:${stage.receiverId}`,
                  !stage.transmitting,
                )
              "
            >
              {{
                stage.transmitting ? 'Stop sending audio' : 'Send audio here'
              }}
            </button>
            <p
              v-if="stage.status"
              class="cast-status"
              :class="{ mismatch: stage.status.mismatch }"
              role="status"
            >
              {{ stage.status.text }}
            </p>
          </li>
        </ul>
      </section>
      <section v-if="cast" class="cast" aria-label="Google Cast">
        <p class="cast-title">
          Google Cast, {{ castPresentationLabel(cast.presentation) }}
        </p>
        <div class="cast-presentation" role="group" aria-label="Cast mode">
          <button
            v-for="option in presentations"
            :key="option.value"
            class="cast-button"
            type="button"
            :aria-pressed="cast.presentation === option.value"
            :disabled="!host.connected"
            @click="choosePresentation(option.value)"
          >
            {{ option.label }}
          </button>
        </div>
        <p v-if="cast.presentation === 'full_suite'" class="cast-note">
          Displays motion artwork and synced lyrics on screen-capable Cast
          receivers.
        </p>
        <p
          v-if="transmit?.state === 'starting'"
          class="cast-note"
          role="status"
        >
          Connecting to {{ labelOf(transmit.device) }}.
        </p>
        <p
          v-else-if="transmit?.state === 'transmitting'"
          class="cast-status"
          :class="{ mismatch: transmit.status?.mismatch }"
          role="status"
        >
          {{ transmit.status?.text ?? `Sending audio to ${transmit.device}.` }}
        </p>
        <p
          v-else-if="transmit?.state === 'failed'"
          class="cast-note"
          role="alert"
        >
          {{ transmit.reason }}
        </p>
        <ul v-if="cast.devices.length > 0" class="cast-devices">
          <li
            v-for="device in cast.devices"
            :key="device.name"
            class="cast-device"
          >
            <span
              >{{ device.label }}, {{ castDisplayLabel(device.display) }}</span
            >
            <button
              v-if="isSendingTo(device.name)"
              class="cast-button"
              type="button"
              :disabled="!host.connected"
              @click="stopAudio"
            >
              Stop sending audio
            </button>
            <button
              v-else
              class="cast-button"
              type="button"
              :disabled="!host.connected || sending"
              @click="sendAudio(device.name)"
            >
              Send audio here
            </button>
          </li>
        </ul>
        <p v-else class="cast-note">No Cast devices found on this network.</p>
        <p class="cast-note">
          Stereo audio streams as AAC; 5.1 surround streams as AC-3 when the
          encoder helper is bundled.
        </p>
      </section>
    </div>
  </div>
</template>

<style scoped>
.output-trigger {
  anchor-name: --output-trigger;
  display: grid;
  place-items: center;
  width: 34px;
  height: 34px;
  border: 0;
  border-radius: 999px;
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 18px;
}

.output-trigger:hover,
.output-trigger[aria-expanded='true'] {
  background: var(--color-fill);
  color: var(--color-accent);
}

/* The panel rises above the trigger. Browsers without anchor positioning keep the fixed offset. */
.output-panel {
  position: fixed;
  inset: auto 16px 96px auto;
  display: grid;
  gap: 10px;
  width: min(360px, calc(100vw - 32px));
  max-height: min(70vh, 560px);
  margin: 0;
  padding: 14px;
  overflow-y: auto;
  border: 1px solid var(--color-separator);
  border-radius: 16px;
  background: var(--color-surface);
  color: var(--color-text);
  box-shadow: 0 12px 32px rgb(0 0 0 / 0.28);
}

/* The author display rule would show a closed popover, so the hidden state is restated for it. */
.output-panel:not(:popover-open) {
  display: none;
}

@supports (bottom: anchor(top)) {
  .output-panel {
    position-anchor: --output-trigger;
    bottom: calc(anchor(top) + 10px);
  }
}

.output-select {
  max-width: 180px;
  min-height: 32px;
  padding: 0 8px;
  border: 1px solid var(--color-fill-strong);
  border-radius: 8px;
  background: transparent;
  color: var(--color-text);
  font: inherit;
  font-size: 13px;
}

.output-select:disabled {
  opacity: 0.5;
}

.cast {
  display: grid;
  gap: 4px;
  font-size: 13px;
  color: var(--color-text-secondary);
}

.cast-title {
  color: var(--color-text);
  font-weight: 600;
}

.cast-devices {
  display: grid;
  gap: 6px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.cast-device {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.cast-button {
  min-height: 32px;
  padding: 0 10px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill-strong);
  color: var(--color-text);
  font: inherit;
  font-size: 13px;
}

.cast-button:disabled {
  opacity: 0.5;
}

.cast-note {
  margin: 0;
  color: var(--color-text-tertiary);
}

/* A route line spans the whole row, so it wraps below its device name and button. */
.cast-status {
  flex-basis: 100%;
  margin: 0;
  color: var(--color-text-tertiary);
}

.cast-status.mismatch {
  color: var(--color-danger);
}
</style>
