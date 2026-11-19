import {
  counterField,
  objectField,
  stringField,
  type JsonObject,
} from '../protocol/json';
import type { Song } from '../protocol/types';
import type { KeyValueStore } from './keyValue';
import { readList, songFromStorage } from './persistence';

export const historyStorageKey = 'cadenza.web.history.v1';
export const historyLimit = 200;

export type HistoryKind = 'played' | 'requested';

export interface HistoryEntry {
  id: string;
  kind: HistoryKind;
  // Milliseconds since the epoch, from this browser's clock.
  at: number;
  // The Host's occurrence of a play. A request has none until its song plays.
  occurrenceId: string | null;
  song: Song;
}

// What this browser played or requested, newest first. The oldest entries fall off once the list is full.
export class History {
  private readonly store: KeyValueStore;
  private readonly newId: () => string;
  private entries: HistoryEntry[];

  constructor(store: KeyValueStore, newId: () => string) {
    this.store = store;
    this.newId = newId;
    this.entries = readList(store.read(historyStorageKey), decodeEntry).slice(
      0,
      historyLimit,
    );
  }

  list(): HistoryEntry[] {
    return this.entries;
  }

  // Returns false when this occurrence is already recorded, so one play is one entry.
  recordPlayed(song: Song, occurrenceId: string, at: number): boolean {
    if (this.entries.some((entry) => entry.occurrenceId === occurrenceId))
      return false;

    this.add('played', song, occurrenceId, at);

    return true;
  }

  recordRequested(song: Song, at: number): void {
    this.add('requested', song, null, at);
  }

  clear(): void {
    this.entries = [];
    this.save();
  }

  private add(
    kind: HistoryKind,
    song: Song,
    occurrenceId: string | null,
    at: number,
  ): void {
    const entry: HistoryEntry = {
      id: this.newId(),
      kind,
      at,
      occurrenceId,
      song,
    };

    this.entries = [entry, ...this.entries].slice(0, historyLimit);
    this.save();
  }

  private save(): void {
    this.store.write(historyStorageKey, JSON.stringify(this.entries));
  }
}

function decodeEntry(object: JsonObject): HistoryEntry | null {
  const id = stringField(object, 'id');
  const kind = stringField(object, 'kind');
  const at = counterField(object, 'at');
  const song = objectField(object, 'song');
  const decodedSong = song === null ? null : songFromStorage(song);

  if (
    id === null ||
    !isHistoryKind(kind) ||
    at === null ||
    decodedSong === null
  )
    return null;

  return {
    id,
    kind,
    at,
    occurrenceId: stringField(object, 'occurrenceId'),
    song: decodedSong,
  };
}

function isHistoryKind(value: string | null): value is HistoryKind {
  return value === 'played' || value === 'requested';
}
