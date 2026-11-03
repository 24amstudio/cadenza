<script setup lang="ts">
import { useNoticesStore } from '~/stores/notices';

const notices = useNoticesStore();
</script>

<template>
  <div class="toast-region" aria-live="polite">
    <Transition name="toast">
      <p v-if="notices.message" class="toast" role="status">
        {{ notices.message }}
      </p>
    </Transition>
  </div>
</template>

<style scoped>
.toast-region {
  position: fixed;
  left: 50%;
  bottom: calc(var(--player-clearance, 96px) + 12px);
  z-index: 20;
  transform: translateX(-50%);
  pointer-events: none;
}

.toast {
  max-width: min(92vw, 460px);
  margin: 0;
  padding: 10px 16px;
  border-radius: 999px;
  background: var(--color-text);
  color: var(--color-canvas);
  box-shadow: 0 18px 40px -18px var(--color-shadow);
  font-size: 14px;
  font-weight: 560;
  text-align: center;
}

.toast-enter-active,
.toast-leave-active {
  transition:
    opacity 220ms var(--ease-standard),
    transform 220ms var(--ease-standard);
}

.toast-enter-from,
.toast-leave-to {
  opacity: 0;
  transform: translateY(8px);
}
</style>
