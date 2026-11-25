import assert from 'node:assert/strict';
import test from 'node:test';
import {
  initialReceiverState,
  reduceKaraoke,
} from '../apps/cast-receiver/karaoke-state.js';

test('a session message sets mode, artwork, motion, and clamped lip-sync offset', () => {
  const theater = reduceKaraoke(initialReceiverState(), {
    type: 'session',
    title: 'Pedida perfeita',
    artist: 'Akad',
    mode: 'theater',
    artworkUrl: 'http://192.168.1.10:9000/cast/artwork',
    motionUrl: 'http://192.168.1.10:9000/cast/motion.mp4',
    lipSyncOffsetMs: 120,
  });

  const video = reduceKaraoke(initialReceiverState(), {
    type: 'session',
    title: 'Video',
    mode: 'karaoke_video',
    artworkUrl: 'javascript:alert(1)',
    lipSyncOffsetMs: 9999,
  });

  const unknown = reduceKaraoke(initialReceiverState(), {
    type: 'session',
    title: 'Pedida perfeita',
    mode: 'surround',
  });

  assert.deepEqual(theater, {
    mode: 'theater',
    title: 'Pedida perfeita',
    artist: 'Akad',
    artworkUrl: 'http://192.168.1.10:9000/cast/artwork',
    motionUrl: 'http://192.168.1.10:9000/cast/motion.mp4',
    lipSyncOffsetMs: 120,
    line: '',
    next: '',
    translation: '',
  });
  assert.equal(video.mode, 'karaoke_video');
  assert.equal(video.artworkUrl, null);
  assert.equal(video.lipSyncOffsetMs, 500);
  assert.equal(unknown.mode, 'audio_only');
});

test('a line message sets sung line, translation, and next line with bounded text', () => {
  const state = reduceKaraoke(initialReceiverState(), {
    type: 'line',
    text: 'first line',
    translation: 'terjemahan',
    next: 'x'.repeat(2_000),
  });

  assert.equal(state.line, 'first line');
  assert.equal(state.translation, 'terjemahan');
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
