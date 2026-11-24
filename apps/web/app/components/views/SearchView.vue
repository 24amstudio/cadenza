<script setup lang="ts">
import { computed, onMounted, useTemplateRef } from 'vue';
import AppIcon from '~/components/common/AppIcon.vue';
import EmptyState from '~/components/common/EmptyState.vue';
import RecommendationShelves from '~/components/browse/RecommendationShelves.vue';
import SongRow from '~/components/library/SongRow.vue';
import { songKey } from '~/lib/library/identity';
import type { SearchScope } from '~/lib/protocol/types';
import { useSearchStore } from '~/stores/search';

const search = useSearchStore();
const field = useTemplateRef<HTMLInputElement>('field');

const scopes: { value: SearchScope; label: string }[] = [
  { value: 'catalog', label: 'Apple Music' },
  { value: 'library', label: 'Library' },
];

const scopeLabel = computed(
  () => scopes.find((scope) => scope.value === search.state.scope)?.label ?? '',
);

const supported = computed(() => search.scopeSupported(search.state.scope));

const suggestionsShown = computed(
  () => search.state.terms.length > 0 && search.state.query.trim() !== '',
);

onMounted(() => field.value?.focus());

function onInput(event: Event): void {
  if (event.target instanceof HTMLInputElement) {
    search.setQuery(event.target.value);
  }
}

// Escape and the clear button both empty the field, and the field keeps focus for the next search.
function clear(): void {
  search.clear();
  field.value?.focus();
}

function submit(): void {
  if (supported.value) search.submit();
}
</script>

<template>
  <section class="search-view" aria-labelledby="search-title">
    <header class="page-header">
      <h1 id="search-title">Search</h1>
    </header>

    <form class="search-form" role="search" @submit.prevent="submit">
      <label class="visually-hidden" for="song-search">
        Song, artist, or album
      </label>
      <div class="field">
        <AppIcon name="search" class="field-icon" />
        <input
          id="song-search"
          ref="field"
          type="search"
          enterkeyhint="search"
          autocomplete="off"
          autocapitalize="off"
          spellcheck="false"
          placeholder="Song, artist, or album"
          :value="search.state.query"
          @input="onInput"
          @keydown.escape="clear"
        />
        <button
          v-if="search.state.query !== ''"
          class="clear-button"
          type="button"
          aria-label="Clear search"
          @click="clear"
        >
          <AppIcon name="close" />
        </button>
      </div>

      <div class="scopes" role="group" aria-label="Where to search">
        <button
          v-for="scope in scopes"
          :key="scope.value"
          class="scope"
          type="button"
          :aria-pressed="search.state.scope === scope.value"
          @click="search.setScope(scope.value)"
        >
          {{ scope.label }}
        </button>
      </div>
    </form>

    <RecommendationShelves
      v-if="search.state.query.trim() === ''"
      class="shelves-section"
    />

    <ul v-if="suggestionsShown" class="suggestions" aria-label="Suggestions">
      <li v-for="term in search.state.terms" :key="term">
        <button
          class="suggestion"
          type="button"
          @click="search.chooseTerm(term)"
        >
          <AppIcon name="search" />
          <span>{{ term }}</span>
        </button>
      </li>
    </ul>

    <div class="results">
      <EmptyState
        v-if="!supported"
        icon="search"
        :title="`${scopeLabel} search is unavailable`"
        body="This Cadenza Host does not offer this search. Switch to the other source, or update Cadenza Host."
      />
      <EmptyState
        v-else-if="search.state.status === 'idle'"
        icon="search"
        title="Search for a song"
        body="Find a song on Apple Music or in Music's library on Cadenza Host, then play it next or add it to Up Next."
      />
      <EmptyState
        v-else-if="search.state.status === 'loading'"
        icon="search"
        title="Searching Cadenza Host…"
        body="Results appear here as soon as Cadenza Host answers."
      />
      <EmptyState
        v-else-if="search.state.status === 'failed'"
        icon="search"
        title="Search did not finish"
        :body="search.state.failure ?? ''"
      >
        <button class="text-button" type="button" @click="search.submit()">
          Try again
        </button>
      </EmptyState>
      <EmptyState
        v-else-if="search.state.songs.length === 0"
        icon="search"
        title="No songs match"
        body="Check the spelling, or try the other source."
      />
      <section v-else class="result-list" aria-labelledby="results-title">
        <h2 id="results-title">Results for “{{ search.state.submitted }}”</h2>
        <ul class="song-list">
          <SongRow
            v-for="song in search.state.songs"
            :key="songKey(song)"
            :song="song"
          />
        </ul>
      </section>
    </div>
  </section>
</template>

<style scoped>
.search-view {
  display: grid;
  gap: 16px;
  max-width: 760px;
  margin: 0 auto;
}

.page-header {
  padding: 0 12px;
}

h1 {
  font-family: var(--font-display);
  font-size: 32px;
  font-weight: 750;
  letter-spacing: -0.02em;
}

.search-form {
  display: grid;
  gap: 12px;
}

.field {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 46px;
  padding: 0 8px 0 14px;
  border-radius: 12px;
  background: var(--color-fill);
  color: var(--color-text-tertiary);
  transition: box-shadow 160ms var(--ease-standard);
}

.field:focus-within {
  box-shadow: 0 0 0 2px var(--color-accent);
}

.field-icon {
  font-size: 19px;
}

.field input {
  flex: 1;
  min-width: 0;
  height: 100%;
  border: 0;
  background: transparent;
  color: var(--color-text);
  font-size: 17px;
  outline: none;
}

.field input::placeholder {
  color: var(--color-text-tertiary);
}

/* The field draws its own clear button, so the browser's is hidden. */
.field input::-webkit-search-cancel-button {
  -webkit-appearance: none;
  appearance: none;
}

.clear-button {
  display: grid;
  place-items: center;
  flex: none;
  width: 30px;
  height: 30px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill-strong);
  color: var(--color-text-secondary);
  font-size: 14px;
}

.scopes {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.scope {
  height: 34px;
  padding: 0 14px;
  border: 0;
  border-radius: 999px;
  background: var(--color-fill);
  color: var(--color-text-secondary);
  font-size: 14px;
  font-weight: 560;
}

.scope[aria-pressed='true'] {
  background: var(--color-fill-strong);
  color: var(--color-text);
}

.suggestions {
  display: grid;
  gap: 2px;
  margin: 0;
  padding: 6px;
  border-radius: var(--radius-control);
  background: var(--color-fill);
  list-style: none;
}

.suggestion {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  min-height: 40px;
  padding: 0 10px;
  border: 0;
  border-radius: 7px;
  background: transparent;
  color: var(--color-text);
  font-size: 15px;
  text-align: left;
}

.suggestion:hover {
  background: var(--color-fill-strong);
}

.suggestion .icon {
  color: var(--color-text-tertiary);
  font-size: 16px;
}

.suggestion span {
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}

.result-list {
  display: grid;
  gap: 8px;
}

.result-list h2 {
  padding: 0 12px;
  color: var(--color-text-secondary);
  font-size: 13px;
  font-weight: 650;
  overflow: hidden;
  white-space: nowrap;
  text-overflow: ellipsis;
}
</style>
