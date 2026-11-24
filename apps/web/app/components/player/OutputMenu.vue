<script setup lang="ts">
import { computed } from 'vue';
import { castDisplayLabel, castPresentationLabel } from '~/lib/cast';
import { useHostStore } from '~/stores/host';

// Chooses the Mac's audio output. Music plays to the default output, so the choice routes Music's audio there.
const host = useHostStore();

const outputs = computed(() => host.snapshot?.audioOutputs ?? []);
const cast = computed(() => host.snapshot?.cast ?? null);

const selected = computed(
  () => outputs.value.find((output) => output.isDefault)?.id ?? '',
);

function choose(event: Event): void {
  if (!(event.target instanceof HTMLSelectElement)) return;

  host.setOutput(event.target.value);
}
</script>

<template>
  <div class="output-menu">
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
    <section v-if="cast" class="cast" aria-label="Google Cast">
      <p class="cast-title">
        Google Cast, {{ castPresentationLabel(cast.presentation) }}
      </p>
      <ul v-if="cast.devices.length > 0" class="cast-devices">
        <li v-for="device in cast.devices" :key="device.name">
          {{ device.name }}, {{ castDisplayLabel(device.display) }}
        </li>
      </ul>
      <p v-else class="cast-note">No Cast devices found on this network.</p>
      <p class="cast-note">Cadenza does not send audio to Cast devices yet.</p>
    </section>
  </div>
</template>

<style scoped>
.output-menu {
  display: grid;
  gap: 8px;
  justify-items: start;
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
  margin: 0;
  padding: 0;
  list-style: none;
}

.cast-note {
  margin: 0;
  color: var(--color-text-tertiary);
}
</style>
