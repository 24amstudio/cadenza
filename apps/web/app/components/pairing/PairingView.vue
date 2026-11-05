<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import { defaultRemoteName, isValidRemoteName } from '~/lib/host/endpoint';
import { useHostStore } from '~/stores/host';

const host = useHostStore();

const pairing = computed(() => host.phase === 'pairing');
const failed = computed(() => host.phase === 'pairing-failed');
const idle = computed(() => host.phase === 'bluetooth-idle');
const searching = computed(() => host.bluetoothState === 'searching');
const linked = computed(() => host.bluetoothState === 'linked');

const bluetoothPairing = computed(
  () => host.bluetoothSupported && (host.phase === 'unpaired' || failed.value),
);

const busy = computed(() => pairing.value || searching.value);

const name = ref(defaultRemoteName(navigator.userAgent));
const pin = ref('');
const nameError = ref<string | null>(null);
const pinError = ref<string | null>(null);
const nameInput = ref<HTMLInputElement | null>(null);
const pinInput = ref<HTMLInputElement | null>(null);
const findButton = ref<HTMLButtonElement | null>(null);
const failureDialog = ref<HTMLDialogElement | null>(null);

// A Host PIN is one use, so the field keeps only digits and clears after each submission.
watch(pin, (value) => {
  const digits = value.replace(/\D/g, '').slice(0, 4);

  if (digits !== value) pin.value = digits;
});

watch(
  () => host.pairingFailure,
  (message) => {
    const dialog = failureDialog.value;

    if (message === null || dialog === null || dialog.open) return;
    dialog.showModal();
  },
);

const heading = computed(() => {
  if (pairing.value) return 'Pairing with Cadenza Host';

  if (failed.value) return 'Pairing did not finish';

  if (idle.value) return 'Connect to Cadenza Host';

  if (searching.value) return 'Looking for Cadenza Host';

  if (linked.value) return 'Enter the Host PIN';

  return 'Pair this browser';
});

const body = computed(() => {
  if (pairing.value)
    return 'Waiting for Cadenza Host to confirm this browser. This takes a few seconds.';

  if (failed.value && host.bluetoothSupported)
    return 'Find Cadenza Host again to pair this browser.';

  if (failed.value)
    return host.phaseMessage ?? 'The invitation is no longer valid.';

  if (idle.value)
    return 'This browser is still paired. Connect over Bluetooth to control playback.';

  if (searching.value)
    return 'Choose Cadenza Host in the list that opens. Keep Bluetooth on near the Host.';

  if (linked.value)
    return 'Cadenza Host shows a four-digit PIN. It changes every fifteen seconds.';

  if (host.bluetoothSupported)
    return 'On Cadenza Host, choose Pair a Remote to show a PIN. Then find Cadenza Host from this browser.';

  if (window.isSecureContext)
    return 'This browser cannot pair over Bluetooth. Use Chrome or Edge, or open Cadenza Web from the Host’s address and scan the code.';

  return 'Scan the pairing code shown in Cadenza Host with this device’s camera. This page opens and pairs on its own.';
});

function submitPin(): void {
  if (pairing.value) return;
  nameError.value = null;
  pinError.value = null;

  if (!isValidRemoteName(name.value)) {
    nameError.value = 'Use 1 to 80 characters without control characters.';
    nameInput.value?.focus();

    return;
  }

  if (!/^\d{4}$/.test(pin.value)) {
    pinError.value = 'Enter the four-digit PIN shown by Cadenza Host.';
    pinInput.value?.focus();

    return;
  }

  const submitted = pin.value;

  pin.value = '';
  host.pairOverBluetooth(submitted, name.value.trim());
}

async function onFailureDialogClosed(): Promise<void> {
  host.dismissPairingFailure();
  await nextTick();
  (linked.value ? pinInput.value : findButton.value)?.focus();
}
</script>

