export type RemoteAudioQualityName =
  'lossless_24_48' | 'standard_16_48' | 'compact_16_48_mono';

export interface RemoteAudioQualityView {
  label: string;
  detail: string;
}

const tiers: Record<
  RemoteAudioQualityName,
  { label: string; format: string; kbps: number }
> = {
  lossless_24_48: {
    label: '24/48',
    format: 'Lossless 24-bit/48 kHz stereo',
    kbps: 2_304,
  },
  standard_16_48: {
    label: '16/48',
    format: '16-bit/48 kHz stereo',
    kbps: 1_536,
  },
  compact_16_48_mono: {
    label: '16/48 mono',
    format: '16-bit/48 kHz mono',
    kbps: 768,
  },
};

const reasons = {
  steady: 'Full quality',
  network: 'Lowered for Wi-Fi pressure',
  remote_playout: 'Lowered for playback pressure on this Remote',
  host_load: 'Lowered for Host CPU load',
  host_power: 'Lowered for Host power or thermal state',
  recovered: 'Restored after a calm stretch',
} satisfies Record<string, string>;

type ReasonName = keyof typeof reasons;

function isTierName(value: string): value is RemoteAudioQualityName {
  return Object.prototype.hasOwnProperty.call(tiers, value);
}

function isReasonName(value: string): value is ReasonName {
  return Object.prototype.hasOwnProperty.call(reasons, value);
}

export function qualityView(
  quality: string | null,
  reason: string,
): RemoteAudioQualityView | null {
  if (quality === null || !isTierName(quality)) return null;

  const tier = tiers[quality];
  const mbps = (tier.kbps / 1_000).toFixed(1);
  const why = isReasonName(reason) ? reasons[reason] : reasons.steady;

  return {
    label: tier.label,
    detail: `${tier.format} · ${mbps} Mbps. ${why}.`,
  };
}
