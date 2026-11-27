import { afterEach, expect, test } from 'bun:test';
import { RemoteAudioReceiver } from '../app/lib/remoteAudio/receiver';

const realAudioContext = globalThis.AudioContext;

afterEach(() => {
  Reflect.set(globalThis, 'AudioContext', realAudioContext);
});

// A project Pages site serves the app under /<repository>/, so the worklet must load beside the app, not from the origin
// root. The stub fails the module request, which stops start() before any socket opens.
test('the Remote requests its worklet under the app base path', async () => {
  const requested: string[] = [];
  const stop = new Error('stop after the worklet request');

  Reflect.set(
    globalThis,
    'AudioContext',
    class {
      audioWorklet = {
        addModule: async (url: string) => {
          requested.push(url);
          throw stop;
        },
      };
    },
  );

  const receiver = new RemoteAudioReceiver('ws://192.168.1.5:7878/v1/socket', {
    clientId: 'remote-1',
    token: 'paired-token-0123456789',
  });

  await expect(receiver.start('/cadenza/')).rejects.toBe(stop);
  expect(requested).toEqual(['/cadenza/remote-audio-worklet.js']);
});