<template>
  <section class="pairing" aria-labelledby="pairing-title">
    <div class="pairing-card">
      <span class="pairing-mark" :class="{ busy }" aria-hidden="true">
        <span v-if="busy" class="spinner"></span>
        <AppIcon
          v-else
          :name="failed ? 'refresh' : host.bluetoothSupported ? 'host' : 'qr'"
        />
      </span>
      <h1 id="pairing-title">{{ heading }}</h1>
      <p class="pairing-body">{{ body }}</p>

      <form
        v-if="bluetoothPairing"
        class="pair-form"
        novalidate
        @submit.prevent="submitPin"
      >
        <label class="field">
          <span>Name for this browser</span>
          <input
            ref="nameInput"
            v-model="name"
            type="text"
            maxlength="120"
            autocomplete="off"
            :aria-invalid="nameError !== null"
            :aria-describedby="nameError ? 'name-error' : undefined"
          />
        </label>
        <p v-if="nameError" id="name-error" class="field-error">
          {{ nameError }}
        </p>

        <button
          v-if="!linked"
          ref="findButton"
          class="pairing-action"
          type="button"
          :disabled="searching"
          @click="host.findBluetoothHost()"
        >
          Find Cadenza Host
        </button>

        <template v-else>
          <label class="field">
            <span>Host PIN</span>
            <input
              ref="pinInput"
              v-model="pin"
              type="text"
              inputmode="numeric"
              autocomplete="one-time-code"
              maxlength="4"
              :aria-invalid="pinError !== null"
              :aria-describedby="pinError ? 'pin-error' : undefined"
            />
          </label>
          <p v-if="pinError" id="pin-error" class="field-error">
            {{ pinError }}
          </p>
          <button class="pairing-action" type="submit" :disabled="pairing">
            Pair over Bluetooth
          </button>
        </template>
      </form>

      <button
        v-if="idle"
        ref="findButton"
        class="pairing-action"
        type="button"
        :disabled="searching"
        @click="host.findBluetoothHost()"
      >
        Connect over Bluetooth
      </button>

      <p
        v-if="host.phaseMessage && (idle || host.phase === 'unpaired')"
        class="pairing-note"
      >
        {{ host.phaseMessage }}
      </p>

      <ol v-if="!host.bluetoothSupported && !pairing && !failed" class="steps">
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

      <p v-if="failed && !host.bluetoothSupported" class="pairing-note">
        Choose Pair a Remote on Cadenza Host and scan a new code.
      </p>
    </div>

    <dialog
      v-if="host.bluetoothSupported"
      ref="failureDialog"
      class="failure-dialog"
      aria-labelledby="failure-title"
      aria-describedby="failure-message"
      @close="onFailureDialogClosed"
    >
      <h2 id="failure-title">Could not connect over Bluetooth</h2>
      <p id="failure-message" class="failure-message">
        {{ host.pairingFailure }}
      </p>
      <form method="dialog" class="failure-actions">
        <button class="pairing-action" type="submit">Try again</button>
      </form>
    </dialog>
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

.pair-form {
  display: grid;
  gap: 12px;
  width: 100%;
  margin-top: 6px;
  text-align: left;
}

.field {
  display: grid;
  gap: 6px;
  font-size: 14px;
  color: var(--color-text-secondary);
}

.field input {
  height: 40px;
  padding: 0 12px;
  border: 1px solid var(--color-separator);
  border-radius: var(--radius-control);
  background: var(--color-fill);
  color: var(--color-text);
  font-size: 16px;
}

.field input[aria-invalid='true'] {
  border-color: var(--color-danger);
}

.field-error {
  color: var(--color-danger);
  font-size: 13px;
}

.pairing-action {
  height: 44px;
  padding: 0 18px;
  border: 0;
  border-radius: var(--radius-control);
  background: var(--color-accent);
  color: var(--color-on-accent);
  font-size: 15px;
  font-weight: 600;
}

.failure-dialog {
  width: min(calc(100vw - 40px), 380px);
  padding: 28px;
  border: 0;
  border-radius: var(--radius-panel);
  background: var(--color-surface);
  color: var(--color-text);
  box-shadow: 0 30px 60px -30px var(--color-shadow);
}

.failure-dialog::backdrop {
  background: rgb(0 0 0 / 0.4);
}

.failure-dialog h2 {
  font-size: 19px;
  font-weight: 700;
}

.failure-message {
  margin-top: 10px;
  color: var(--color-text-secondary);
  font-size: 15px;
  line-height: 1.45;
}

.failure-actions {
  display: flex;
  justify-content: flex-end;
  margin-top: 22px;
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
