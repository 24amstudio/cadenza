import type { AudioQuality, CurrentPlayback } from './protocol/types';

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

// The names Music's audio tier badge uses, matching the native Remote. Nothing is shown while the tier is unread.
export function qualityLabel(quality: AudioQuality): string | null {
  switch (quality) {
    case 'lossless':
      return 'Lossless';
    case 'hi_res_lossless':
      return 'Hi-Res Lossless';
    case 'dolby_atmos':
      return 'Dolby Atmos';
    case 'unknown':
      return null;
  }
}

// Long totals read as hours and minutes, which a summary card can show at a glance.
export function formatListeningTime(milliseconds: number): string {
  const totalMinutes = Math.floor(Math.max(0, milliseconds) / 60_000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;

  if (hours === 0) return `${minutes} min`;

  return `${hours} h ${minutes} min`;
}
