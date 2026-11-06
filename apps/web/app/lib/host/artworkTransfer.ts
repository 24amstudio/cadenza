import { artworkDataUrl } from './artwork';
import {
  ArtworkAssembly,
  base64ToBytes,
  bytesToBase64,
  digestMatches,
} from './artworkAssembly';
import { traceEvent } from './trace';

export interface ArtworkChunkFrame {
  requestId: string;
  index: number;
  count: number;
  totalBytes: number;
  sha256: string;
  dataBase64: string;
}

// What the client knows about the artwork requests that chunks may answer.
export interface ArtworkSink {
  // The artwork URL of the open request, or null when the request is closed.
  artworkRequest(requestId: string): string | null;
  // Closes the request. A null image keeps the preview on screen.
  deliver(requestId: string, artworkUrl: string, dataUrl: string | null): void;
}

// Reassembles the full image from chunks, one assembly per request. The image replaces the preview only after its
// digest verifies and it is a recognised image.
export class ArtworkChunks {
  private readonly sink: ArtworkSink;
  private readonly assemblies = new Map<string, ArtworkAssembly>();

  constructor(sink: ArtworkSink) {
    this.sink = sink;
  }

  reset(): void {
    this.assemblies.clear();
  }

  receive(frame: ArtworkChunkFrame): void {
    const artworkUrl = this.sink.artworkRequest(frame.requestId);

    if (artworkUrl === null) return;
    let assembly = this.assemblies.get(frame.requestId);

    if (assembly === undefined) {
      if (!ArtworkAssembly.accepts(frame.count, frame.totalBytes)) return;
      assembly = new ArtworkAssembly(
        frame.count,
        frame.totalBytes,
        frame.sha256,
      );
      this.assemblies.set(frame.requestId, assembly);
      traceEvent('artwork transfer started', {
        requestId: frame.requestId,
        chunks: frame.count,
        bytes: frame.totalBytes,
      });
    }

    const file = assembly.add(frame.index, base64ToBytes(frame.dataBase64));

    if (file === null) return;
    this.assemblies.delete(frame.requestId);
    void this.verify(frame.requestId, artworkUrl, file, assembly.sha256);
  }

  private async verify(
    requestId: string,
    artworkUrl: string,
    file: Uint8Array,
    sha256: string,
  ): Promise<void> {
    const verified = await digestMatches(file, sha256);

    if (this.sink.artworkRequest(requestId) === null) return;

    if (!verified) {
      traceEvent('artwork failed verification; keeping the preview');
      this.sink.deliver(requestId, artworkUrl, null);

      return;
    }

    // A file that is not a recognised image keeps the preview on screen rather than clearing it.
    const dataUrl = artworkDataUrl(bytesToBase64(file));

    if (dataUrl === null) {
      traceEvent('artwork is not a recognised image; keeping the preview');
      this.sink.deliver(requestId, artworkUrl, null);

      return;
    }

    traceEvent('artwork verified', { requestId, bytes: file.length });
    this.sink.deliver(requestId, artworkUrl, dataUrl);
  }
}
