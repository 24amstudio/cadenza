import type {
  CastDevice,
  CastDisplay,
  CastPresentation,
  CastState,
  CastTransmitState,
  PendingStage,
  StageDevice,
} from './types';
import {
  arrayField,
  booleanField,
  counterField,
  isJsonObject,
  objectField,
  stringField,
  type JsonObject,
  type JsonValue,
} from './json';

// The Cast and Cadenza TV parts of the host snapshot. A malformed field drops that device, never the whole snapshot.

export function decodeCast(object: JsonObject | null): CastState | null {
  if (object === null) return null;

  const presentation = stringField(object, 'presentation');

  if (!isCastPresentation(presentation)) return null;

  return {
    presentation,
    devices: decodeCastDevices(arrayField(object, 'devices') ?? []),
    transmit: decodeCastTransmit(objectField(object, 'transmit')),
    stages: decodeStages(arrayField(object, 'stages') ?? []),
    pendingStages: decodePendingStages(
      arrayField(object, 'pending_stages') ?? [],
    ),
  };
}

function decodeStages(values: JsonValue[]): StageDevice[] {
  return values.flatMap((value) => {
    if (!isJsonObject(value)) return [];

    const receiverId = stringField(value, 'receiver_id');
    const name = stringField(value, 'name');
    const transport = stringField(value, 'transport');
    const transmitting = booleanField(value, 'transmitting');

    if (
      receiverId === null ||
      name === null ||
      transport === null ||
      transmitting === null
    )
      return [];

    return [{ receiverId, name, transport, transmitting }];
  });
}

function decodePendingStages(values: JsonValue[]): PendingStage[] {
  return values.flatMap((value) => {
    if (!isJsonObject(value)) return [];

    const receiverId = stringField(value, 'receiver_id');
    const name = stringField(value, 'name');
    const pin = stringField(value, 'pin');
    const expiresInMs = counterField(value, 'expires_in_ms');

    if (
      receiverId === null ||
      name === null ||
      pin === null ||
      expiresInMs === null
    )
      return [];

    return [{ receiverId, name, pin, expiresInMs }];
  });
}

function decodeCastTransmit(
  object: JsonObject | null,
): CastTransmitState | null {
  if (object === null) return null;

  const state = stringField(object, 'state');

  if (!isCastTransmitState(state)) return null;

  return {
    state,
    device: stringField(object, 'device'),
    reason: stringField(object, 'reason'),
  };
}

function isCastTransmitState(
  value: string | null,
): value is CastTransmitState['state'] {
  return (
    value === 'idle' ||
    value === 'starting' ||
    value === 'transmitting' ||
    value === 'failed'
  );
}

function isCastPresentation(value: string | null): value is CastPresentation {
  return value === 'auto' || value === 'audio_only' || value === 'full_suite';
}

function decodeCastDevices(values: JsonValue[]): CastDevice[] {
  return values.flatMap((value) => {
    if (!isJsonObject(value)) return [];

    const name = stringField(value, 'name');
    const display = stringField(value, 'display');

    if (name === null || !isCastDisplay(display)) return [];

    return [{ name, label: stringField(value, 'label') ?? name, display }];
  });
}

function isCastDisplay(value: string | null): value is CastDisplay {
  return value === 'none' || value === 'display' || value === 'unknown';
}
