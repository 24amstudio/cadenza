import { expect, test } from 'bun:test';
import {
  browseKey,
  browseTtlMs,
  describeBrowseFailure,
} from '../app/lib/browse';

test('the same page opened by ID and by song are different keys, and a playlists list has its own', () => {
  const byId = browseKey({ kind: 'album', id: '9' });

  const bySong = browseKey({
    kind: 'album',
    song: { source: 'catalog', id: '1' },
  });

  expect(byId).not.toBe(bySong);
  expect(browseKey({ kind: 'artist', id: '9' })).not.toBe(byId);
  expect(browseKey({ kind: 'playlists' })).toBe('playlists');
});

test('playlists are kept for less time than catalog pages', () => {
  expect(browseTtlMs('playlists')).toBeLessThan(browseTtlMs('album'));
  expect(browseTtlMs('playlist')).toBe(browseTtlMs('playlists'));
  expect(browseTtlMs('artist')).toBe(browseTtlMs('album'));
});

test('failures read as plain sentences, and an unknown one keeps the Host message', () => {
  expect(describeBrowseFailure('not_found', '')).toContain('could not find');
  expect(describeBrowseFailure('catalog_unavailable', '')).toContain(
    'Apple Music',
  );
  expect(describeBrowseFailure('odd', 'Disk full.')).toBe('Disk full.');
  expect(describeBrowseFailure('odd', '')).toContain('could not load');
});
