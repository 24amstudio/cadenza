<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import { signalBarCount } from '~/lib/host/linkSignal';
import type { StreamRoundTrip } from '~/lib/remoteAudio/roundTrip';
import type { RemoteAudioQualityView } from '~/lib/remoteAudio/quality';

// Signal bars for the link to Cadenza Host, beside the path that carries it (Bluetooth or Wi-Fi). A down arrow flashes
// when frames arrive and an up arrow when frames leave. Each flash replays because the arrow is re-keyed on every pulse,
const props = defineProps<{
  bars: number;
  overBluetooth: boolean;
  rxPulse: number;
  txPulse: number;
  roundTrip: StreamRoundTrip | null;
  quality: RemoteAudioQualityView | null;
}>();

const transportLabel = computed(() =>
  props.overBluetooth ? 'Bluetooth' : 'Wi-Fi',
);
</script>

<template>
  <div class="link">
    <AppIcon class="transport" :name="overBluetooth ? 'bluetooth' : 'wifi'" />
    <span
      class="bars"
      role="img"
      :aria-label="`${transportLabel} signal: ${bars} of ${signalBarCount} bars`"
    >
      <i
        v-for="bar in signalBarCount"
        :key="bar"
        :class="{ on: bar <= bars }"
        :style="{ height: `${4 + bar * 3}px` }"
      />
    </span>
    <span v-if="roundTrip" class="round-trip" tabindex="0">
      {{ roundTrip.totalMs }} ms
      <span class="round-trip-detail" aria-hidden="true">
        <span
          >Network RTT <b>{{ roundTrip.networkMs }} ms</b></span
        >
        <span
          >Processing RTT <b>{{ roundTrip.processingMs }} ms</b></span
        >
        <span class="round-trip-total"
          >Total <b>{{ roundTrip.totalMs }} ms</b></span
        >
      </span>
      <span class="sr-only"
        >, network {{ roundTrip.networkMs }} ms, processing
        {{ roundTrip.processingMs }} ms</span
      >
    </span>
    <span v-if="quality" class="quality" tabindex="0">
      {{ quality.label }}
      <span class="quality-detail" aria-hidden="true">{{
        quality.detail
      }}</span>
      <span class="sr-only">, {{ quality.detail }}</span>
    </span>
    <span class="arrows" aria-hidden="true">
      <svg
        :key="rxPulse"
        class="arrow"
        :class="{ flash: rxPulse > 0 }"
        viewBox="0 0 12 12"
      >
        <path d="M6 2v8M3 7l3 3 3-3" />
      </svg>
      <svg
        :key="txPulse"
        class="arrow"
        :class="{ flash: txPulse > 0 }"
        viewBox="0 0 12 12"
      >
        <path d="M6 10V2M3 5l3-3 3 3" />
      </svg>
    </span>
  </div>
</template>

<style scoped>
.link {
  position: relative;
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 4px;
}

.transport {
  flex: none;
  font-size: 14px;
  color: var(--color-text-secondary);
}

.bars {
  display: inline-flex;
  align-items: flex-end;
  gap: 2px;
  height: 10px;
}

.bars i {
  width: 3px;
  border-radius: 1px;
  background: var(--color-text-tertiary);
  opacity: 0.45;
}

.bars i.on {
  background: var(--color-text-secondary);
  opacity: 1;
}

.round-trip {
  flex: none;
  border-radius: 4px;
  color: var(--color-text-secondary);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
  cursor: default;
}

.round-trip:focus-visible {
  outline: 2px solid var(--color-accent);
  outline-offset: 2px;
}

.round-trip-detail {
  position: absolute;
  left: 0;
  bottom: calc(100% + 8px);
  z-index: 10;
  display: none;
  flex-direction: column;
  gap: 4px;
  padding: 8px 10px;
  border: 1px solid var(--color-separator);
  border-radius: var(--radius-control);
  background: var(--color-surface);
  box-shadow: 0 8px 24px var(--color-shadow);
  color: var(--color-text-secondary);
}

.round-trip:hover .round-trip-detail,
.round-trip:focus .round-trip-detail {
  display: flex;
}

.round-trip-detail b {
  color: var(--color-text);
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

.round-trip-total {
  padding-top: 4px;
  border-top: 1px solid var(--color-separator);
}

.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  margin: -1px;
  overflow: hidden;
  clip: rect(0 0 0 0);
  white-space: nowrap;
  border: 0;
  padding: 0;
}

.quality {
  flex: none;
  border-radius: 4px;
  color: var(--color-text-secondary);
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
  cursor: default;
}

.quality:focus-visible {
  outline: 2px solid var(--color-accent);
  outline-offset: 2px;
}

.quality-detail {
  position: absolute;
  left: 0;
  bottom: calc(100% + 8px);
  z-index: 10;
  display: none;
  width: max-content;
  max-width: 180px;
  padding: 8px 10px;
  border: 1px solid var(--color-separator);
  border-radius: var(--radius-control);
  background: var(--color-surface);
  box-shadow: 0 8px 24px var(--color-shadow);
  color: var(--color-text-secondary);
  white-space: normal;
  line-height: 1.35;
}

.quality:hover .quality-detail,
.quality:focus .quality-detail {
  display: block;
}

.arrows {
  display: inline-flex;
  gap: 2px;
}

.arrow {
  width: 11px;
  height: 11px;
  fill: none;
  stroke: var(--color-text-tertiary);
  stroke-width: 1.8;
  stroke-linecap: round;
  stroke-linejoin: round;
}

.arrow.flash {
  animation: flash 320ms var(--ease-standard);
}

@keyframes flash {
  from {
    stroke: var(--color-accent);
  }
  to {
    stroke: var(--color-text-tertiary);
  }
}

@media (prefers-reduced-motion: reduce) {
  .arrow.flash {
    animation: none;
  }
}
</style>
