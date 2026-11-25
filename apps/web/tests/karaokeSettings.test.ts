import { describe, expect, test } from 'bun:test';
import { decodeHostMessage } from '../app/lib/protocol/decode';
import { encodeCommand } from '../app/lib/protocol/encode';

const commandId = '3f1c2a2e-7b6d-4c1e-9a1f-2d3e4f5a6b7c';
const epoch = '6e4f9a10-1111-4222-8333-444455556666';

const base = {
  commandId,
  hostEpoch: epoch,
  expiresAtHostMs: 9000,
  expectedRevision: 18,
};

describe('karaoke settings', () => {
  test('a saved nudge is sent with the track it belongs to and no other fields', () => {
    const sent = JSON.parse(
      encodeCommand({
        ...base,
        action: {
          kind: 'lyrics.offset',
          song: { source: 'catalog', id: '626140098' },
          offsetMs: -500,
        },
      }),
    );

    expect(sent.action).toEqual({
      kind: 'lyrics.offset',
      song: { source: 'catalog', id: '626140098' },
      user_offset_ms: -500,
    });
  });

  test('a lyric document carries the nudge saved for its track', () => {
    const text = JSON.stringify({
      version: 1,
      type: 'lyrics',
      lyrics: {
        occurrence_id: '0a0b0c0d-1111-4222-8333-444455556666',
        revision: '3f1c2a2e-7b6d-4c1e-9a1f-2d3e4f5a6b7c',
        translation_source: 'none',
        source: 'apple_music',
        user_offset_ms: 250,
        lines: [],
      },
    });

    const message = decodeHostMessage(text);

    expect(
      message?.type === 'lyrics' ? message.lyrics.userOffsetMs : null,
    ).toBe(250);
  });

  test('an offset outside the saved range is not shown as a nudge', () => {
    const text = JSON.stringify({
      version: 1,
      type: 'lyrics',
      lyrics: {
        occurrence_id: '0a0b0c0d-1111-4222-8333-444455556666',
        revision: '3f1c2a2e-7b6d-4c1e-9a1f-2d3e4f5a6b7c',
        translation_source: 'none',
        source: 'apple_music',
        user_offset_ms: 90000,
        lines: [],
      },
    });

    const message = decodeHostMessage(text);

    expect(
      message?.type === 'lyrics' ? message.lyrics.userOffsetMs : 'missing',
    ).toBeNull();
  });
});
