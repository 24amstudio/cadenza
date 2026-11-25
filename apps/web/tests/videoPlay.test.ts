import { describe, expect, test } from 'bun:test';
import {
  SongRequests,
  type RequestOutcome,
} from '../app/lib/host/songRequests';
import type { SongIdentity } from '../app/lib/protocol/types';
import { Clock } from './support/hostClient';

const video: SongIdentity = { source: 'catalog', id: '626140098' };

function requestsOver() {
  const clock = new Clock();
  const sent: string[] = [];
  let linked = true;
  let ids = 0;

  const requests = new SongRequests({
    send: (text) => {
      if (!linked) return false;
      sent.push(text);

      return true;
    },
    newId: () => {
      ids += 1;

      return `request-${ids}`;
    },
    schedule: clock.schedule,
  });

  return {
    requests,
    sent,
    unlink: () => {
      linked = false;
    },
  };
}

describe('music video play requests', () => {
  test('a video is sent once as a play request and settles once when the Host starts it', () => {
    const { requests, sent } = requestsOver();
    const outcomes: RequestOutcome<null>[] = [];

    requests.playVideo(video, (outcome) => outcomes.push(outcome));

    expect(JSON.parse(sent[0] ?? '{}')).toEqual({
      version: 1,
      type: 'video.play',
      request_id: 'request-1',
      song: { source: 'catalog', id: '626140098' },
    });

    requests.receive({ type: 'video.started', requestId: 'request-1' });
    requests.receive({ type: 'video.started', requestId: 'request-1' });

    expect(outcomes).toEqual([{ ok: true, value: null }]);
  });

  test('a Host refusal settles with its reason and nothing is sent again', () => {
    const { requests, sent } = requestsOver();
    const outcomes: RequestOutcome<null>[] = [];

    requests.playVideo(video, (outcome) => outcomes.push(outcome));
    requests.receive({
      type: 'error',
      requestId: 'request-1',
      commandId: null,
      errorCode: 'music_unavailable',
      message: 'Music did not start this video.',
    });

    expect(outcomes).toEqual([
      {
        ok: false,
        errorCode: 'music_unavailable',
        message: 'Music did not start this video.',
      },
    ]);
    expect(sent).toHaveLength(1);
  });

  test('a reply to another request does not settle this one', () => {
    const { requests } = requestsOver();
    const outcomes: RequestOutcome<null>[] = [];

    requests.playVideo(video, (outcome) => outcomes.push(outcome));

    expect(
      requests.receive({ type: 'video.started', requestId: 'other' }),
    ).toBe(false);
    expect(outcomes).toEqual([]);
  });

  test('with no live link nothing is sent and the callback is never called', () => {
    const { requests, unlink } = requestsOver();
    const outcomes: RequestOutcome<null>[] = [];

    unlink();

    expect(
      requests.playVideo(video, (outcome) => outcomes.push(outcome)),
    ).toBeNull();
    expect(outcomes).toEqual([]);
  });
});
