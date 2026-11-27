import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { Ajv2020 } from 'ajv/dist/2020.js';
import remoteAudio from '../shared/protocol/v1/remote-audio.schema.json' with { type: 'json' };

const fixture = JSON.parse(
  readFileSync(
    new URL(
      '../shared/protocol/examples/remote-audio-frames.json',
      import.meta.url,
    ),
    'utf8',
  ),
);

const ajv = new Ajv2020({ strict: true, allErrors: true });
const validate = ajv.compile(remoteAudio);

const handshake = {
  version: 1,
  type: 'REMOTE_AUDIO_HANDSHAKE',
  clientId: 'web-remote-living-room',
  token: 'paired-token-0123456789',
  transport: 'wifi_lan',
  sampleRate: 48000,
  baseLatencyMs: 5.3,
  outputLatencyMs: 12.1,
  userAgent: 'Mozilla/5.0',
};

const config = {
  version: 1,
  type: 'REMOTE_AUDIO_STREAM_CONFIG',
  enabled: true,
  streamMode: 'crossover_split',
  targetClientId: 'web-remote-living-room',
  crossoverHz: 80,
  subGainDb: 0,
  phaseInvert: false,
  manualDistanceOffsetMs: 0,
};

const telemetry = {
  version: 1,
  type: 'REMOTE_AUDIO_SYNC',
  streamMode: 'pure_transfer_exclusive',
  calibrationState: 'electronic_locked',
  electronicOffsetMs: 0.4,
  acousticOffsetMs: 0,
  clockOffsetUs: -1200,
  clockDriftPpm: 12.5,
  jitterBufferMs: 28,
  droppedStaleFrames60s: 0,
  linkHealthy: true,
};

test('handshake from a Wi-Fi Remote is accepted, and BLE is refused', () => {
  assert.equal(validate(handshake), true, JSON.stringify(validate.errors));
  assert.equal(validate({ ...handshake, transport: 'ble' }), false);
  assert.equal(validate({ ...handshake, token: 'short' }), false);
});

test('stream config accepts the three modes and refuses values outside the bounds', () => {
  for (const streamMode of [
    'pure_transfer_exclusive',
    'pure_transfer_mirror',
    'crossover_split',
  ]) {
    assert.equal(validate({ ...config, streamMode }), true, streamMode);
  }

  assert.equal(validate({ ...config, streamMode: 'stereo_wide' }), false);
  assert.equal(validate({ ...config, crossoverHz: 39.9 }), false);
  assert.equal(validate({ ...config, crossoverHz: 160 }), true);
  assert.equal(validate({ ...config, subGainDb: 12.5 }), false);
  assert.equal(validate({ ...config, manualDistanceOffsetMs: -50.5 }), false);
});

test('sync telemetry carries the calibration state and clock offset, and refuses unknown states', () => {
  assert.equal(validate(telemetry), true, JSON.stringify(validate.errors));
  assert.equal(
    validate({ ...telemetry, calibrationState: 'chirp_locked' }),
    false,
  );
  assert.equal(validate({ ...telemetry, clockOffsetUs: 1.5 }), false);
});

test('binary audio frame header is 26 bytes and its payload matches the header', () => {
  const bytes = Buffer.from(fixture.audioFrame.hex, 'hex');
  const { channels, bitDepth, frameCount, samples } = fixture.audioFrame.fields;
  const headerBytes = 26;

  assert.equal(bytes[0], 0x01);
  assert.equal(
    bytes.length - headerBytes,
    (frameCount * channels * bitDepth) / 8,
  );
  assert.equal(bytes.length - headerBytes, samples.length * 2);
  assert.equal(bytes.readUInt32BE(4), fixture.audioFrame.fields.sequenceNumber);
  assert.equal(bytes.readUInt16BE(24), frameCount);
  assert.deepEqual(
    Array.from({ length: samples.length }, (_, i) =>
      bytes.readInt16LE(headerBytes + i * 2),
    ),
    samples,
  );
});

test('control frames match their documented sizes and type bytes', () => {
  const flush = Buffer.from(fixture.flush.hex, 'hex');
  const ping = Buffer.from(fixture.ping.hex, 'hex');
  const pong = Buffer.from(fixture.pong.hex, 'hex');

  assert.equal(flush.length, 5);
  assert.equal(flush[0], 0x02);
  assert.equal(flush.readUInt32BE(1), fixture.flush.fields.generationSeq);
  assert.equal(ping.length, 17);
  assert.equal(ping[0], 0x04);
  assert.equal(pong.length, 25);
  assert.equal(pong[0], 0x05);
  assert.equal(
    pong.readBigUInt64BE(1).toString(),
    fixture.pong.fields.t1HostSendUs,
  );
});

const command = {
  version: 1,
  type: 'REMOTE_AUDIO_COMMAND',
  action: 'new_environment',
};

const setup = {
  version: 1,
  type: 'REMOTE_AUDIO_SETUP',
  enabled: true,
  streamMode: 'crossover_split',
  targetClientId: 'web-remote-living-room',
  crossoverHz: 80,
  subGainDb: 0,
  phaseInvert: false,
  manualDistanceOffsetMs: 0,
  roomStatus: 'measured',
  acousticOffsetMs: -1.5,
};

test('a Remote command is accepted only with a known action', () => {
  assert.equal(validate(command), true, JSON.stringify(validate.errors));
  assert.equal(validate({ ...command, action: 'factory_reset' }), false);
});

test('the Host setup carries the saved values and the room status, and it refuses an unknown status', () => {
  assert.equal(validate(setup), true, JSON.stringify(validate.errors));
  assert.equal(validate({ ...setup, roomStatus: 'almost' }), false);
  assert.equal(validate({ ...setup, crossoverHz: 200 }), false);

  // A setup with no Remote chosen yet omits the target, and that is still a valid setup.
  const unassigned = {
    version: 1,
    type: 'REMOTE_AUDIO_SETUP',
    enabled: true,
    streamMode: 'crossover_split',
    crossoverHz: 80,
    subGainDb: 0,
    phaseInvert: false,
    manualDistanceOffsetMs: 0,
    roomStatus: 'measured',
    acousticOffsetMs: -1.5,
  };

  assert.equal(validate(unassigned), true, JSON.stringify(validate.errors));
});
