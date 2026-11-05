import { expect, spyOn, test } from 'bun:test';
import { traceFrame } from '../app/lib/host/trace';

test('pairing secrets and payload bytes never reach the console', () => {
  const debug = spyOn(console, 'debug').mockImplementation(() => {});

  try {
    traceFrame(
      'out',
      'bluetooth',
      JSON.stringify({
        type: 'pair',
        pair: { pin: '4821', name: 'Mac', remote_version: 'cadenza-web 1' },
      }),
    );
    traceFrame(
      'out',
      'websocket',
      JSON.stringify({
        type: 'hello',
        auth: { remote_id: 'remote-1', token: 'hello-token-value' },
      }),
    );
    traceFrame(
      'in',
      'bluetooth',
      JSON.stringify({
        type: 'artwork.chunk',
        request_id: 'art-1',
        data_base64: 'QUJDRA==',
      }),
    );

    const logged = JSON.stringify(debug.mock.calls);

    expect(logged).not.toContain('4821');
    expect(logged).not.toContain('hello-token-value');
    expect(logged).not.toContain('QUJDRA==');
    expect(logged).toContain('Mac');
    expect(logged).toContain('8 base64 characters');
  } finally {
    debug.mockRestore();
  }
});

test('a frame that is not JSON is logged by length and does not throw', () => {
  const debug = spyOn(console, 'debug').mockImplementation(() => {});

  try {
    expect(() => traceFrame('in', 'websocket', '{not json')).not.toThrow();
    expect(JSON.stringify(debug.mock.calls)).toContain('unparseable');
  } finally {
    debug.mockRestore();
  }
});
