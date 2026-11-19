import { songKey } from '../library/identity';
import type { RequestOutcome, Settle } from '../host/songRequests';
import type { Schedule } from '../host/waiters';
import type { SearchScope, Song, SongSuggestions } from '../protocol/types';

export const suggestDelayMs = 250;

export type SearchStatus = 'idle' | 'loading' | 'done' | 'failed';

export interface SearchState {
  // The text in the field, which can differ from the search that produced the results.
  query: string;
  scope: SearchScope;
  status: SearchStatus;
  submitted: string;
  songs: Song[];
  failure: string | null;
  terms: string[];
}

// The requests the session makes. A cancelled request may still answer; the session ignores that answer.
export interface SearchPort {
  search(
    query: string,
    scope: SearchScope,
    settle: Settle<Song[]>,
  ): string | null;
  suggest(query: string, settle: Settle<SongSuggestions>): string | null;
  cancel(requestId: string): void;
  schedule: Schedule;
}

export function emptySearchState(scope: SearchScope = 'catalog'): SearchState {
  return {
    query: '',
    scope,
    status: 'idle',
    submitted: '',
    songs: [],
    failure: null,
    terms: [],
  };
}

const notConnected = 'Cadenza Host is not connected.';

// Only the newest search may change the results, and only the newest suggestions may change the terms. A slow answer to
// text the person has since changed is dropped, so it never replaces what they are looking at.
export class SearchSession {
  private readonly port: SearchPort;
  private readonly onChange: (state: SearchState) => void;
  private state: SearchState = emptySearchState();
  private searchGeneration = 0;
  private searchRequest: string | null = null;
  private suggestGeneration = 0;
  private suggestRequest: string | null = null;
  private cancelDebounce: (() => void) | null = null;

  constructor(port: SearchPort, onChange: (state: SearchState) => void) {
    this.port = port;
    this.onChange = onChange;
  }

  current(): SearchState {
    return this.state;
  }

  setQuery(query: string): void {
    this.cancelSuggestions();
    this.update({ query, terms: [] });
    const text = query.trim();

    if (text === '') return;
    this.cancelDebounce = this.port.schedule(
      () => this.requestSuggestions(text),
      suggestDelayMs,
    );
  }

  submit(): void {
    const text = this.state.query.trim();

    if (text === '') return;
    this.cancelSuggestions();
    this.run(text);
  }

  chooseTerm(term: string): void {
    this.update({ query: term });
    this.submit();
  }

  setScope(scope: SearchScope): void {
    if (scope === this.state.scope) return;
    this.update({ scope });

    if (this.state.submitted !== '') this.run(this.state.submitted);
  }

  clear(): void {
    this.cancelSuggestions();
    this.cancelSearch();
    this.update(emptySearchState(this.state.scope));
  }

  private run(text: string): void {
    this.cancelSearch();
    const generation = this.searchGeneration;

    this.update({
      status: 'loading',
      submitted: text,
      songs: [],
      failure: null,
      terms: [],
    });

    const request = this.port.search(text, this.state.scope, (outcome) => {
      if (generation !== this.searchGeneration) return;
      this.searchRequest = null;
      this.update(searchChange(outcome));
    });

    if (request === null) {
      this.update({ status: 'failed', failure: notConnected });

      return;
    }

    this.searchRequest = request;
  }

  private requestSuggestions(text: string): void {
    this.cancelDebounce = null;
    this.suggestGeneration += 1;
    const generation = this.suggestGeneration;

    this.suggestRequest = this.port.suggest(text, (outcome) => {
      if (generation !== this.suggestGeneration) return;
      this.suggestRequest = null;

      // Suggestions are optional, so a failed one leaves the list empty rather than showing an error.
      if (outcome.ok) this.update({ terms: uniqueTerms(outcome.value.terms) });
    });
  }

  private cancelSearch(): void {
    this.searchGeneration += 1;

    if (this.searchRequest !== null) this.port.cancel(this.searchRequest);
    this.searchRequest = null;
  }

  private cancelSuggestions(): void {
    this.cancelDebounce?.();
    this.cancelDebounce = null;
    this.suggestGeneration += 1;

    if (this.suggestRequest !== null) this.port.cancel(this.suggestRequest);
    this.suggestRequest = null;
  }

  private update(change: Partial<SearchState>): void {
    this.state = { ...this.state, ...change };
    this.onChange(this.state);
  }
}

function searchChange(outcome: RequestOutcome<Song[]>): Partial<SearchState> {
  return outcome.ok
    ? { status: 'done', songs: distinctSongs(outcome.value) }
    : { status: 'failed', failure: outcome.message };
}

// The list is keyed by song identity, so a song the Host returns twice is shown once.
function distinctSongs(songs: Song[]): Song[] {
  const seen = new Set<string>();
  const unique: Song[] = [];

  for (const song of songs) {
    const key = songKey(song);

    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(song);
  }

  return unique;
}

function uniqueTerms(terms: string[]): string[] {
  return [...new Set(terms)];
}
