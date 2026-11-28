import { afterEach, expect, test } from 'bun:test';
import type { RemoteAudioSettings } from '../app/lib/remoteAudio/config';
import { RemoteAudioReceiver } from '../app/lib/remoteAudio/receiver';
import type { SocketWorkerInbound } from '../app/lib/remoteAudio/socketWorker';

const realAudioContext = globalThis.AudioContext;
const realAudioWorkletNode = globalThis.AudioWorkletNode;
const realWorker = globalThis.Worker;

afterEach(() => {
  Reflect.set(globalThis, 'AudioContext', realAudioContext);
  Reflect.set(globalThis, 'AudioWorkletNode', realAudioWorkletNode);
  Reflect.set(globalThis, 'Worker', realWorker);
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

test('settings reach the socket worker as plain data when read from reactive state', async () => {
  const posted: SocketWorkerInbound[] = [];

  Reflect.set(
    globalThis,
    'AudioContext',
    class {
      baseLatency = 0;
      outputLatency = 0;
      destination = {};
      audioWorklet = { addModule: async () => {} };
      async resume() {}
      async close() {}
    },
  );
  Reflect.set(
    globalThis,
    'AudioWorkletNode',
    class {
      port = { postMessage() {} };
      connect() {}
      disconnect() {}
    },
  );
  Reflect.set(
    globalThis,
    'Worker',
    class {
      postMessage(message: SocketWorkerInbound, transfer: Transferable[] = []) {
        posted.push(structuredClone(message, { transfer }));
      }
      terminate() {}
    },
  );

  const settings: RemoteAudioSettings = {
    enabled: true,
    streamMode: 'crossover_split',
    crossoverHz: 80,
    subGainDb: 0,
    phaseInvert: false,
    manualDistanceOffsetMs: 0,
  };

  const receiver = new RemoteAudioReceiver('ws://192.168.1.5:7878/v1/socket', {
    clientId: 'remote-1',
    token: 'paired-token-0123456789',
  });

  await receiver.start('/');
  receiver.sendConfig(new Proxy(settings, {}));
  receiver.stop();

  expect(posted.at(-1)).toEqual({ type: 'config', settings });
});
