import type { CurrentPlayback } from './protocol/types';

// Position is anchored to the Host sample time. While playing, the browser advances it from that anchor on the Host
// timeline, so progress stays correct between state updates without polling.
export function positionAt(
  current: CurrentPlayback,
  playing: boolean,
  hostNowMs: number,
): number {
  const elapsedMs = playing
    ? Math.max(0, hostNowMs - current.sampledAtHostMs)
    : 0;

  const position = current.positionMs + elapsedMs;
  const duration = current.song.durationMs;

  return duration === null ? position : Math.min(position, duration);
}

export function progressRatio(
  positionMs: number,
  durationMs: number | null,
): number {
  if (durationMs === null || durationMs <= 0) return 0;

  return Math.min(1, Math.max(0, positionMs / durationMs));
}

export function formatClock(milliseconds: number): string {
  const totalSeconds = Math.floor(Math.max(0, milliseconds) / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = String(totalSeconds % 60).padStart(2, '0');

  if (hours > 0)
    return `${hours}:${String(minutes).padStart(2, '0')}:${seconds}`;

  return `${minutes}:${seconds}`;
}

export function formatWait(milliseconds: number | null): string {
  if (milliseconds === null) return 'Waiting';
  const minutes = Math.round(milliseconds / 60_000);

  if (minutes < 1) return 'Next';

  return `In ${minutes} min`;
}
