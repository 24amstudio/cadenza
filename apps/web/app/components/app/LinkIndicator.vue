<script setup lang="ts">
import { signalBarCount } from '~/lib/host/linkSignal';

// Signal bars for the link to Cadenza Host, with a down arrow that flashes when frames arrive and an up arrow when
// frames leave. Each flash replays because the arrow is re-keyed on every pulse, so no timer runs.
defineProps<{ bars: number; rxPulse: number; txPulse: number }>();
</script>

<template>
  <div class="link">
    <span
      class="bars"
      role="img"
      :aria-label="`Signal: ${bars} of ${signalBarCount} bars`"
    >
      <i
        v-for="bar in signalBarCount"
        :key="bar"
        :class="{ on: bar <= bars }"
        :style="{ height: `${4 + bar * 3}px` }"
      />
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
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 4px;
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
