import { describe, expect, test } from 'bun:test';
import {
  STAGE_LOG_MAX_LENGTH,
  stageLogMessage,
  stagePlaybackMessage,
} from '../app/lib/stage/stageProtocol';

describe('Stage receiver reports', () => {
  test('a playback report names what this output plays and nothing else', () => {
    const text = stagePlaybackMessage({
      codec: 'pcm',
      channels: 2,
      path: 'pcm_worklet',
      active: true,
    });

    expect(JSON.parse(text)).toEqual({
      version: 1,
      type: 'STAGE_PLAYBACK',
      codec: 'pcm',
      channels: 2,
      path: 'pcm_worklet',
      active: true,
    });
  });

  test('a log line keeps its level and stays within the Host limit', () => {
    const text = stageLogMessage('warn', 'x'.repeat(STAGE_LOG_MAX_LENGTH + 40));

    const parsed = JSON.parse(text);

    expect(parsed.type).toBe('STAGE_LOG');
    expect(parsed.level).toBe('warn');
    expect(parsed.message).toHaveLength(STAGE_LOG_MAX_LENGTH);
  });
});
