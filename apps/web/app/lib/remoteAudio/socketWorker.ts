import type { RemoteAudioSettings } from './config';
import {
  RemoteAudioSocketCore,
  type RemoteAudioCredentials,
  type RemoteAudioOutput,
  type RemoteAudioStatus,
} from './socketCore';
import type { OutputClockSample } from './timeline';
import { openRemoteAudioSocket } from './socketTransport';

export type SocketWorkerInbound =
  | {
      type: 'start';
      url: string;
      credentials: RemoteAudioCredentials;
      output: RemoteAudioOutput;
      port: MessagePort;
    }
  | { type: 'config'; settings: RemoteAudioSettings }
  | { type: 'command'; action: 'new_environment' }
  | { type: 'clock'; sample: OutputClockSample }
  | { type: 'longTasks'; ms: number }
  | { type: 'stop' };

export type SocketWorkerOutbound = {
  type: 'status';
  patch: Partial<RemoteAudioStatus>;
};

interface WorkletMessage {
  type: string;
  dropped?: number;
  concealed?: number;
  underrun?: number;
}

interface WorkerScope {
  postMessage(message: SocketWorkerOutbound): void;
  onmessage: ((event: MessageEvent<SocketWorkerInbound>) => void) | null;
}

const scope: WorkerScope = self;

let core: RemoteAudioSocketCore | null = null;

scope.onmessage = (event) => {
  const message = event.data;

  switch (message.type) {
    case 'start':
      start(message.url, message.credentials, message.output, message.port);
      break;
    case 'config':
      core?.sendConfig(message.settings);
      break;
    case 'command':
      core?.sendCommand(message.action);
      break;
    case 'clock':
      core?.setOutputClock(message.sample);
      break;
    case 'longTasks':
      core?.addLongTaskMs(message.ms);
      break;
    case 'stop':
      core?.stop();
      core = null;
      break;
  }
};

function start(
  url: string,
  credentials: RemoteAudioCredentials,
  output: RemoteAudioOutput,
  port: MessagePort,
): void {
  port.onmessage = (event: MessageEvent<WorkletMessage>) => {
    if (event.data.type !== 'stats') return;
    core?.receivePlayoutCounts({
      dropped: event.data.dropped ?? 0,
      concealed: event.data.concealed ?? 0,
      underrun: event.data.underrun ?? 0,
    });
  };

  core = new RemoteAudioSocketCore({
    connect: (address) => openRemoteAudioSocket(address),
    port,
    now: () => performance.timeOrigin + performance.now(),
    emit: (patch) => scope.postMessage({ type: 'status', patch }),
  });
  core.start(url, credentials, output);
}
