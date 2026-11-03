import { computed, ref } from 'vue';
import { defineStore } from 'pinia';
import type {
  ConnectionState,
  PairingState,
  Snapshot,
  TransportKind,
  TransportStatus,
} from '~/types/protocol';

const initialSnapshot: Snapshot = {
  revision: 18,
  current: {
    id: 'song-001',
    title: 'Breathe Deeper',
    artist: 'Tame Impala',
    album: 'The Slow Rush',
    artwork:
      'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&w=900&q=85',
    durationSeconds: 372,
  },
  positionSeconds: 126,
  isPlaying: true,
  lyricsAvailable: true,
  queue: [
    {
      id: 'song-002',
      requestId: 'request-102',
      title: 'Borderline',
      artist: 'Tame Impala',
      album: 'The Slow Rush',
      artwork:
        'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&w=240&q=80',
      durationSeconds: 237,
      requester: 'Mia’s Remote',
      waitLabel: 'in 6 min',
    },
    {
      id: 'song-003',
      requestId: 'request-103',
      title: 'The Less I Know The Better',
      artist: 'Tame Impala',
      album: 'Currents',
      artwork:
        'https://images.unsplash.com/photo-1524368535928-5b5e00ddc76b?auto=format&fit=crop&w=240&q=80',
      durationSeconds: 216,
      requester: 'Alex’s Remote',
      waitLabel: 'in 10 min',
    },
  ],
};

export const useSessionStore = defineStore('session', () => {
  const state = ref<ConnectionState>('connected');
  const activeTransport = ref<TransportKind>('webrtc');
  const snapshot = ref<Snapshot>(initialSnapshot);
  const toast = ref<string | null>(null);
  const pairingVisible = ref(false);
  const pairingState = ref<PairingState>('idle');
  const isBusy = ref(false);

  const transport: TransportStatus = {
    kind: 'webrtc',
    label: 'WebRTC',
    state: 'connected',
    detail: 'Direct on your local network',
  };

  const status = computed<TransportStatus>(() => ({
    ...transport,
    kind: activeTransport.value,
    state: state.value,
  }));

  const progress = computed(() => {
    const current = snapshot.value.current;

    return current
      ? Math.min(
          100,
          (snapshot.value.positionSeconds / current.durationSeconds) * 100,
        )
      : 0;
  });

  function notify(message: string) {
    toast.value = message;
    window.setTimeout(() => {
      if (toast.value === message) toast.value = null;
    }, 2800);
  }

  async function togglePlayback() {
    if (state.value !== 'connected' || isBusy.value) return;
    isBusy.value = true;
    await new Promise((resolve) => window.setTimeout(resolve, 220));
    snapshot.value.isPlaying = !snapshot.value.isPlaying;
    isBusy.value = false;
    notify(snapshot.value.isPlaying ? 'Playback resumed' : 'Playback paused');
  }

  function selectTransport(kind: TransportKind) {
    activeTransport.value = kind;
    notify(`${kind === 'webrtc' ? 'WebRTC' : kind.toUpperCase()} selected`);
  }

  function setUnreachable() {
    state.value = 'unreachable';
    notify(
      'Host is unreachable. Check that Cadenza is running on your network.',
    );
  }

  function openPairing() {
    pairingState.value = 'idle';
    pairingVisible.value = true;
  }

  async function pairBrowser() {
    pairingState.value = 'scanning';
    await new Promise((resolve) => window.setTimeout(resolve, 650));
    pairingState.value = 'paired';
    state.value = 'connected';
    pairingVisible.value = false;
    notify('This browser is paired with Cadenza Host');
  }

  return {
    state,
    activeTransport,
    snapshot,
    toast,
    pairingVisible,
    pairingState,
    isBusy,
    status,
    progress,
    togglePlayback,
    selectTransport,
    setUnreachable,
    openPairing,
    pairBrowser,
  };
});
