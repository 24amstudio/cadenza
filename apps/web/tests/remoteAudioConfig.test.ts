import { describe, expect, test } from 'bun:test';
import {
  clampToBounds,
  commandMessage,
  parseSetupMessage,
  defaultRemoteAudioSettings,
  remoteAudioBounds,
  streamConfigMessage,
  transportAllowsStreaming,
} from '../app/lib/remoteAudio/config';
import { remoteAudioSocketUrl } from '../app/lib/remoteAudio/receiver';

describe('remote audio settings', () => {
  test('a config message carries the target Remote and the bounded settings the Host decodes', () => {
    const message = JSON.parse(
      streamConfigMessage(
        {
          ...defaultRemoteAudioSettings,
          enabled: true,
          streamMode: 'crossover_split',
          crossoverHz: 120,
          subGainDb: -3,
          phaseInvert: true,
          manualDistanceOffsetMs: 4.5,
        },
        'web-remote-living-room',
      ),
    );

    expect(message).toEqual({
      version: 1,
      type: 'REMOTE_AUDIO_STREAM_CONFIG',
      enabled: true,
      streamMode: 'crossover_split',
      targetClientId: 'web-remote-living-room',
      crossoverHz: 120,
      subGainDb: -3,
      phaseInvert: true,
      manualDistanceOffsetMs: 4.5,
    });
  });

  test('a slider value outside its bounds is clamped before it is sent', () => {
    const { crossoverHz, subGainDb, manualDistanceOffsetMs } =
      remoteAudioBounds;

    expect(clampToBounds(39, crossoverHz)).toBe(40);
    expect(clampToBounds(200, crossoverHz)).toBe(160);
    expect(clampToBounds(-20, subGainDb)).toBe(-12);
    expect(clampToBounds(60, manualDistanceOffsetMs)).toBe(50);
    expect(clampToBounds(Number.NaN, subGainDb)).toBe(-12);
  });

  test('only a Wi-Fi LAN connection may stream, so a Bluetooth Remote is refused', () => {
    expect(transportAllowsStreaming('wifi_lan')).toBe(true);
    expect(transportAllowsStreaming('ble')).toBe(false);
  });

  test('the audio socket keeps the Host and port of the Remote socket and uses the cast path', () => {
    expect(remoteAudioSocketUrl('ws://192.168.1.20:8787/v1/socket#x')).toBe(
      'ws://192.168.1.20:8787/cast/live?role=remote_audio',
    );
    expect(remoteAudioSocketUrl('wss://cadenza.example/v1/socket')).toBe(
      'wss://cadenza.example/cast/live?role=remote_audio',
    );
  });
});

describe('remote audio setup and command', () => {
  test('the new-environment command carries its protocol type and action', () => {
    expect(JSON.parse(commandMessage('new_environment'))).toEqual({
      version: 1,
      type: 'REMOTE_AUDIO_COMMAND',
      action: 'new_environment',
    });
  });

  test('a Host setup parses into the values the Remote shows, and a bad one is refused', () => {
    const host = {
      version: 1,
      type: 'REMOTE_AUDIO_SETUP',
      enabled: true,
      streamMode: 'crossover_split',
      targetClientId: 'web-remote-living-room',
      crossoverHz: 120,
      subGainDb: -3,
      phaseInvert: true,
      manualDistanceOffsetMs: 4.5,
      roomStatus: 'measured',
      acousticOffsetMs: -1.5,
    };

    expect(parseSetupMessage(JSON.stringify(host))).toEqual({
      enabled: true,
      streamMode: 'crossover_split',
      targetClientId: 'web-remote-living-room',
      crossoverHz: 120,
      subGainDb: -3,
      phaseInvert: true,
      manualDistanceOffsetMs: 4.5,
      roomStatus: 'measured',
      acousticOffsetMs: -1.5,
    });
    expect(
      parseSetupMessage(JSON.stringify({ ...host, crossoverHz: 200 })),
    ).toBeNull();
    expect(
      parseSetupMessage(JSON.stringify({ ...host, roomStatus: 'almost' })),
    ).toBeNull();
    expect(parseSetupMessage('not json')).toBeNull();
  });

  test('a setup with no Remote chosen parses with a null target', () => {
    const unassigned = {
      version: 1,
      type: 'REMOTE_AUDIO_SETUP',
      enabled: false,
      streamMode: 'pure_transfer_exclusive',
      crossoverHz: 80,
      subGainDb: 0,
      phaseInvert: false,
      manualDistanceOffsetMs: 0,
      roomStatus: 'not_measured',
      acousticOffsetMs: 0,
    };

    expect(
      parseSetupMessage(JSON.stringify(unassigned))?.targetClientId,
    ).toBeNull();
  });
});
