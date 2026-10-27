import assert from 'node:assert/strict';
import test from 'node:test';
import { Ajv2020 } from 'ajv/dist/2020.js';
import common from '../shared/protocol/v1/common.schema.json' with { type: 'json' };
import command from '../shared/protocol/v1/command.schema.json' with { type: 'json' };
import result from '../shared/protocol/v1/result.schema.json' with { type: 'json' };
import credit from '../shared/protocol/v1/credit.schema.json' with { type: 'json' };
import state from '../shared/protocol/v1/state.schema.json' with { type: 'json' };

const ajv = new Ajv2020({ strict: true, allErrors: true });

ajv.addSchema(common);

ajv.addSchema(state);

const validateCommand = ajv.compile(command);
const validateResult = ajv.compile(result);
const validateCredit = ajv.compile(credit);
const commandId = '00000000-0000-4000-8000-000000000001';
const epoch = '00000000-0000-4000-8000-000000000002';
const occurrence = '00000000-0000-4000-8000-000000000003';

const base = {
  version: 1,
  type: 'command',
  command_id: commandId,
  host_epoch: epoch,
  expires_at_host_ms: 5000,
  expected_revision: 2,
};

test('commands support catalog/library identities without accepting script or owner injection', () => {
  const enqueue = {
    ...base,
    action: {
      kind: 'queue.enqueue',
      song: { source: 'catalog', id: '18446744073709551615' },
    },
  };

  assert.equal(
    validateCommand(enqueue),
    true,
    JSON.stringify(validateCommand.errors),
  );
  assert.equal(
    validateCommand({
      ...base,
      action: {
        kind: 'queue.enqueue',
        song: { source: 'library', id: 'AB1234567890CDEF' },
      },
    }),
    true,
  );
  assert.equal(
    validateCommand({ ...enqueue, requested_by: 'another-tablet' }),
    false,
  );
  assert.equal(
    validateCommand({
      ...base,
      action: {
        kind: 'queue.enqueue',
        song: { source: 'catalog', id: '123"; do shell script "anything' },
      },
    }),
    false,
  );
  assert.equal(
    validateCommand({
      ...base,
      action: { kind: 'execute', script: 'arbitrary script' },
    }),
    false,
  );
});

test('unsafe counters, invalid volume, missing boot identity, and unguarded transport are rejected', () => {
  const pause = {
    ...base,
    action: { kind: 'playback.pause', occurrence_id: occurrence },
  };

  assert.equal(validateCommand(pause), true);
  assert.equal(validateCommand({ ...pause, host_epoch: '' }), false);
  assert.equal(validateCommand({ ...pause, expected_revision: -1 }), false);
  assert.equal(validateCommand({ ...pause, expected_revision: 1.5 }), false);
  assert.equal(
    validateCommand({ ...pause, expires_at_host_ms: 9007199254740992 }),
    false,
  );
  assert.equal(
    validateCommand({ ...base, action: { kind: 'playback.skip' } }),
    false,
  );
  assert.equal(
    validateCommand({
      ...base,
      action: { kind: 'playback.volume', percent: 101 },
    }),
    false,
  );
  assert.equal(
    validateCommand({
      ...base,
      action: {
        kind: 'playback.seek',
        occurrence_id: occurrence,
        position_ms: -1,
      },
    }),
    false,
  );
});

test('results distinguish confirmed completion from uncertainty and deadline failure', () => {
  const response = {
    version: 1,
    type: 'command.result',
    command_id: commandId,
    host_epoch: epoch,
    revision: 2,
  };

  assert.equal(validateResult({ ...response, outcome: 'applied' }), true);
  assert.equal(
    validateResult({
      ...response,
      outcome: 'applied',
      error_code: 'forbidden',
    }),
    false,
  );
  assert.equal(validateResult({ ...response, outcome: 'unconfirmed' }), false);
  assert.equal(
    validateResult({
      ...response,
      outcome: 'unconfirmed',
      error_code: 'outcome_unknown',
    }),
    true,
  );
  assert.equal(
    validateResult({
      ...response,
      outcome: 'expired',
      error_code: 'forbidden',
    }),
    false,
  );
  assert.equal(
    validateResult({ ...response, outcome: 'expired', error_code: 'expired' }),
    true,
  );
  assert.equal(
    validateResult({
      ...response,
      outcome: 'rejected',
      error_code: 'forbidden',
    }),
    true,
  );
  assert.equal(
    validateResult({
      ...response,
      outcome: 'rejected',
      error_code: 'outcome_unknown',
    }),
    false,
  );
  assert.equal(validateResult({ ...response, outcome: 'accepted' }), false);
  assert.equal(
    validateResult({ ...response, outcome: 'applied', resolved: true }),
    false,
  );
  assert.equal(
    validateResult({
      ...response,
      outcome: 'unconfirmed',
      error_code: 'outcome_unknown',
      resolved: true,
    }),
    true,
  );
});

test('analytics credits cannot count a play without observed playback time', () => {
  const event = {
    version: 1,
    type: 'analytics.credit',
    event_id: commandId,
    sequence: 1,
    occurrence_id: occurrence,
    song: { source: 'catalog', id: '100' },
    play_count_delta: 1,
    played_ms_delta: 1000,
  };

  assert.equal(validateCredit(event), true);
  assert.equal(validateCredit({ ...event, played_ms_delta: 0 }), false);
  assert.equal(validateCredit({ ...event, played_ms_delta: -1 }), false);
  assert.equal(validateCredit({ ...event, play_count_delta: 2 }), false);
  assert.equal(validateCredit({ ...event, sequence: 0 }), false);
  assert.equal(
    validateCredit({ ...event, play_count_delta: 0, played_ms_delta: 0 }),
    true,
  );
});
