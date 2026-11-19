import { describe, expect, test } from 'bun:test';
import type { RequestOutcome, Settle } from '../app/lib/host/songRequests';
import type { Schedule } from '../app/lib/host/waiters';
import type {
  SearchScope,
  Song,
  SongSuggestions,
} from '../app/lib/protocol/types';
import {
  SearchSession,
  emptySearchState,
  suggestDelayMs,
  type SearchPort,
  type SearchState,
} from '../app/lib/search/searchSession';
import { Clock } from './support/hostClient';

const breathe: Song = {
  source: 'catalog',
  id: '1440857781',
  title: 'Breathe Deeper',
  artist: 'Tame Impala',
  album: 'The Slow Rush',
  durationMs: 372_000,
  artworkUrl: null,
};

const borderline: Song = { ...breathe, id: '2', title: 'Borderline' };

interface PendingSearch {
  id: string;
  query: string;
  scope: SearchScope;
  settle: Settle<Song[]>;
}

interface PendingSuggest {
  id: string;
  query: string;
  settle: Settle<SongSuggestions>;
}

// Records what the session asks for and answers only when the test does. Cancelling does not stop a reply, so the
// session's own check against stale answers is what is under test.
class FakePort implements SearchPort {
  readonly clock = new Clock();
  readonly searches: PendingSearch[] = [];
  readonly suggests: PendingSuggest[] = [];
  readonly cancelled: string[] = [];
  linked = true;
  private ids = 0;

  schedule: Schedule = (callback, delayMs) =>
    this.clock.schedule(callback, delayMs);

  search(query: string, scope: SearchScope, settle: Settle<Song[]>) {
    if (!this.linked) return null;
    this.ids += 1;
    const id = `request-${this.ids}`;

    this.searches.push({ id, query, scope, settle });

    return id;
  }

  suggest(query: string, settle: Settle<SongSuggestions>) {
    if (!this.linked) return null;
    this.ids += 1;
    const id = `request-${this.ids}`;

    this.suggests.push({ id, query, settle });

    return id;
  }

  cancel(requestId: string): void {
    this.cancelled.push(requestId);
  }
}

function sessionOver(port: FakePort) {
  const states: SearchState[] = [];
  const session = new SearchSession(port, (state) => states.push(state));

  return {
    session,
    latest: () => states.at(-1) ?? emptySearchState(),
  };
}

function ok(songs: Song[]): RequestOutcome<Song[]> {
  return { ok: true, value: songs };
}

describe('search session', () => {
  test('a slow answer to an older search never replaces the newer results', () => {
    const port = new FakePort();
    const { session, latest } = sessionOver(port);

    session.setQuery('Breathe');
    session.submit();
    session.setQuery('Borderline');
    session.submit();

    const [older, newer] = port.searches;

    newer?.settle(ok([borderline]));
    older?.settle(ok([breathe]));

    expect(latest().submitted).toBe('Borderline');
    expect(latest().songs).toEqual([borderline]);
    expect(latest().status).toBe('done');
    // No suggestion was sent, so the first search is request-1.
    expect(port.cancelled).toEqual(['request-1']);
  });

  test('a song the Host returns twice is listed once', () => {
    const port = new FakePort();
    const { session, latest } = sessionOver(port);

    session.setQuery('Tame Impala');
    session.submit();
    port.searches[0]?.settle(ok([breathe, breathe, borderline]));

    expect(latest().songs).toEqual([breathe, borderline]);
  });

  test('a search with nothing to search for sends nothing', () => {
    const port = new FakePort();
    const { session, latest } = sessionOver(port);

    session.setQuery('   ');
    session.submit();

    expect(port.searches).toEqual([]);
    expect(latest().status).toBe('idle');
  });

  test('a search the Host cannot take fails with a clear message', () => {
    const port = new FakePort();
    const { session, latest } = sessionOver(port);

    port.linked = false;
    session.setQuery('Breathe');
    session.submit();

    expect(latest().status).toBe('failed');
    expect(latest().failure).toBe('Cadenza Host is not connected.');
  });

  test('changing the scope searches the submitted text again in the new scope', () => {
    const port = new FakePort();
    const { session } = sessionOver(port);

    session.setQuery('Breathe');
    session.submit();
    session.setScope('library');

    expect(port.searches.map((search) => search.scope)).toEqual([
      'catalog',
      'library',
    ]);
    expect(port.searches[1]?.query).toBe('Breathe');
  });

  test('suggestions wait for the pause in typing, then keep only the newest text', () => {
    const port = new FakePort();
    const { session, latest } = sessionOver(port);

    session.setQuery('b');
    port.clock.advance(suggestDelayMs - 50);
    session.setQuery('ba');
    port.clock.advance(suggestDelayMs - 50);
    expect(port.suggests).toEqual([]);

    port.clock.advance(50);
    expect(port.suggests.map((suggest) => suggest.query)).toEqual(['ba']);

    port.suggests[0]?.settle({
      ok: true,
      value: { terms: ['Breathe', 'Breathe', 'Borderline'], songs: [] },
    });
    expect(latest().terms).toEqual(['Breathe', 'Borderline']);
  });

  test('a suggestion answer for text that has changed is ignored', () => {
    const port = new FakePort();
    const { session, latest } = sessionOver(port);

    session.setQuery('b');
    port.clock.advance(suggestDelayMs);
    session.setQuery('bo');
    port.suggests[0]?.settle({
      ok: true,
      value: { terms: ['Borderline'], songs: [] },
    });

    expect(latest().terms).toEqual([]);
  });

  test('choosing a suggestion searches for it and clears the suggestions', () => {
    const port = new FakePort();
    const { session, latest } = sessionOver(port);

    session.setQuery('Bord');
    port.clock.advance(suggestDelayMs);
    port.suggests[0]?.settle({
      ok: true,
      value: { terms: ['Borderline'], songs: [] },
    });
    session.chooseTerm('Borderline');

    expect(port.searches.at(-1)?.query).toBe('Borderline');
    expect(latest().query).toBe('Borderline');
    expect(latest().terms).toEqual([]);
  });

  test('clearing the field empties the query, the results and the suggestions', () => {
    const port = new FakePort();
    const { session, latest } = sessionOver(port);

    session.setQuery('Breathe');
    session.submit();
    port.searches[0]?.settle(ok([breathe]));
    session.clear();

    expect(latest()).toEqual(emptySearchState());
  });
});
