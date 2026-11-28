import type { CastState } from '~/lib/protocol/types';

export interface CastingSource {
  cast: CastState | null;
  remoteAudioTarget?: string | null;
}

export function isCasting(source: CastingSource | null): boolean {
  if (source === null) return false;

  if (source.remoteAudioTarget) return true;

  if (source.cast === null) return false;

  return (
    source.cast.transmit?.state === 'transmitting' ||
    source.cast.stages.some((stage) => stage.transmitting)
  );
}
