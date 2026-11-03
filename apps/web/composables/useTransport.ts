import { computed, type Ref } from 'vue';
import type {
  CommandPayload,
  RemoteTransport,
  TransportKind,
} from '~/types/protocol';

class BrowserTransport implements RemoteTransport {
  constructor(public readonly kind: TransportKind) {}

  async connect() {
    return Promise.resolve();
  }

  close() {}

  async send(command: string, payload: CommandPayload) {
    return {
      commandId: `${command}-${Date.now()}`,
      outcome: 'accepted' as const,
      message: `Queued ${command} with ${Object.keys(payload).length} fields`,
    };
  }
}

export function useTransport(kind: Ref<TransportKind>) {
  const transport = computed(() => new BrowserTransport(kind.value));

  return { transport };
}
