import { describe, expect, test } from 'bun:test';
import { qualityView } from '../app/lib/remoteAudio/quality';

describe('stream quality view', () => {
  test('shows nothing until the Host names a tier this Remote knows', () => {
    expect(qualityView(null, 'steady')).toBeNull();
    expect(qualityView('ultra_96_24', 'steady')).toBeNull();
  });

  test('labels the top tier 24/48 and says what it is, with its rate', () => {
    expect(qualityView('lossless_24_48', 'steady')).toEqual({
      label: '24/48',
      detail: 'Lossless 24-bit/48 kHz stereo · 2.3 Mbps. Full quality.',
    });
  });

  test('names the reason the Host lowered the stream', () => {
    expect(qualityView('standard_16_48', 'network')?.detail).toBe(
      '16-bit/48 kHz stereo · 1.5 Mbps. Lowered for Wi-Fi pressure.',
    );
  });

  test('reads an unfamiliar reason as steady rather than inventing a cause', () => {
    expect(qualityView('lossless_24_48', 'future_reason')?.detail).toContain(
      'Full quality.',
    );
  });
});
