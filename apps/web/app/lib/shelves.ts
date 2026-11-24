import type { RecommendationShelfItem } from '~/lib/protocol/types';

export interface Shelves {
  forYou: RecommendationShelfItem[];
  roomBlend: RecommendationShelfItem[];
}

const roomBlendReason = 'room_blend';

const reasonLabels = new Map<string, string>([
  ['more_from_artist', 'More from this artist'],
  ['rediscovery', 'Rediscovery'],
  ['matches_time_of_day', 'Fits this time of day'],
]);

/** Room Blend holds the suggestions every connected Remote shares. The rest are For You. */
export function splitShelves(items: RecommendationShelfItem[]): Shelves {
  return {
    roomBlend: items.filter((item) => item.evidence.includes(roomBlendReason)),
    forYou: items.filter((item) => !item.evidence.includes(roomBlendReason)),
  };
}

/** The reasons a Remote can explain. Other evidence, such as queue status, is left out. */
export function shelfReasons(item: RecommendationShelfItem): string[] {
  return item.evidence.flatMap((tag) => {
    const label = reasonLabels.get(tag);

    return label ? [label] : [];
  });
}
