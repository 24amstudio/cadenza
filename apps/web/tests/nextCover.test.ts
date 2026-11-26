import { describe, expect, test } from 'bun:test';
import { prefetchNextCover } from '../app/lib/host/nextCover';

function recorder() {
  const fetched: string[] = [];

  return {
    artwork: { prefetch: (url: string) => void fetched.push(url) },
    albums: { shown: (url: string) => `shown:${url}` },
    fetched,
  };
}

describe('prefetchNextCover', () => {
  test('the next cover starts early unless the Host is constrained or in survival', () => {
    const cover = recorder();

    prefetchNextCover(
      cover.artwork,
      cover.albums,
      'https://is1-ssl.mzstatic.com/a.jpg',
      'balanced',
    );
    prefetchNextCover(
      cover.artwork,
      cover.albums,
      'https://is1-ssl.mzstatic.com/b.jpg',
      'constrained',
    );
    prefetchNextCover(
      cover.artwork,
      cover.albums,
      'https://is1-ssl.mzstatic.com/c.jpg',
      'survival',
    );

    expect(cover.fetched).toEqual(['shown:https://is1-ssl.mzstatic.com/a.jpg']);
  });

  test('a song without a cover, or an unknown budget, starts nothing it cannot show', () => {
    const cover = recorder();

    prefetchNextCover(cover.artwork, cover.albums, null, 'unrestricted');
    prefetchNextCover(cover.artwork, cover.albums, undefined, null);

    expect(cover.fetched).toEqual([]);
  });
});
