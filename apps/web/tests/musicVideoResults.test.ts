import { describe, expect, test } from 'bun:test';
import { decodeHostMessage } from '../app/lib/protocol/decode';

describe('music video search results', () => {
  test('a music video keeps its media type and a song is decoded as before', () => {
    const text = JSON.stringify({
      version: 1,
      type: 'search.result',
      request_id: '3f1c2a2e-7b6d-4c1e-9a1f-2d3e4f5a6b7c',
      songs: [
        {
          source: 'catalog',
          id: '1440857781',
          title: 'Breathe Deeper',
          artist: 'Tame Impala',
          album: 'The Slow Rush',
          media_type: 'musicVideo',
        },
        {
          source: 'catalog',
          id: '1',
          title: 'Song',
          artist: 'Artist',
          album: '',
        },
      ],
    });

    expect(decodeHostMessage(text)).toMatchObject({
      type: 'search.result',
      songs: [
        { id: '1440857781', mediaType: 'musicVideo' },
        { id: '1', title: 'Song' },
      ],
    });
  });
});
