export const ambientModes = ['basic', 'artwork', 'alive'] as const;

export type AmbientMode = (typeof ambientModes)[number];

export const defaultAmbientMode: AmbientMode = 'artwork';

export const ambientIdleMs = 5 * 60_000;

export const ambientWakeDistancePx = 4;

export const ambientModeOptions: readonly {
  value: AmbientMode;
  label: string;
  detail: string;
}[] = [
  {
    value: 'basic',
    label: 'Basic',
    detail: 'The clock, the title and the artist.',
  },
  {
    value: 'artwork',
    label: 'Artwork',
    detail: 'The clock, the title, the artist and the cover.',
  },
  {
    value: 'alive',
    label: 'Alive',
    detail:
      'The clock and the full song, over the motion cover blurred behind them.',
  },
];

export function parseAmbientMode(value: string | null): AmbientMode {
  return ambientModes.find((mode) => mode === value) ?? defaultAmbientMode;
}
