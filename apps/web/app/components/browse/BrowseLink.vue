<script setup lang="ts">
import { computed } from 'vue';
import { identityOf } from '~/lib/library/identity';
import type { Song } from '~/lib/protocol/types';
import { useHostStore } from '~/stores/host';
import { useUiStore } from '~/stores/ui';

// An artist or album name that opens its page. It is plain text when the Host cannot browse or the song has no ID.
const props = defineProps<{ kind: 'artist' | 'album'; song: Song }>();

const host = useHostStore();
const ui = useUiStore();

const label = computed(() =>
  (props.kind === 'artist' ? props.song.artist : props.song.album).trim(),
);

const identity = computed(() => identityOf(props.song));

const linked = computed(
  () => host.supportsBrowse && identity.value !== null && label.value !== '',
);

function open(): void {
  const song = identity.value;

  if (song === null) return;
  ui.openBrowse({ request: { kind: props.kind, song }, title: label.value });
}
</script>

<template>
  <button
    v-if="linked"
    class="browse-link"
    type="button"
    :aria-label="`Open ${kind} ${label}`"
    @click.stop="open"
  >
    {{ label }}
  </button>
  <span v-else>{{ label }}</span>
</template>

<style scoped>
.browse-link {
  display: inline-block;
  max-width: 100%;
  padding: 0;
  overflow: hidden;
  border: 0;
  background: none;
  color: inherit;
  font: inherit;
  text-align: inherit;
  text-overflow: ellipsis;
  white-space: nowrap;
  vertical-align: bottom;
  cursor: pointer;
}

.browse-link:hover {
  text-decoration: underline;
  text-underline-offset: 3px;
}
</style>
