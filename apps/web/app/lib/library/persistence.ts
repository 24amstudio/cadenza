import {
  counterField,
  isJsonArray,
  isJsonObject,
  parseJson,
  stringField,
  type JsonObject,
} from '../protocol/json';
import type { Song } from '../protocol/types';

// Reads a stored list. An entry that does not decode is dropped alone, so one damaged entry never empties the list.
export function readList<Item>(
  text: string | null,
  decode: (object: JsonObject) => Item | null,
): Item[] {
  const value = text === null ? null : parseJson(text);

  if (!isJsonArray(value)) return [];
  const items: Item[] = [];

  for (const entry of value) {
    if (!isJsonObject(entry)) continue;
    const item = decode(entry);

    if (item !== null) items.push(item);
  }

  return items;
}

// Stored songs use the same camel-case fields as Song, which JSON.stringify writes directly.
export function songFromStorage(object: JsonObject): Song | null {
  const source = stringField(object, 'source');
  const id = stringField(object, 'id');
  const title = stringField(object, 'title');
  const artist = stringField(object, 'artist');
  const album = stringField(object, 'album');

  if (
    !isSongSource(source) ||
    id === null ||
    title === null ||
    artist === null ||
    album === null
  )
    return null;

  return {
    source,
    id,
    title,
    artist,
    album,
    durationMs: counterField(object, 'durationMs'),
    artworkUrl: stringField(object, 'artworkUrl'),
  };
}

function isSongSource(value: string | null): value is Song['source'] {
  return value === 'catalog' || value === 'library' || value === 'unknown';
}
