import { describe, expect, test } from 'bun:test';
import { decodeHostMessage } from '../app/lib/protocol/decode';
import { encodeRecommendationShelf } from '../app/lib/protocol/encode';

describe('recommendation shelf messages', () => {
  test('a shelf reply decodes to its items and keeps the request id it answers', () => {
    const message = decodeHostMessage(
      JSON.stringify({
        type: 'recommendation.result',
        request_id: 'request-1',
        recommendation_shelf: {
          items: [
            {
              track: { source: 'catalog', id: '42', artist_id: 'Artist' },
              title: 'Song',
              artist: 'Artist',
              evidence: ['room_blend'],
            },
            {
              track: { source: 'unknown', id: '7' },
              title: 'Skipped',
              artist: 'X',
              evidence: [],
            },
          ],
        },
      }),
    );

    expect(message).toEqual({
      type: 'recommendation.shelf',
      requestId: 'request-1',
      items: [
        {
          source: 'catalog',
          id: '42',
          title: 'Song',
          artist: 'Artist',
          evidence: ['room_blend'],
        },
      ],
    });
  });

  test('a shelf the Host cannot give comes back as an error for that request', () => {
    const message = decodeHostMessage(
      JSON.stringify({
        type: 'recommendation.result',
        request_id: 'request-2',
        error_code: 'planning_paused',
      }),
    );

    expect(message).toMatchObject({
      type: 'error',
      requestId: 'request-2',
      errorCode: 'planning_paused',
    });
  });

  test('the shelf request asks for a list and sends no queue action', () => {
    const frame = JSON.parse(encodeRecommendationShelf('request-3'));

    expect(frame.type).toBe('recommendation.query');
    expect(frame.request_id).toBe('request-3');
    expect(frame.recommendation_query.shelf).toBe(true);
    expect(frame.action).toBeUndefined();
  });
});
