import { describe, expect, test } from 'bun:test';
import { isCasting } from '../app/lib/casting';
import type {
  CastState,
  CastTransmitState,
  StageDevice,
} from '../app/lib/protocol/types';

const idleCast: CastState = {
  presentation: 'auto',
  devices: [],
  transmit: null,
  stages: [],
  pendingStages: [],
};

function transmitting(state: CastTransmitState['state']): CastTransmitState {
  return { state, device: 'Living Room TV', reason: null };
}

function stage(isTransmitting: boolean): StageDevice {
  return {
    receiverId: 'tv-1',
    name: 'Bedroom TV',
    transport: 'cadenza_web_tv_stage',
    transmitting: isTransmitting,
  };
}

describe('casting indicator', () => {
  test('nothing is cast when no Remote stream, Cast device, or TV is receiving', () => {
    expect(isCasting(null)).toBe(false);
    expect(isCasting({ cast: idleCast, remoteAudioTarget: null })).toBe(false);
  });

  test('a Wi-Fi stream to a Remote counts, even with no Cast device', () => {
    expect(
      isCasting({ cast: idleCast, remoteAudioTarget: 'Living Room iPad' }),
    ).toBe(true);
  });

  test('a Cast device counts only once it is transmitting, not while it is starting or after it fails', () => {
    const withTransmit = (state: CastTransmitState['state']) => ({
      cast: { ...idleCast, transmit: transmitting(state) },
    });

    expect(isCasting(withTransmit('transmitting'))).toBe(true);
    expect(isCasting(withTransmit('starting'))).toBe(false);
    expect(isCasting(withTransmit('failed'))).toBe(false);
  });

  test('a Cadenza TV counts only while it is receiving audio', () => {
    expect(isCasting({ cast: { ...idleCast, stages: [stage(true)] } })).toBe(
      true,
    );
    expect(isCasting({ cast: { ...idleCast, stages: [stage(false)] } })).toBe(
      false,
    );
  });
});
