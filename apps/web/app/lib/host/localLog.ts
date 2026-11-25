import { encodeLogReport } from '../protocol/encode';
import { hostUnderPressure } from './hostBudget';
import {
  counterField,
  isJsonArray,
  isJsonObject,
  parseJson,
  stringField,
  type JsonObject,
} from '../protocol/json';

// The Remote's own log, kept in this browser until the Host has taken each entry. A dropped link loses nothing: entries
// leave the store only after they were handed to the socket, and the oldest fall off once the limit is reached.
export type LocalLogLevel = 'debug' | 'info' | 'warning' | 'error';

export interface LocalLogEntry {
  id: number;
  level: LocalLogLevel;
  action: string;
  message: string;
}

// Only the two methods used here, so a test can supply storage without faking the whole interface.
export type LocalLogStorage = Pick<Storage, 'getItem' | 'setItem'>;

export const localLogStorageKey = 'cadenza.web.logs.v1';
export const localLogLimit = 200;

// The Host accepts at most this many entries in one log.report frame.
export const localLogBatchLimit = 100;

const actionLimit = 120;
const messageLimit = 2_000;

export class LocalLog {
  private readonly storage: () => LocalLogStorage | null;
  private entries: LocalLogEntry[];
  private nextId: number;

  constructor(storage: () => LocalLogStorage | null) {
    this.storage = storage;
    this.entries = readEntries(readStored(storage));
    this.nextId =
      this.entries.reduce((highest, entry) => Math.max(highest, entry.id), 0) +
      1;
  }

  record(level: LocalLogLevel, action: string, message: string): void {
    const entry: LocalLogEntry = {
      id: this.nextId,
      level,
      action: clip(action, actionLimit),
      message: clip(message, messageLimit),
    };

    this.nextId += 1;
    this.entries = [...this.entries, entry].slice(-localLogLimit);
    this.save();
  }

  pending(): LocalLogEntry[] {
    return this.entries.slice(0, localLogBatchLimit);
  }

  forget(ids: number[]): void {
    const gone = new Set(ids);
    const kept = this.entries.filter((entry) => !gone.has(entry.id));

    if (kept.length === this.entries.length) return;
    this.entries = kept;
    this.save();
  }

  private save(): void {
    try {
      this.storage()?.setItem(localLogStorageKey, JSON.stringify(this.entries));
    } catch {
      // Full or blocked. The entries stay in memory for this visit.
    }
  }
}

// Sends the held entries through `send`, and removes them only once it returned, so a send that throws keeps them.
// Under thermal pressure nothing is sent, and the entries wait for the Host's budget to recover.
export function flushLocalLog(
  send: (text: string) => void,
  budget: string | null | undefined,
): void {
  if (hostUnderPressure(budget)) return;

  const log = sharedLocalLog();
  const batch = log.pending();

  if (batch.length === 0) return;

  send(encodeLogReport(batch));
  log.forget(batch.map((entry) => entry.id));
}

let shared: LocalLog | null = null;

export function sharedLocalLog(): LocalLog {
  shared ??= new LocalLog(browserStorage);

  return shared;
}

// Outside a browser, or when storage is blocked, the log lives in memory for this visit.
function browserStorage(): LocalLogStorage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

function readStored(storage: () => LocalLogStorage | null): string | null {
  try {
    return storage()?.getItem(localLogStorageKey) ?? null;
  } catch {
    return null;
  }
}

// A stored entry that does not decode is dropped, so one damaged item never hides the rest of the log.
function readEntries(text: string | null): LocalLogEntry[] {
  if (text === null) return [];

  const value = parseJson(text);

  if (value === null || !isJsonArray(value)) return [];

  return value
    .flatMap((item) => {
      if (!isJsonObject(item)) return [];

      const entry = decodeEntry(item);

      return entry === null ? [] : [entry];
    })
    .slice(-localLogLimit);
}

function decodeEntry(object: JsonObject): LocalLogEntry | null {
  const id = counterField(object, 'id');
  const level = stringField(object, 'level');
  const action = stringField(object, 'action');
  const message = stringField(object, 'message');

  if (
    id === null ||
    id < 1 ||
    !isLevel(level) ||
    action === null ||
    action.length === 0 ||
    action.length > actionLimit ||
    message === null ||
    message.length === 0 ||
    message.length > messageLimit
  ) {
    return null;
  }

  return { id, level, action, message };
}

function isLevel(value: string | null): value is LocalLogLevel {
  return (
    value === 'debug' ||
    value === 'info' ||
    value === 'warning' ||
    value === 'error'
  );
}

function clip(text: string, limit: number): string {
  const trimmed = text.trim() === '' ? '(empty)' : text;

  return trimmed.length <= limit ? trimmed : trimmed.slice(0, limit);
}
