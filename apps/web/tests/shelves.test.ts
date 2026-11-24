import { describe, expect, test } from 'bun:test';
import type { RecommendationShelfItem } from '../app/lib/protocol/types';
import { shelfReasons, splitShelves } from '../app/lib/shelves';

function item(id: string, evidence: string[]): RecommendationShelfItem {
  return {
    source: 'catalog',
    id,
    title: `Song ${id}`,
    artist: 'Artist',
    evidence,
  };
}

describe('recommendation shelves', () => {
  test('suggestions every Remote shares are Room Blend, and the rest are For You', () => {
    const shelves = splitShelves([
      item('1', ['more_from_artist']),
      item('2', ['room_blend', 'more_from_artist']),
    ]);

    expect(shelves.roomBlend.map((entry) => entry.id)).toEqual(['2']);
    expect(shelves.forYou.map((entry) => entry.id)).toEqual(['1']);
  });

  test('only reasons the Remote can explain are shown', () => {
    const reasons = shelfReasons(
      item('1', [
        'more_from_artist',
        'recent listening',
        'already in the Host queue',
      ]),
    );

    expect(reasons).toEqual(['More from this artist']);
  });
});
