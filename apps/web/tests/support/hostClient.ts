import {
  HostClient,
  type HostChange,
  type HostClientOptions,
  type SocketLike,
} from '../../app/lib/host/client';
import type {
  CredentialStore,
  StoredCredential,
} from '../../app/lib/host/credentials';
import {
  counterField,
  isJsonObject,
  objectField,
  parseJson,
  type JsonObject,
  type JsonValue,
} from '../../app/lib/protocol/json';
import type { CommandResult } from '../../app/lib/protocol/types';

export const remoteId = '3f1c2a2e-7b6d-4c1e-9a1f-2d3e4f5a6b7c';
export const epoch = '6e4f9a10-1111-4222-8333-444455556666';
export const occurrenceId = '0a0b0c0d-1111-4222-8333-444455556666';
export const token = 'T'.repeat(43);
export const hostOffsetMs = 1_000;

type Message = { [key: string]: JsonValue | undefined };

export function socketAt(sockets: FakeSocket[], index: number): FakeSocket {
  const socket = sockets[index];

  if (socket === undefined) throw new Error(`No socket at index ${index}`);

  return socket;
}

export class FakeSocket implements SocketLike {
  onOpen: (() => void) | null = null;
  onMessage: ((text: string) => void) | null = null;
  onClose: (() => void) | null = null;
  readonly frames: JsonObject[] = [];
  closed = false;

  send(text: string): void {
    const value = parseJson(text);

    if (value !== null && isJsonObject(value)) this.frames.push(value);
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.onClose?.();
  }

  open(): void {
    this.onOpen?.();
  }

  serverDrop(): void {
    this.close();
  }

  // Undefined fields are omitted by JSON.stringify, matching frames that carry no value for that key.
  receive(message: Message): void {
    this.onMessage?.(JSON.stringify({ version: 1, ...message }));
  }

  framesOfType(type: string): JsonObject[] {
    return this.frames.filter((frame) => frame.type === type);
  }
}

export class Clock {
  now = 0;
  private tasks: { at: number; run: () => void; cancelled: boolean }[] = [];

  schedule = (callback: () => void, delayMs: number): (() => void) => {
    const task = { at: this.now + delayMs, run: callback, cancelled: false };
    this.tasks.push(task);

    return () => {
      task.cancelled = true;
    };
  };

  advance(ms: number): void {
    const target = this.now + ms;

    for (;;) {
      const due = this.tasks
        .filter((task) => !task.cancelled && task.at <= target)
        .sort((first, second) => first.at - second.at)[0];

      if (due === undefined) break;
      this.now = due.at;
      this.tasks = this.tasks.filter((task) => task !== due);
      due.run();
    }

    this.now = target;
  }
}

export class MemoryCredentials implements CredentialStore {
  value: StoredCredential | null = null;
  read(): StoredCredential | null {
    return this.value;
  }
  write(credential: StoredCredential): void {
    this.value = credential;
  }
  clear(): void {
    this.value = null;
  }
}

export interface Harness {
  client: HostClient;
  sockets: FakeSocket[];
  changes: HostChange[];
  clock: Clock;
  credentials: MemoryCredentials;
}

export function harness(
  credentials: MemoryCredentials = new MemoryCredentials(),
  progressiveArtwork = false,
): Harness {
  const clock = new Clock();
  const sockets: FakeSocket[] = [];
  const changes: HostChange[] = [];
  let ids = 0;

  const options: HostClientOptions = {
    url: 'wss://host.test/v1/socket',
    remoteVersion: 'cadenza-web test',
    defaultName: 'Web browser on Mac',
    openSocket: () => {
      const socket = new FakeSocket();
      sockets.push(socket);

      return socket;
    },
    credentials,
    monotonicNow: () => clock.now,
    schedule: clock.schedule,
    newId: () => {
      ids += 1;

      return `id-${ids}`;
    },
    onChange: (change) => changes.push(change),
    progressiveArtwork,
  };

  return {
    client: new HostClient(options),
    sockets,
    changes,
    clock,
    credentials,
  };
}

export function welcome(
  issuedToken: string | null,
  capabilities: string[] = ['artwork.host-cache'],
): JsonObject {
  return {
    type: 'welcome',
    welcome: {
      host_id: remoteId,
      host_name: 'Living room Mac',
      host_epoch: epoch,
      remote_id: remoteId,
      token: issuedToken,
      host_time_ms: hostOffsetMs,
      capabilities,
    },
  };
}

// Answers each clock probe as the Host would: 10 ms round trip, Host clock 1000 ms ahead. A reply triggers the next
// probe, so the loop continues until no unanswered probe remains.
export function answerClockProbes(socket: FakeSocket, clock: Clock): void {
  const answered = new Set<JsonValue | undefined>();

  for (;;) {
    const frame = socket
      .framesOfType('clock')
      .find((candidate) => !answered.has(candidate.request_id));

    if (frame === undefined) return;
    answered.add(frame.request_id);
    const sample = objectField(frame, 'clock');

    const sentAtRemote =
      sample === null ? null : counterField(sample, 'sent_at_remote_ms');

    if (sentAtRemote === null) return;
    clock.advance(10);
    socket.receive({
      type: 'clock',
      request_id: frame.request_id ?? null,
      clock: {
        sent_at_remote_ms: sentAtRemote,
        received_at_host_ms: sentAtRemote + hostOffsetMs + 5,
        sent_at_host_ms: sentAtRemote + hostOffsetMs + 5,
      },
    });
  }
}

export function snapshotFrame(revision: number): JsonObject {
  return {
    type: 'state',
    snapshot: {
      host_id: remoteId,
      host_epoch: epoch,
      revision,
      sequence: 1,
      host_time_ms: 2_000,
      allow_cross_remote_edits: false,
      playing: true,
      volume: 50,
      current: null,
      queue: [],
      quality: 'unknown',
      synchronized: true,
      observation_gap: false,
    },
  };
}

export function phases(changes: HostChange[]): string[] {
  return changes.flatMap((change) =>
    change.kind === 'phase' ? [change.phase] : [],
  );
}

export function results(changes: HostChange[]): CommandResult[] {
  return changes.flatMap((change) =>
    change.kind === 'commandResolved' ? [change.result] : [],
  );
}
