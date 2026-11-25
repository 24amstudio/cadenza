import { encodeArtistMotionGet } from '../protocol/encode';
import type { HostMessage } from '../protocol/decode';
import {
  ArtworkAssembly,
  base64ToBytes,
  digestMatches,
} from './artworkAssembly';

export type ArtistMotionMessage = Extract<
  HostMessage,
  { type: 'artist.motion.chunk' | 'artist.motion.unavailable' }
>;

// How long an Artist Details header waits for its video. The Host stops sending at its own deadline.
export const artistMotionTimeoutMs = 30_000;

interface Pending {
  assembly: ArtworkAssembly | null;
  resolve: (video: Uint8Array<ArrayBuffer> | null) => void;
  timer: ReturnType<typeof setTimeout>;
}

// An artist's motion video travels on its own request ID, outside the artwork lanes, so a header never competes with
// the playing song's artwork. Each request resolves once: with the verified video, or with null.
export class ArtistMotion {
  private readonly pending = new Map<string, Pending>();
  private readonly send: (text: string) => boolean;
  private readonly newId: () => string;

  constructor(send: (text: string) => boolean, newId: () => string) {
    this.send = send;
    this.newId = newId;
  }

  request(artistName: string): Promise<Uint8Array<ArrayBuffer> | null> {
    return new Promise((resolve) => {
      const requestId = this.newId();

      const timer = setTimeout(
        () => this.settle(requestId, null),
        artistMotionTimeoutMs,
      );

      this.pending.set(requestId, { assembly: null, resolve, timer });

      if (!this.send(encodeArtistMotionGet(requestId, artistName))) {
        this.settle(requestId, null);
      }
    });
  }

  receive(message: ArtistMotionMessage): void {
    if (message.type === 'artist.motion.unavailable') {
      this.settle(message.requestId, null);

      return;
    }

    const entry = this.pending.get(message.requestId);

    if (entry === undefined) return;

    if (entry.assembly === null) {
      if (!ArtworkAssembly.accepts(message.count, message.totalBytes)) {
        this.settle(message.requestId, null);

        return;
      }

      entry.assembly = new ArtworkAssembly(
        message.count,
        message.totalBytes,
        message.sha256,
      );
    }

    const file = entry.assembly.add(
      message.index,
      base64ToBytes(message.dataBase64),
    );

    if (file !== null)
      void this.verify(message.requestId, file, entry.assembly.sha256);
  }

  private async verify(
    requestId: string,
    file: Uint8Array<ArrayBuffer>,
    sha256: string,
  ): Promise<void> {
    const verified = await digestMatches(file, sha256);

    this.settle(requestId, verified ? file : null);
  }

  private settle(
    requestId: string,
    video: Uint8Array<ArrayBuffer> | null,
  ): void {
    const entry = this.pending.get(requestId);

    if (entry === undefined) return;

    this.pending.delete(requestId);
    clearTimeout(entry.timer);
    entry.resolve(video);
  }
}
