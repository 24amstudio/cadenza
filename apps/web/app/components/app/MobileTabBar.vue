<script setup lang="ts">
import { computed } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import { navigationItems } from '~/lib/navigation';
import { useHostStore } from '~/stores/host';
import { useUiStore } from '~/stores/ui';

const host = useHostStore();
const ui = useUiStore();

const items = computed(() =>
  navigationItems(host.current !== null && host.lyricsStatus > 0),
);
</script>

<template>
  <nav class="tab-bar" aria-label="Sections">
    <button
      v-for="item in items"
      :key="item.view"
      class="tab"
      :class="{ active: ui.view === item.view }"
      type="button"
      :aria-current="ui.view === item.view ? 'page' : undefined"
      @click="ui.showView(item.view)"
    >
      <AppIcon :name="item.icon" />
      <span>{{ item.label }}</span>
    </button>
  </nav>
</template>

<style scoped>
.tab-bar {
  display: grid;
  grid-auto-flow: column;
  grid-auto-columns: 1fr;
  padding: 6px 8px calc(6px + env(safe-area-inset-bottom));
  border-top: 1px solid var(--color-separator);
  background: var(--color-chrome);
  backdrop-filter: var(--chrome-blur);
  -webkit-backdrop-filter: var(--chrome-blur);
}

.tab {
  display: grid;
  justify-items: center;
  gap: 3px;
  padding: 4px 0;
  border: 0;
  background: transparent;
  color: var(--color-text-tertiary);
  font-size: 11px;
  font-weight: 560;
}

.tab .icon {
  font-size: 22px;
}

.tab.active {
  color: var(--color-accent);
}
</style>
