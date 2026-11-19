import type { HostMessage } from '../protocol/decode';
import {
  encodeBrowseGet,
  encodeOperationCancel,
  encodeSearch,
  encodeSearchSuggest,
  encodeSongPrepare,
  type SongDetails,
} from '../protocol/encode';
import type {
  BrowsePage,
  BrowseRequest,
  SearchScope,
  Song,
  SongIdentity,
  SongSuggestions,
} from '../protocol/types';
import type { Schedule } from './waiters';

export type RequestOutcome<Value> =
  | { ok: true; value: Value }
  | { ok: false; errorCode: string; message: string };

export type Settle<Value> = (outcome: RequestOutcome<Value>) => void;

export interface SongRequestsOptions {
  // Sends one frame over the live link. False means the link is not ready and nothing was sent.
  send: (text: string) => boolean;
  newId: () => string;
  schedule: Schedule;
}

interface Pending {
  // Takes the reply or error for this request. False when the message does not answer it.
  answer: (message: HostMessage) => boolean;
  abandon: () => void;
  // Stops waiting without settling, so a reply that still arrives is ignored.
  drop: () => void;
}

const queryLimit = 200;
const searchTimeoutMs = 20_000;
const prepareTimeoutMs = 20_000;
const suggestTimeoutMs = 6_000;
const browseTimeoutMs = 25_000;

// Each request is sent once and settles once: with the Host's reply, with its error, or with a failure when the link
// closes or the deadline passes. Nothing here is sent again. A lost request is reported, and the person asks again.
export class SongRequests {
  private readonly options: SongRequestsOptions;
  private readonly pending = new Map<string, Pending>();

  constructor(options: SongRequestsOptions) {
    this.options = options;
  }

  // Returns the request ID, or null when nothing was sent. The settle callback is not called in that case.
  search(
    query: string,
    scope: SearchScope,
    settle: Settle<Song[]>,
  ): string | null {
    return this.start(
      searchTimeoutMs,
      (requestId) => encodeSearch(requestId, query.slice(0, queryLimit), scope),
      (message) =>
        message.type === 'search.result'
          ? succeed(message.songs)
          : hostFailure(message),
      settle,
    );
  }

  suggest(query: string, settle: Settle<SongSuggestions>): string | null {
    return this.start(
      suggestTimeoutMs,
      (requestId) => encodeSearchSuggest(requestId, query.slice(0, queryLimit)),
      (message) =>
        message.type === 'search.suggestions'
          ? succeed(message.suggestions)
          : hostFailure(message),
      settle,
    );
  }

  prepare(
    song: SongIdentity,
    settle: Settle<null>,
    details?: SongDetails,
  ): string | null {
    return this.start(
      prepareTimeoutMs,
      (requestId) => encodeSongPrepare(requestId, song, details),
      (message) =>
        message.type === 'song.ready' ? succeed(null) : hostFailure(message),
      settle,
    );
  }

  browse(request: BrowseRequest, settle: Settle<BrowsePage>): string | null {
    return this.start(
      browseTimeoutMs,
      (requestId) => encodeBrowseGet(requestId, request),
      (message) =>
        message.type === 'browse.result'
          ? succeed(message.browse)
          : hostFailure(message),
      settle,
    );
  }

  cancel(requestId: string): void {
    this.pending.get(requestId)?.drop();
  }

  // Stops waiting and tells the Host to stop working on it, so a page left behind costs the Host nothing more.
  abort(requestId: string): void {
    const entry = this.pending.get(requestId);

    if (entry === undefined) return;
    entry.drop();
    this.options.send(encodeOperationCancel(requestId));
  }

  // True when the message answered one of these requests, so the client does not handle it again.
  receive(message: HostMessage): boolean {
    const requestId = answerIdOf(message);
    const entry = requestId === null ? undefined : this.pending.get(requestId);

    return entry !== undefined && entry.answer(message);
  }

  // The link closed. Every open request fails now and is never sent again.
  abandon(): void {
    for (const entry of [...this.pending.values()]) entry.abandon();
  }

  private start<Value>(
    timeoutMs: number,
    frame: (requestId: string) => string,
    decode: (message: HostMessage) => RequestOutcome<Value> | null,
    settle: Settle<Value>,
  ): string | null {
    const requestId = this.options.newId();

    if (!this.options.send(frame(requestId))) return null;

    const finish = (outcome: RequestOutcome<Value>): void => {
      if (!this.pending.delete(requestId)) return;
      cancelTimer();
      settle(outcome);
    };

    const cancelTimer = this.options.schedule(
      () => finish(failure('timeout', 'Cadenza Host did not answer in time.')),
      timeoutMs,
    );

    this.pending.set(requestId, {
      answer: (message) => {
        const outcome = decode(message);

        if (outcome === null) return false;
        finish(outcome);

        return true;
      },
      abandon: () =>
        finish(failure('unavailable', 'Cadenza Host is not connected.')),
      drop: () => {
        cancelTimer();
        this.pending.delete(requestId);
      },
    });

    return requestId;
  }
}

function succeed<Value>(value: Value): RequestOutcome<Value> {
  return { ok: true, value };
}

function failure(errorCode: string, message: string): RequestOutcome<never> {
  return { ok: false, errorCode, message };
}

function hostFailure(message: HostMessage): RequestOutcome<never> | null {
  return message.type === 'error'
    ? failure(message.errorCode, message.message)
    : null;
}

function answerIdOf(message: HostMessage): string | null {
  switch (message.type) {
    case 'search.result':
    case 'search.suggestions':
    case 'song.ready':
    case 'browse.result':
    case 'error':
      return message.requestId;
    default:
      return null;
  }
}
