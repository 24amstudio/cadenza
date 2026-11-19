import type { Song } from '../protocol/types';
import { songKey } from './identity';
import type { KeyValueStore } from './keyValue';
import { readList, songFromStorage } from './persistence';

// The version is in the key, so a later shape can be read without guessing at this one.
export const favoritesStorageKey = 'cadenza.web.favorites.v1';

// Favorites, newest first. A song is a favorite by its identity. The metadata is kept only to draw its row.
export class Favorites {
  private readonly store: KeyValueStore;
  private songs: Song[];

  constructor(store: KeyValueStore) {
    this.store = store;
    this.songs = readList(store.read(favoritesStorageKey), songFromStorage);
  }

  list(): Song[] {
    return this.songs;
  }

  has(song: Song): boolean {
    const key = songKey(song);

    return this.songs.some((item) => songKey(item) === key);
  }

  // Returns whether the song is a favorite afterwards.
  toggle(song: Song): boolean {
    const saved = this.has(song);
    const key = songKey(song);

    this.songs = saved
      ? this.songs.filter((item) => songKey(item) !== key)
      : [song, ...this.songs];
    this.store.write(favoritesStorageKey, JSON.stringify(this.songs));

    return !saved;
  }
}
