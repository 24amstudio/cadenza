import {
  ArtworkAssembly,
  base64ToBytes,
  digestMatches,
} from './artworkAssembly';
import { traceEvent } from './trace';

export interface MotionChunkFrame {
  requestId: string;
  occurrenceId: string;
  index: number;
  count: number;
  totalBytes: number;
  sha256: string;
  dataBase64: string;
}

// What the client knows about the artwork requests that a motion video may answer.
export interface MotionSink {
  // The artwork URL of the open request that asked for this occurrence's motion, or null when there is none.
  motionRequest(requestId: string, occurrenceId: string): string | null;
  // Closes the request. The video is null when it failed verification.
  finish(
    requestId: string,
    artworkUrl: string,
    video: Uint8Array<ArrayBuffer> | null,
  ): void;
}

// Reassembles the motion video that the Host sends under an artwork request. One transfer is kept at a time, because
// the page asks for the playing song's artwork alone. A video is delivered only after every chunk arrived and its digest
// matches, and a request that closed meanwhile receives nothing.
export class MotionTransfer {
  private readonly sink: MotionSink;
  private transfer: {
    requestId: string;
    assembly: ArtworkAssembly;
  } | null = null;

  constructor(sink: MotionSink) {
    this.sink = sink;
  }

  reset(): void {
    this.transfer = null;
  }

  receive(frame: MotionChunkFrame): void {
    if (this.sink.motionRequest(frame.requestId, frame.occurrenceId) === null) {
      return;
    }

    const complete = this.add(frame);

    if (complete !== null) void this.verify(frame, complete);
  }

  // Returns the whole file, with the digest the Host announced, once the last chunk arrives. Otherwise null.
  private add(
    frame: MotionChunkFrame,
  ): { file: Uint8Array<ArrayBuffer>; sha256: string } | null {
    let current = this.transfer;

    if (current?.requestId !== frame.requestId) {
      if (!ArtworkAssembly.accepts(frame.count, frame.totalBytes)) return null;

      current = {
        requestId: frame.requestId,
        assembly: new ArtworkAssembly(
          frame.count,
          frame.totalBytes,
          frame.sha256,
        ),
      };
      this.transfer = current;
    }

    const file = current.assembly.add(
      frame.index,
      base64ToBytes(frame.dataBase64),
    );

    if (file === null) return null;
    this.transfer = null;

    return { file, sha256: current.assembly.sha256 };
  }

  private async verify(
    frame: MotionChunkFrame,
    complete: { file: Uint8Array<ArrayBuffer>; sha256: string },
  ): Promise<void> {
    const verified = await digestMatches(complete.file, complete.sha256);

    const artworkUrl = this.sink.motionRequest(
      frame.requestId,
      frame.occurrenceId,
    );

    if (artworkUrl === null) return;
    traceEvent(verified ? 'motion verified' : 'motion failed verification', {
      requestId: frame.requestId,
      bytes: complete.file.length,
    });
    this.sink.finish(
      frame.requestId,
      artworkUrl,
      verified ? complete.file : null,
    );
  }
}
