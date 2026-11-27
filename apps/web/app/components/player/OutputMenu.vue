<script setup lang="ts">
import { computed, ref } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import RemoteAudioSection from '~/components/player/RemoteAudioSection.vue';
import { castDisplayLabel } from '~/lib/cast';
import type { CastPresentation } from '~/lib/protocol/types';
import { useHostStore } from '~/stores/host';

// The panel groups controls by destination: Mac output, Wi-Fi stream, karaoke, Cadenza TV and Google Cast.
// The output glyph keeps the trigger distinct from the volume control beside it.
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

function pickOutput(id: string): void {
  host.setOutput(id);
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
  { value: 'audio_only', label: 'Audio only' },
  { value: 'full_suite', label: 'Full suite' },
];
</script>

<template>
  <div class="output-menu">
    <button
      type="button"
      class="output-trigger"
      popovertarget="output-panel"
      aria-label="Output and streaming"
      :aria-expanded="panelOpen"
    >
      <AppIcon name="output" />
    </button>
    <div
      id="output-panel"
      class="output-panel"
      popover="auto"
      aria-label="Output and streaming"
      @toggle="onPanelToggle"
    >
      <h2 class="output-title">Output</h2>

      <section
        v-if="outputs.length > 0"
        class="om-section"
        aria-labelledby="output-mac"
      >
        <h3 id="output-mac" class="om-heading">Mac audio</h3>
        <div class="om-list">
          <button
            v-for="output in outputs"
            :key="output.id"
            type="button"
            class="om-row"
            :aria-pressed="output.isDefault"
            :disabled="!host.connected"
            @click="pickOutput(output.id)"
          >
            <span class="om-row-text">
              <span class="om-row-title">{{ output.name }}</span>
              <span class="om-row-sub">{{ output.transport }}</span>
            </span>
            <AppIcon v-if="output.isDefault" name="check" class="om-check" />
          </button>
        </div>
      </section>

      <RemoteAudioSection />

      <section class="om-section" aria-labelledby="output-karaoke">
        <h3 id="output-karaoke" class="om-heading">Karaoke lyrics</h3>
        <div class="om-segmented" role="group" aria-labelledby="output-karaoke">
          <button
            type="button"
            class="om-segment"
            :aria-pressed="videoOutput === 'host_display'"
            :disabled="!host.connected"
            @click="chooseLyricTarget('host_display')"
          >
            This Mac
          </button>
          <button
            type="button"
            class="om-segment"
            :aria-pressed="videoOutput === 'cast_transmitter'"
            :disabled="!host.connected"
            @click="chooseLyricTarget('cast_transmitter')"
          >
            Cast device
          </button>
        </div>
        <p v-if="videoOutput === 'cast_transmitter'" class="om-note">
          Lyrics show on the active Cast receiver, not on this Mac.
        </p>
        <div class="om-row om-row-static">
          <span class="om-row-text">
            <span class="om-row-title">AVR lip sync</span>
            <span class="om-row-sub">{{ lipSyncOffsetMs }} ms</span>
          </span>
          <span class="om-stepper">
            <button
              type="button"
              class="om-action"
              aria-label="Earlier by 50 milliseconds"
              :disabled="!host.connected"
              @click="nudgeLipSync(-50)"
            >
              −50 ms
            </button>
            <button
              type="button"
              class="om-action"
              aria-label="Later by 50 milliseconds"
              :disabled="!host.connected"
              @click="nudgeLipSync(50)"
            >
              +50 ms
            </button>
          </span>
        </div>
      </section>

      <section
        v-if="cast && (cast.pendingStages.length > 0 || cast.stages.length > 0)"
        class="om-section"
        aria-labelledby="output-tv"
      >
        <h3 id="output-tv" class="om-heading">Cadenza TV</h3>
        <div class="om-list">
          <div
            v-for="pending in cast.pendingStages"
            :key="pending.receiverId"
            class="om-row om-row-static"
          >
            <span class="om-row-text">
              <span class="om-row-title">{{ pending.name }}</span>
              <span class="om-row-sub">PIN {{ pending.pin }}</span>
            </span>
            <button
              type="button"
              class="om-action om-action-primary"
              :disabled="!host.connected"
              @click="host.approveStage(pending.pin)"
            >
              Approve
            </button>
          </div>
          <div
            v-for="stage in cast.stages"
            :key="stage.receiverId"
            class="om-row om-row-static"
          >
            <span class="om-row-text">
              <span class="om-row-title">{{ stage.name }}</span>
              <span class="om-row-sub">
                {{
                  stage.transmitting ? 'Playing audio' : 'Full Cadenza Suite'
                }}
              </span>
              <span
                v-if="stage.status"
                class="om-status"
                :class="{ mismatch: stage.status.mismatch }"
                role="status"
              >
                {{ stage.status.text }}
              </span>
            </span>
            <button
              type="button"
              class="om-action"
              :disabled="!host.connected"
              @click="
                host.setCastTransmit(
                  `stage:${stage.receiverId}`,
                  !stage.transmitting,
                )
              "
            >
              {{ stage.transmitting ? 'Stop' : 'Send audio here' }}
            </button>
          </div>
        </div>
      </section>

      <section v-if="cast" class="om-section" aria-labelledby="output-cast">
        <h3 id="output-cast" class="om-heading">Google Cast</h3>
        <div class="om-segmented" role="group" aria-label="Cast presentation">
          <button
            v-for="option in presentations"
            :key="option.value"
            type="button"
            class="om-segment"
            :aria-pressed="cast.presentation === option.value"
            :disabled="!host.connected"
            @click="choosePresentation(option.value)"
          >
            {{ option.label }}
          </button>
        </div>
        <p v-if="cast.presentation === 'full_suite'" class="om-note">
          Displays motion artwork and synced lyrics on screen-capable Cast
          receivers.
        </p>
        <p
          v-if="transmit?.state === 'starting'"
          class="om-status"
          role="status"
        >
          Connecting to {{ labelOf(transmit.device) }}.
        </p>
        <p
          v-else-if="transmit?.state === 'transmitting'"
          class="om-status"
          :class="{ mismatch: transmit.status?.mismatch }"
          role="status"
        >
          {{ transmit.status?.text ?? `Sending audio to ${transmit.device}.` }}
        </p>
        <p
          v-else-if="transmit?.state === 'failed'"
          class="om-status alert"
          role="alert"
        >
          {{ transmit.reason }}
        </p>
        <div v-if="cast.devices.length > 0" class="om-list">
          <div
            v-for="device in cast.devices"
            :key="device.name"
            class="om-row om-row-static"
          >
            <span class="om-row-text">
              <span class="om-row-title">{{ device.label }}</span>
              <span class="om-row-sub">{{
                castDisplayLabel(device.display)
              }}</span>
            </span>
            <button
              v-if="isSendingTo(device.name)"
              type="button"
              class="om-action"
              :disabled="!host.connected"
              @click="stopAudio"
            >
              Stop
            </button>
            <button
              v-else
              type="button"
              class="om-action"
              :disabled="!host.connected || sending"
              @click="sendAudio(device.name)"
            >
              Send audio here
            </button>
          </div>
        </div>
        <p v-else class="om-note">No Cast devices found on this network.</p>
        <p class="om-note">
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
  gap: 18px;
  width: min(360px, calc(100vw - 32px));
  max-height: min(70vh, 600px);
  margin: 0;
  padding: 16px;
  overflow-y: auto;
  border: 1px solid var(--color-separator);
  border-radius: 20px;
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

.output-title {
  margin: 0;
  color: var(--color-text);
  font-size: 17px;
  font-weight: 600;
}
</style>
