import type { RemoteAudioStatus } from './receiver';

export interface StreamRoundTrip {
  totalMs: number;
  networkMs: number;
  processingMs: number;
}

export function streamRoundTrip(
  status: Pick<
    RemoteAudioStatus,
    'transmitting' | 'networkRttMs' | 'processingRttMs'
  >,
): StreamRoundTrip | null {
  if (
    !status.transmitting ||
    status.networkRttMs === null ||
    status.processingRttMs === null
  ) {
    return null;
  }

  const networkMs = Math.round(status.networkRttMs);
  const processingMs = Math.round(status.processingRttMs);

  return { totalMs: networkMs + processingMs, networkMs, processingMs };
}
