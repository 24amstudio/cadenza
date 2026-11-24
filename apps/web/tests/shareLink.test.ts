import { describe, expect, test } from 'bun:test';
import { sharedSongId } from '../app/lib/shareLink';

describe('sharedSongId', () => {
  test('a song link and an album link with a track name the song', () => {
    expect(sharedSongId('https://music.apple.com/us/song/title/958A4478')).toBe(
      '958A4478',
    );
    expect(
      sharedSongId(
        'Listen https://music.apple.com/us/album/name/1234?i=5678 now',
      ),
    ).toBe('5678');
  });

  test('playlists, albums without a track, other hosts, and plain http name no song', () => {
    expect(
      sharedSongId('https://music.apple.com/us/playlist/mix/pl.u-abc'),
    ).toBeNull();
    expect(
      sharedSongId('https://music.apple.com/us/album/name/1234'),
    ).toBeNull();
    expect(
      sharedSongId('https://music.apple.com.evil.example/us/song/x/1'),
    ).toBeNull();
    expect(sharedSongId('http://music.apple.com/us/song/x/1')).toBeNull();
    expect(sharedSongId('just some words')).toBeNull();
  });
});
