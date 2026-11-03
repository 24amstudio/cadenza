<script setup lang="ts">
import AppIcon, { type IconName } from '~/components/common/AppIcon.vue';

defineProps<{ icon: IconName; title: string; body: string }>();
</script>

<template>
  <section class="empty-state">
    <span class="empty-icon"><AppIcon :name="icon" /></span>
    <h2>{{ title }}</h2>
    <p>{{ body }}</p>
    <slot />
  </section>
</template>

<style scoped>
.empty-state {
  display: grid;
  justify-items: center;
  align-content: center;
  gap: 10px;
  min-height: 50vh;
  padding: 40px 24px;
  text-align: center;
}

.empty-icon {
  display: grid;
  place-items: center;
  width: 72px;
  height: 72px;
  margin-bottom: 8px;
  border-radius: 22px;
  background: var(--color-fill);
  color: var(--color-text-secondary);
  font-size: 30px;
}

h2 {
  font-family: var(--font-display);
  font-size: 22px;
  font-weight: 650;
  letter-spacing: -0.01em;
}

p {
  max-width: 380px;
  color: var(--color-text-secondary);
}
</style>
