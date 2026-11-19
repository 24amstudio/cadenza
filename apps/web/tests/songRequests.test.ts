import { describe, expect, test } from 'bun:test';
import {
  SongRequests,
  type RequestOutcome,
} from '../app/lib/host/songRequests';
import type { Song } from '../app/lib/protocol/types';
import {
  Clock,
  answerClockProbes,
  harness,
  playingSnapshotFrame,
  socketAt,
  token,
  welcome,
} from './support/hostClient';

const song: Song = {
  source: 'catalog',
  id: '1440857781',
  title: 'Breathe Deeper',
  artist: 'Tame Impala',
  album: 'The Slow Rush',
  durationMs: 372_000,
  artworkUrl: null,
};

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
    clock,
    sent,
    unlink: () => {
      linked = false;
    },
  };
}

describe('song requests', () => {
  test('a search is sent once and settles once with the Host reply', () => {
    const { requests, sent } = requestsOver();
    const outcomes: RequestOutcome<Song[]>[] = [];

    const id = requests.search('Breathe', 'catalog', (outcome) =>
      outcomes.push(outcome),
    );

    expect(id).toBe('request-1');
    expect(sent).toHaveLength(1);
    expect(
      requests.receive({
        type: 'search.result',
        requestId: 'request-1',
        songs: [song],
      }),
    ).toBe(true);
    // A second answer for the same request is not a second result.
    expect(
      requests.receive({
        type: 'search.result',
        requestId: 'request-1',
        songs: [song],
      }),
    ).toBe(false);
    expect(outcomes).toEqual([{ ok: true, value: [song] }]);
  });

  test('a refusal from the Host settles with its own code and message', () => {
    const { requests } = requestsOver();
    const outcomes: RequestOutcome<Song[]>[] = [];

    requests.search('Breathe', 'library', (outcome) => outcomes.push(outcome));
    requests.receive({
      type: 'error',
      requestId: 'request-1',
      commandId: null,
      errorCode: 'busy',
      message: 'Too many searches are running.',
    });

    expect(outcomes).toEqual([
      {
        ok: false,
        errorCode: 'busy',
        message: 'Too many searches are running.',
      },
    ]);
  });

  test('a request the Host never answers times out, and a late reply is ignored', () => {
    const { requests, clock } = requestsOver();
    const outcomes: RequestOutcome<null>[] = [];

    requests.prepare({ source: 'catalog', id: '1440857781' }, (outcome) =>
      outcomes.push(outcome),
    );
    clock.advance(20_000);

    expect(outcomes).toHaveLength(1);
    expect(outcomes[0]?.ok).toBe(false);
    expect(
      requests.receive({ type: 'song.ready', requestId: 'request-1' }),
    ).toBe(false);
    expect(outcomes).toHaveLength(1);
  });

  test('a closed link fails every open request, and nothing is sent again', () => {
    const { requests, sent } = requestsOver();
    const outcomes: RequestOutcome<Song[]>[] = [];

    requests.search('Breathe', 'catalog', (outcome) => outcomes.push(outcome));
    requests.abandon();

    expect(sent).toHaveLength(1);
    expect(outcomes).toEqual([
      {
        ok: false,
        errorCode: 'unavailable',
        message: 'Cadenza Host is not connected.',
      },
    ]);
  });

  test('a cancelled request ignores the reply that still arrives', () => {
    const { requests } = requestsOver();
    const outcomes: RequestOutcome<Song[]>[] = [];

    const id = requests.search('Breathe', 'catalog', (outcome) =>
      outcomes.push(outcome),
    );

    if (id !== null) requests.cancel(id);

    expect(
      requests.receive({
        type: 'search.result',
        requestId: 'request-1',
        songs: [song],
      }),
    ).toBe(false);
    expect(outcomes).toEqual([]);
  });

  test('nothing is sent or reported while the link is not ready', () => {
    const { requests, sent, unlink } = requestsOver();
    const outcomes: RequestOutcome<Song[]>[] = [];

    unlink();

    expect(
      requests.search('Breathe', 'catalog', (outcome) =>
        outcomes.push(outcome),
      ),
    ).toBeNull();
    expect(sent).toEqual([]);
    expect(outcomes).toEqual([]);
  });
});

describe('song requests over the client link', () => {
  function connected() {
    const setup = harness();
    const socket = () => socketAt(setup.sockets, 0);

    setup.client.start('S'.repeat(43));
    socket().open();
    socket().receive(welcome(token));
    socket().receive(playingSnapshotFrame(18));
    answerClockProbes(socket(), setup.clock);

    return { ...setup, socket };
  }

  test('a search reply reaches the request that asked for it', () => {
    const { client, socket } = connected();
    const outcomes: RequestOutcome<Song[]>[] = [];

    client.songs.search('Breathe', 'catalog', (outcome) =>
      outcomes.push(outcome),
    );
    const request = socket().framesOfType('search')[0];

    socket().receive({
      type: 'search.result',
      request_id: request?.request_id,
      songs: [
        {
          source: 'catalog',
          id: '1440857781',
          title: 'Breathe Deeper',
          artist: 'Tame Impala',
          album: 'The Slow Rush',
          duration_ms: 372000,
        },
      ],
    });

    expect(outcomes).toEqual([{ ok: true, value: [song] }]);
  });

  test('a search open on a link that drops fails, and the reconnect does not send it again', () => {
    const { client, socket, sockets, clock } = connected();
    const outcomes: RequestOutcome<Song[]>[] = [];

    client.songs.search('Breathe', 'catalog', (outcome) =>
      outcomes.push(outcome),
    );
    socket().serverDrop();
    clock.advance(30_000);
    socketAt(sockets, 1).open();
    socketAt(sockets, 1).receive(welcome(token));

    expect(outcomes).toHaveLength(1);
    expect(outcomes[0]?.ok).toBe(false);
    const searches = sockets.flatMap((item) => item.framesOfType('search'));

    expect(searches).toHaveLength(1);
  });
});
