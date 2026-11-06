import { defineStore } from 'pinia';
import { computed, ref, shallowRef, watch } from 'vue';
import {
  bluetoothAvailable,
  forgetBluetoothDevice,
  openBluetoothSocket,
  reconnectBluetoothLink,
  rememberBluetoothDevice,
  rememberedBluetoothDevice,
  silentReconnectSupported,
} from '~/lib/host/bluetooth';
import { reconnectWithRetries } from '~/lib/host/bluetoothReconnect';
import {
  artworkDataUrl,
  artworkStatus,
  type ArtworkStatus,
} from '~/lib/host/artwork';
import { openBrowserSocket } from '~/lib/host/browserSocket';
import {
  HostClient,
  type HostChange,
  type HostPhase,
  type SocketLike,
} from '~/lib/host/client';
import { createCredentialStore } from '~/lib/host/credentials';
import {
  defaultRemoteName,
  remoteVersion,
  socketUrlFor,
} from '~/lib/host/endpoint';
import { randomUuid } from '~/lib/host/ids';
import { describeCommandResult } from '~/lib/host/messages';
import { readInvitationSecret } from '~/lib/host/pairing';
import { lyricsLevel, type LyricsLevel } from '~/lib/lyrics';
import { positionAt } from '~/lib/playback';
import type {
  CommandAction,
  CommandResult,
  CurrentPlayback,
  LyricDocument,
  Snapshot,
} from '~/lib/protocol/types';
import { useNoticesStore } from '~/stores/notices';

interface LyricsState {
  occurrenceId: string;
  document: LyricDocument | null;
  unavailable: boolean;
}

// Artwork is kept for the current queue only so long sessions do not grow without bound.
const artworkLimit = 48;
// Motion videos are up to 8 MiB each, so only a few albums keep theirs.

const motionLimit = 4;
const progressIntervalMs = 250;

