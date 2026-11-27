import {
  booleanField,
  isJsonObject,
  numberField,
  parseJson,
  stringField,
  type JsonObject,
} from '../protocol/json';

// The Remote's stream settings and their bounds. `shared/protocol/v1/remote-audio.schema.json` is the contract, and the
// Host refuses any value outside these bounds rather than clamping it.

export type RemoteAudioStreamMode =
  'pure_transfer_exclusive' | 'pure_transfer_mirror' | 'crossover_split';

export interface RemoteAudioSettings {
  enabled: boolean;
  streamMode: RemoteAudioStreamMode;
  crossoverHz: number;
  subGainDb: number;
  phaseInvert: boolean;
  manualDistanceOffsetMs: number;
}

export const remoteAudioBounds = {
  crossoverHz: { min: 40, max: 160, default: 80 },
  subGainDb: { min: -12, max: 12, default: 0 },
  manualDistanceOffsetMs: { min: -50, max: 50, default: 0 },
} as const;

export const defaultRemoteAudioSettings: RemoteAudioSettings = {
  enabled: false,
  streamMode: 'pure_transfer_exclusive',
  crossoverHz: remoteAudioBounds.crossoverHz.default,
  subGainDb: remoteAudioBounds.subGainDb.default,
  phaseInvert: false,
  manualDistanceOffsetMs: remoteAudioBounds.manualDistanceOffsetMs.default,
};

/** The message the Remote sends on its audio socket, for a target Remote. */
export function streamConfigMessage(
  settings: RemoteAudioSettings,
  targetClientId: string,
): string {
  return JSON.stringify({
    version: 1,
    type: 'REMOTE_AUDIO_STREAM_CONFIG',
    enabled: settings.enabled,
    streamMode: settings.streamMode,
    targetClientId,
    crossoverHz: settings.crossoverHz,
    subGainDb: settings.subGainDb,
    phaseInvert: settings.phaseInvert,
    manualDistanceOffsetMs: settings.manualDistanceOffsetMs,
  });
}

/** Keeps a numeric setting inside its bounds, so a slider never sends a value the Host would refuse. */
export function clampToBounds(
  value: number,
  bounds: { min: number; max: number },
): number {
  if (Number.isNaN(value)) return bounds.min;

  return Math.min(bounds.max, Math.max(bounds.min, value));
}

/** The mode needs Wi-Fi. A Remote on Bluetooth can choose it, but the Host refuses to stream to it. */
export function transportAllowsStreaming(
  transport: 'wifi_lan' | 'ble',
): boolean {
  return transport === 'wifi_lan';
}

export type RemoteAudioRoomStatus =
  'not_measured' | 'measuring' | 'measured' | 'needs_microphone' | 'failed';

/** The setup the Host owns, as its `REMOTE_AUDIO_SETUP` message carries it. */
export interface RemoteAudioHostSetup extends RemoteAudioSettings {
  targetClientId: string | null;
  roomStatus: RemoteAudioRoomStatus;
  acousticOffsetMs: number;
}

const roomStatuses: readonly RemoteAudioRoomStatus[] = [
  'not_measured',
  'measuring',
  'measured',
  'needs_microphone',
  'failed',
];

const streamModes: readonly RemoteAudioStreamMode[] = [
  'pure_transfer_exclusive',
  'pure_transfer_mirror',
  'crossover_split',
];

/** The command a Remote sends to ask the Host for a new output environment. */
export function commandMessage(action: 'new_environment'): string {
  return JSON.stringify({ version: 1, type: 'REMOTE_AUDIO_COMMAND', action });
}

function within(value: number, bounds: { min: number; max: number }): boolean {
  return value >= bounds.min && value <= bounds.max;
}

/** A number field that is present and inside its bounds, or null. */
function boundedField(
  object: JsonObject,
  key: string,
  bounds: { min: number; max: number },
): number | null {
  const value = numberField(object, key);

  return value !== null && within(value, bounds) ? value : null;
}

function isStreamMode(value: string): value is RemoteAudioStreamMode {
  return streamModes.some((mode) => mode === value);
}

function isRoomStatus(value: string): value is RemoteAudioRoomStatus {
  return roomStatuses.some((status) => status === value);
}

/**
 * Parses the Host's `REMOTE_AUDIO_SETUP` text. Returns null for a message of the wrong shape, a value outside its bounds,
 * or an unknown status. The Host sends a setup with no target until one is chosen, so `targetClientId` may be absent.
 */
export function parseSetupMessage(text: string): RemoteAudioHostSetup | null {
  const object = parseJson(text);

  if (object === null || !isJsonObject(object)) return null;

  const enabled = booleanField(object, 'enabled');
  const phaseInvert = booleanField(object, 'phaseInvert');
  const streamMode = stringField(object, 'streamMode');
  const roomStatus = stringField(object, 'roomStatus');

  const crossoverHz = boundedField(
    object,
    'crossoverHz',
    remoteAudioBounds.crossoverHz,
  );

  const subGainDb = boundedField(
    object,
    'subGainDb',
    remoteAudioBounds.subGainDb,
  );

  const manualDistanceOffsetMs = boundedField(
    object,
    'manualDistanceOffsetMs',
    remoteAudioBounds.manualDistanceOffsetMs,
  );

  const acousticOffsetMs = boundedField(object, 'acousticOffsetMs', {
    min: -50,
    max: 50,
  });

  const targetClientId = stringField(object, 'targetClientId');

  if (
    stringField(object, 'type') !== 'REMOTE_AUDIO_SETUP' ||
    numberField(object, 'version') !== 1 ||
    enabled === null ||
    phaseInvert === null ||
    streamMode === null ||
    !isStreamMode(streamMode) ||
    roomStatus === null ||
    !isRoomStatus(roomStatus) ||
    crossoverHz === null ||
    subGainDb === null ||
    manualDistanceOffsetMs === null ||
    acousticOffsetMs === null ||
    (object.targetClientId !== undefined && targetClientId === null)
  ) {
    return null;
  }

  return {
    enabled,
    streamMode,
    crossoverHz,
    subGainDb,
    phaseInvert,
    manualDistanceOffsetMs,
    targetClientId,
    roomStatus,
    acousticOffsetMs,
  };
}
