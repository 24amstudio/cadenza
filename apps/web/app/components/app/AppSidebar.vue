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

const statusLabel = computed(() => {
  switch (host.phase) {
    case 'connected':
      return 'Connected';
    case 'reconnecting':
      return 'Reconnecting';
    case 'connecting':
    case 'pairing':
      return 'Connecting';
    case 'bluetooth-idle':
      return 'Not connected';
    default:
      return 'Not paired';
  }
});
</script>

<template>
  <aside class="sidebar" aria-label="Cadenza Remote">
    <div class="brand">
      <span class="brand-mark" aria-hidden="true">C</span>
      <span>Cadenza</span>
    </div>

    <nav class="nav" aria-label="Sections">
      <button
        v-for="item in items"
        :key="item.view"
        class="nav-item"
        :class="{ active: ui.view === item.view }"
        type="button"
        :aria-current="ui.view === item.view ? 'page' : undefined"
        @click="ui.showView(item.view)"
      >
        <AppIcon :name="item.icon" />
        <span>{{ item.label }}</span>
      </button>
    </nav>

    <div class="host-card">
      <span class="status" :class="host.phase" aria-hidden="true"></span>
      <div class="host-copy">
        <strong>{{ host.hostName ?? 'Cadenza Host' }}</strong>
        <span>{{ statusLabel }}</span>
      </div>
    </div>
  </aside>
</template>

<style scoped>
.sidebar {
  display: flex;
  flex-direction: column;
  gap: 24px;
  min-height: 0;
  padding: 26px 14px 16px;
  border-right: 1px solid var(--color-separator);
  background: var(--color-sidebar);
  backdrop-filter: var(--chrome-blur);
  -webkit-backdrop-filter: var(--chrome-blur);
}

.brand {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 10px;
  font-family: var(--font-display);
  font-size: 18px;
  font-weight: 700;
  letter-spacing: -0.01em;
}

.brand-mark {
  display: grid;
  place-items: center;
  width: 26px;
  height: 26px;
  border-radius: 8px;
  background: linear-gradient(135deg, #ff5f73, var(--color-accent));
  color: #fff;
  font-size: 14px;
  font-weight: 800;
}

.nav {
  display: grid;
  gap: 2px;
}

.nav-item {
  display: flex;
  align-items: center;
  gap: 12px;
  height: 36px;
  padding: 0 10px;
  border: 0;
  border-radius: var(--radius-control);
  background: transparent;
  color: var(--color-text-secondary);
  font-size: 15px;
  font-weight: 560;
  text-align: left;
  transition:
    background-color 160ms var(--ease-standard),
    color 160ms;
}

.nav-item .icon {
  font-size: 19px;
}

.nav-item:hover {
  background: var(--color-fill);
  color: var(--color-text);
}

.nav-item.active {
  background: var(--color-fill-strong);
  color: var(--color-text);
}

.nav-item.active .icon {
  color: var(--color-accent);
}

.host-card {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-top: auto;
  padding: 12px 10px;
  border-radius: var(--radius-control);
  background: var(--color-fill);
}

.status {
  flex: none;
  width: 8px;
  height: 8px;
  border-radius: 999px;
  background: var(--color-text-tertiary);
}

.status.connected {
  background: #30d158;
  box-shadow: 0 0 0 3px rgb(48 209 88 / 0.18);
}

.status.reconnecting,
.status.connecting,
.status.pairing {
  background: #ffd60a;
}

.host-copy {
  display: grid;
  min-width: 0;
}

.host-copy strong,
.host-copy span {
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}

.host-copy strong {
  font-size: 13px;
  font-weight: 600;
}

.host-copy span {
  color: var(--color-text-secondary);
  font-size: 12px;
}
</style>