export const useHostStore = defineStore('host', () => {
  const notices = useNoticesStore();

  // A stored pairing starts in the connecting state, so the first render never shows the pairing view.
  const phase = ref<HostPhase>(
    createCredentialStore(browserStorage()).read() === null
      ? 'unpaired'
      : 'connecting',
  );

  const attempt = ref(0);
  const phaseMessage = ref<string | null>(null);

  const hostName = ref<string | null>(null);
  const remoteName = ref('');
  const capabilities = shallowRef<string[]>([]);
  const snapshot = shallowRef<Snapshot | null>(null);
  const clockOffsetMs = ref<number | null>(null);
  const clockTick = ref(0);
  const lyrics = shallowRef<LyricsState | null>(null);
  const artworks = shallowRef<Record<string, string | null>>({});
  // Motion videos by artwork URL, so an album keeps its motion across its songs. Object URLs are revoked on eviction.
  const motionVideos = shallowRef<Record<string, string>>({});
  const busyAction = ref<CommandAction['kind'] | null>(null);
  // A row that is not playing asks only for the preview, so preview and full requests are tracked apart. settledArtwork
  // holds the URLs whose full image or motion has arrived.
  const previewRequests = new Set<string>();
  const fullRequests = new Set<string>();
  const settledArtwork = new Set<string>();
  // Web Bluetooth exists only in secure contexts and Chromium-based browsers. When it is absent, pairing uses the QR.
  const bluetoothSupported = bluetoothAvailable();
  // 'searching' while the browser's device chooser and GATT connection run. 'linked' once the Host's link waits for a PIN.
  const bluetoothState = ref<'idle' | 'searching' | 'linked'>('idle');
  // Failures that need a decision open a dialog in the pairing view. Routine outcomes use a toast instead.
  const pairingFailure = ref<string | null>(null);
  let bluetoothLink: SocketLike | null = null;
  // Bumped by forgetting the browser, so a reconnect that is still retrying cannot link a forgotten Host.
  let reconnectGeneration = 0;
  let client: HostClient | null = null;
  let snapshotReceivedMs = 0;
  let ticker: ReturnType<typeof setInterval> | null = null;

  const current = computed(() => snapshot.value?.current ?? null);
  const isPlaying = computed(() => snapshot.value?.playing ?? false);
  const connected = computed(() => phase.value === 'connected');
  const queue = computed(() => snapshot.value?.queue ?? []);
  const canControl = computed(() => connected.value && current.value !== null);

  const lyricsForCurrent = computed<LyricsState | null>(() => {
    const song = current.value;
    const state = lyrics.value;

    return song !== null &&
      state !== null &&
      state.occurrenceId === song.occurrenceId
      ? state
      : null;
  });

  const lyricsDocument = computed(
    () => lyricsForCurrent.value?.document ?? null,
  );

  const lyricsStatus = computed<LyricsLevel>(() =>
    lyricsLevel(lyricsDocument.value),
  );

  const lyricsLoading = computed(
    () =>
      current.value !== null &&
      lyricsForCurrent.value !== null &&
      lyricsDocument.value === null &&
      !lyricsForCurrent.value.unavailable,
  );

  const motionUrl = computed(() => {
    const url = current.value?.song.artworkUrl ?? null;

    return url === null ? null : (motionVideos.value[url] ?? null);
  });

  // The Host-anchored position at this instant. Per-frame views, such as the lyric sweep, read it directly.
  function livePositionMs(): number {
    const song = current.value;

    if (song === null) return 0;
    const offset = clockOffsetMs.value;

    // Until the clock is known, progress continues from the local time the snapshot arrived. Holding the sample time
    // instead froze the lyrics between snapshots, which is what made them jump.
    const hostNow =
      offset === null
        ? song.sampledAtHostMs + (performance.now() - snapshotReceivedMs)
        : performance.now() + offset;

    return positionAt(song, isPlaying.value, hostNow);
  }

  // The tick re-renders the position-driven views a few times a second. It is not a network request.
  const positionMs = computed(() => {
    void clockTick.value;

    return livePositionMs();
  });

  watch(
    [isPlaying, connected],
    ([playing, online]) => {
      stopTicker();

      if (playing && online) {
        ticker = setInterval(() => {
          clockTick.value += 1;
        }, progressIntervalMs);
      }
    },
    { immediate: true },
  );

  function stopTicker(): void {
    if (ticker !== null) clearInterval(ticker);
    ticker = null;
  }

  function start(): void {
    if (client !== null) return;
    const secret = readInvitationSecret(window.location.hash);

    // The invitation is one use. Removing it from the address bar keeps it out of history and screenshots.
    if (secret !== null) {
      window.history.replaceState(
        null,
        '',
        window.location.pathname + window.location.search,
      );
    }

    client = new HostClient({
      url: socketUrlFor(window.location.href),
      remoteVersion,
      defaultName: defaultRemoteName(navigator.userAgent),
      openSocket: openBrowserSocket,
      progressiveArtwork: bluetoothSupported,
      credentials: createCredentialStore(browserStorage()),
      monotonicNow: () => performance.now(),
      schedule: scheduleTask,
      newId: randomUuid,
      onChange: handleChange,
    });
    remoteName.value = client.remoteName();

    if (bluetoothSupported) {
      const deviceId = rememberedBluetoothDevice();
      // Without a device list the browser cannot reconnect silently, so the connect button shows at once.
      const silent = deviceId !== null && silentReconnectSupported();

      if (client.startBluetooth(silent) && deviceId !== null) {
        reconnectRemembered(deviceId);
      }
    } else {
      client.start(secret);
    }
  }

  // After a reload the page reconnects without the chooser when the browser still permits the device, retrying for a
  // short while. Only a reconnect that still fails shows the connect button, never the pairing view.
  function reconnectRemembered(deviceId: string): void {
    const generation = ++reconnectGeneration;

    void reconnectWithRetries(() => reconnectBluetoothLink(deviceId)).then(
      (link) => {
        if (generation !== reconnectGeneration) {
          link?.socket.close();

          return;
        }

        if (link === null) {
          client?.bluetoothReconnectFailed();

          return;
        }

        client?.connectOverBluetooth(link.socket);
      },
    );
  }

  function retry(): void {
    if (bluetoothSupported) return;
    client?.retry();
  }

  // Must be called from a click handler: the browser allows its device chooser only in response to a user gesture.
  function findBluetoothHost(): void {
    if (client === null || bluetoothState.value !== 'idle') return;
    bluetoothState.value = 'searching';

    openBluetoothSocket().then(
      ({ socket, deviceId }) => {
        bluetoothState.value = 'idle';
        rememberBluetoothDevice(deviceId);

        if (phase.value === 'bluetooth-idle') {
          client?.connectOverBluetooth(socket);

          return;
        }

        bluetoothLink = socket;
        bluetoothState.value = 'linked';
        socket.onClose = () => {
          if (bluetoothLink !== socket) return;
          bluetoothLink = null;
          bluetoothState.value = 'idle';
          notices.show(
            'The Bluetooth link to Cadenza Host closed. Find it again to pair.',
          );
        };
      },
      (error: Error) => {
        bluetoothState.value = 'idle';
        reportBluetoothFailure(error);
      },
    );
  }

  function pairOverBluetooth(pin: string, name: string): void {
    const socket = bluetoothLink;

    if (client === null || socket === null) return;
    bluetoothLink = null;
    bluetoothState.value = 'idle';
    client.pairOverBluetooth(socket, pin, name);
  }

  function closeBluetoothLink(): void {
    const socket = bluetoothLink;

    bluetoothLink = null;
    bluetoothState.value = 'idle';
    socket?.close();
  }

  function dismissPairingFailure(): void {
    pairingFailure.value = null;
  }

  function reportBluetoothFailure(error: Error): void {
    // The chooser was dismissed, or no Host answered. Both are routine and the user can simply try again.
    if (error instanceof DOMException && error.name === 'NotFoundError') {
      notices.show(
        'No Cadenza Host was chosen. Keep Bluetooth on near the Host and try again.',
      );

      return;
    }

    pairingFailure.value =
      'Cadenza Host could not be reached over Bluetooth. Keep Bluetooth on near the Host, then try again.';
  }

  function handleChange(change: HostChange): void {
    switch (change.kind) {
      case 'phase':
        applyPhase(change.phase, change.attempt, change.message);

        return;
      case 'welcome':
        hostName.value = change.welcome.hostName;
        capabilities.value = change.welcome.capabilities;

        return;
      case 'snapshot':
        applySnapshot(change.snapshot);

        return;
      case 'clock':
        clockOffsetMs.value = change.offsetMs;

        return;
      case 'lyrics':
        lyrics.value = {
          occurrenceId: change.lyrics.occurrenceId,
          document: change.lyrics,
          unavailable: false,
        };

        return;
      case 'lyricsUnavailable':
        if (change.occurrenceId !== null) {
          lyrics.value = {
            occurrenceId: change.occurrenceId,
            document: null,
            unavailable: true,
          };
        }

        return;
      case 'artwork':
        applyArtwork(change.artworkUrl, change.dataUrl, change.full);

        return;
      case 'motion':
        showMotion(change.artworkUrl, change.video);

        return;
      case 'commandResolved':
        showCommandResult(change.result);

        return;
      case 'notice':
        notices.show(change.message);

        return;
    }
  }

  function applyPhase(
    next: HostPhase,
    nextAttempt: number,
    message: string | null,
  ): void {
    phase.value = next;
    attempt.value = nextAttempt;
    phaseMessage.value = message;

    if (next === 'connected') {
      // Requests in flight on the old socket were dropped. Clearing them lets the next snapshot ask again.
      previewRequests.clear();
      fullRequests.clear();
      lyrics.value = null;
    }

    if (next === 'pairing-failed' && bluetoothSupported) {
      pairingFailure.value = message;
    }

    if (next === 'unpaired' || next === 'pairing-failed') {
      snapshot.value = null;
      clockOffsetMs.value = null;
      lyrics.value = null;

      if (next === 'unpaired') hostName.value = null;
    }
  }

  function applySnapshot(next: Snapshot): void {
    snapshot.value = next;
    snapshotReceivedMs = performance.now();
    const song = next.current;
    // The cover arrives with the song, so it is on screen with the title. A full image already here is not replaced.
    const preview = song?.artworkPreview;
    const previewUrl = song?.song.artworkUrl ?? null;
    const previewDataUrl = preview ? artworkDataUrl(preview) : null;

    if (previewUrl !== null && previewDataUrl !== null) {
      applyArtwork(previewUrl, previewDataUrl, false);
    }

    if (song === null) {
      abandonFullArtwork(null);

      return;
    }

    const state = lyrics.value;

    if (state === null || state.occurrenceId !== song.occurrenceId) {
      lyrics.value = {
        occurrenceId: song.occurrenceId,
        document: null,
        unavailable: false,
      };
      client?.requestLyrics(song.occurrenceId);
      // A song that is no longer playing keeps no transfer, so the Host does not send its image or motion.
      abandonFullArtwork(song.occurrenceId);
      requestFullArtwork(song);
    }
  }

  function abandonFullArtwork(playingOccurrenceId: string | null): void {
    client?.cancelFullArtwork(playingOccurrenceId);
    fullRequests.clear();
  }

  // The playing song asks for its motion video in place of the full image, or for the full image when it has no motion.
  function requestFullArtwork(song: CurrentPlayback): void {
    const url = song.song.artworkUrl;

    if (
      url === null ||
      settledArtwork.has(url) ||
      fullRequests.has(url) ||
      motionVideos.value[url] !== undefined
    ) {
      return;
    }

    fullRequests.add(url);
    client?.requestArtwork(url, {
      kind: 'full',
      occurrenceId: song.occurrenceId,
    });
  }

  function applyArtwork(
    url: string,
    dataUrl: string | null,
    full: boolean,
  ): void {
    if (full) {
      fullRequests.delete(url);
      settledArtwork.add(url);
      // A full image that fails to verify keeps the preview on screen.

      if (dataUrl !== null || !(url in artworks.value)) {
        rememberArtwork(url, dataUrl);
      }

      return;
    }

    previewRequests.delete(url);

    if (!settledArtwork.has(url)) rememberArtwork(url, dataUrl);
  }

  // Motion is kept per album, so the album's next song needs no transfer. The oldest albums are evicted.
  function showMotion(
    artworkUrl: string,
    video: Uint8Array<ArrayBuffer> | null,
  ): void {
    fullRequests.delete(artworkUrl);

    if (video === null) return;

    const next = { ...motionVideos.value };
    const previous = next[artworkUrl];

    if (previous !== undefined) URL.revokeObjectURL(previous);
    delete next[artworkUrl];
    next[artworkUrl] = URL.createObjectURL(
      new Blob([video], { type: 'video/mp4' }),
    );

    for (const stale of Object.keys(next).slice(0, -motionLimit)) {
      const url = next[stale];

      if (url !== undefined) URL.revokeObjectURL(url);
      delete next[stale];
    }

    motionVideos.value = next;
  }

  function artworkStatusFor(url: string | null): ArtworkStatus {
    return artworkStatus(url, artworks.value);
  }

  function rememberArtwork(url: string, dataUrl: string | null): void {
    const next = { ...artworks.value, [url]: dataUrl };
    const urls = Object.keys(next);

    for (const stale of urls.slice(
      0,
      Math.max(0, urls.length - artworkLimit),
    )) {
      delete next[stale];
    }

    artworks.value = next;
  }

  function artworkFor(url: string | null): string | null {
    if (url === null) return null;

    return artworks.value[url] ?? null;
  }

  // Rows ask for the small preview. The playing song's full image or motion is asked for by requestFullArtwork.
  function requestArtwork(url: string): void {
    // A full request in flight does not cover the preview: one that does not run progressively sends no preview.
    if (
      url in artworks.value ||
      previewRequests.has(url) ||
      settledArtwork.has(url)
    ) {
      return;
    }

    previewRequests.add(url);
    client?.requestArtwork(url, { kind: 'preview' });
  }

  function showCommandResult(result: CommandResult): void {
    const message = describeCommandResult(result);

    if (message !== null) notices.show(message);
  }

  // A second command waits until the first returns, so repeated taps cannot queue duplicate mutations.
  async function runAction(action: CommandAction): Promise<void> {
    if (client === null || !connected.value || busyAction.value !== null)
      return;
    busyAction.value = action.kind;
    const result = await client.sendCommand(action);
    busyAction.value = null;
    showCommandResult(result);
  }

  function togglePlayback(): void {
    const song = current.value;

    if (song === null) return;
    const kind = isPlaying.value ? 'playback.pause' : 'playback.resume';
    void runAction({ kind, occurrenceId: song.occurrenceId });
  }

  function skipNext(): void {
    const song = current.value;

    if (song === null) return;
    void runAction({ kind: 'playback.skip', occurrenceId: song.occurrenceId });
  }

  function skipPrevious(): void {
    const song = current.value;

    if (song === null) return;
    void runAction({
      kind: 'playback.previous',
      occurrenceId: song.occurrenceId,
    });
  }

  function seekTo(targetMs: number): void {
    const song = current.value;

    if (song === null) return;
    const duration = song.song.durationMs ?? targetMs;

    const positionMsValue = Math.round(
      Math.min(Math.max(0, targetMs), duration),
    );

    void runAction({
      kind: 'playback.seek',
      occurrenceId: song.occurrenceId,
      positionMs: positionMsValue,
    });
  }

  async function setVolume(percent: number): Promise<void> {
    if (client === null || !connected.value) return;

    const result = await client.sendCommand({
      kind: 'playback.volume',
      percent: Math.round(Math.min(100, Math.max(0, percent))),
    });

    showCommandResult(result);
  }

  function renameRemote(name: string): void {
    client?.renameRemote(name);
    remoteName.value = name;
  }

  function forgetBrowser(): void {
    reconnectGeneration += 1;
    closeBluetoothLink();
    forgetBluetoothDevice();
    client?.forget();
    remoteName.value = '';
  }

  return {
    livePositionMs,
    phase,
    attempt,
    phaseMessage,
    hostName,
    remoteName,
    capabilities,
    snapshot,
    current,
    isPlaying,
    connected,
    canControl,
    queue,
    positionMs,
    lyricsDocument,
    lyricsStatus,
    lyricsLoading,
    busyAction,
    artworkFor,
    artworkStatusFor,
    motionUrl,
    requestArtwork,
    bluetoothSupported,
    bluetoothState,
    pairingFailure,
    findBluetoothHost,
    pairOverBluetooth,
    closeBluetoothLink,
    dismissPairingFailure,
    start,
    retry,
    togglePlayback,
    skipNext,
    skipPrevious,
    seekTo,
    setVolume,
    renameRemote,
    forgetBrowser,
  };
});

function scheduleTask(callback: () => void, delayMs: number): () => void {
  const handle = setTimeout(callback, delayMs);

  return () => clearTimeout(handle);
}

function browserStorage(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}
