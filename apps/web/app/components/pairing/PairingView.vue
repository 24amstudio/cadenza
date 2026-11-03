<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import { useHostStore } from '~/stores/host';

const host = useHostStore();

const pairing = computed(() => host.phase === 'pairing');
const failed = computed(() => host.phase === 'pairing-failed');

const heading = computed(() => {
  if (pairing.value) return 'Pairing with Cadenza Host';

  if (failed.value) return 'Pairing did not finish';

  return 'Pair this browser';
});

const body = computed(() => {
  if (pairing.value)
    return 'Waiting for Cadenza Host to confirm this browser. This takes a few seconds.';

  if (failed.value)
    return host.phaseMessage ?? 'The invitation is no longer valid.';

  return 'Scan the pairing code shown in Cadenza Host with this device’s camera. This page opens and pairs on its own.';
});
</script>

<template>
  <section class="pairing" aria-labelledby="pairing-title">
    <div class="pairing-card">
      <span class="pairing-mark" :class="{ busy: pairing }" aria-hidden="true">
        <span v-if="pairing" class="spinner"></span>
        <AppIcon v-else :name="failed ? 'refresh' : 'qr'" />
      </span>
      <h1 id="pairing-title">{{ heading }}</h1>
      <p class="pairing-body">{{ body }}</p>

      <ol v-if="!pairing && !failed" class="steps">
        <li>
          <span class="step-number">1</span>
          <span
            >In Cadenza Host settings, turn on Cadenza Web under Network.</span
          >
        </li>
        <li>
          <span class="step-number">2</span>
          <span
            >Choose Pair a Remote, then scan the code with your camera.</span
          >
        </li>
      </ol>

      <p v-if="failed" class="pairing-note">
        Choose Pair a Remote on Cadenza Host and scan a new code.
      </p>
    </div>
  </section>
</template>

<style scoped>
.pairing {
  display: grid;
  place-items: center;
  min-height: 100%;
  padding: 32px 20px;
}

.pairing-card {
  display: grid;
  justify-items: center;
  gap: 14px;
  width: min(100%, 440px);
  padding: 40px 32px 32px;
  border-radius: var(--radius-panel);
  background: var(--color-surface);
  box-shadow: 0 30px 60px -36px var(--color-shadow);
  text-align: center;
}

.pairing-mark {
  display: grid;
  place-items: center;
  width: 84px;
  height: 84px;
  margin-bottom: 6px;
  border-radius: 26px;
  background: linear-gradient(145deg, #ff5f73, var(--color-accent));
  color: #fff;
  font-size: 38px;
  box-shadow: 0 16px 34px -14px var(--color-accent);
}

.pairing-mark.busy {
  background: var(--color-fill-strong);
  box-shadow: none;
}

.spinner {
  width: 26px;
  height: 26px;
  border: 3px solid var(--color-fill-strong);
  border-top-color: var(--color-accent);
  border-radius: 999px;
  animation: spin 900ms linear infinite;
}

@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}

h1 {
  font-family: var(--font-display);
  font-size: 26px;
  font-weight: 700;
  letter-spacing: -0.02em;
}

.pairing-body {
  color: var(--color-text-secondary);
  font-size: 16px;
  line-height: 1.45;
}

.steps {
  display: grid;
  gap: 12px;
  width: 100%;
  margin: 6px 0 0;
  padding: 0;
  list-style: none;
  text-align: left;
}

.steps li {
  display: flex;
  align-items: baseline;
  gap: 12px;
  padding: 12px 14px;
  border-radius: var(--radius-control);
  background: var(--color-fill);
  font-size: 14px;
}

.step-number {
  display: grid;
  flex: none;
  place-items: center;
  width: 22px;
  height: 22px;
  border-radius: 999px;
  background: var(--color-text);
  color: var(--color-canvas);
  font-size: 12px;
  font-weight: 700;
}

.pairing-note {
  color: var(--color-text);
  font-weight: 560;
}
</style>
