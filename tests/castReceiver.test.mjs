import assert from 'node:assert/strict';
import test from 'node:test';
import {
  initialReceiverState,
  reduceKaraoke,
} from '../apps/cast-receiver/karaoke-state.js';

test('a session message names the track and switches to Full Suite only when asked for it', () => {
  const full = reduceKaraoke(initialReceiverState(), {
    type: 'session',
    title: 'Pedida perfeita',
    mode: 'full_suite',
  });

  const unknown = reduceKaraoke(initialReceiverState(), {
    type: 'session',
    title: 'Pedida perfeita',
    mode: 'surround',
  });

  assert.deepEqual(full, {
    mode: 'full_suite',
    title: 'Pedida perfeita',
    line: '',
    next: '',
  });
  assert.equal(unknown.mode, 'audio_only');
});

test('a line message sets the sung line and the next one, and long text is bounded', () => {
  const state = reduceKaraoke(initialReceiverState(), {
    type: 'line',
    text: 'first line',
    next: 'x'.repeat(2_000),
  });

  assert.equal(state.line, 'first line');
  assert.equal(state.next.length, 500);
});

test('a message that is not an object, or of an unknown type, leaves the view as it was', () => {
  const state = reduceKaraoke(initialReceiverState(), {
    type: 'line',
    text: 'kept',
    next: '',
  });

  assert.equal(reduceKaraoke(state, null), state);
  assert.equal(reduceKaraoke(state, 'line'), state);
  assert.equal(
    reduceKaraoke(state, {
      type: 'artwork',
      url: 'https://example.test/a.jpg',
    }),
    state,
  );
});
