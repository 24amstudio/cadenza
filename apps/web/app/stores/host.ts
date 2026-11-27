import { defineStore } from 'pinia';
import { computed, ref, shallowRef, watch, type Ref } from 'vue';
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
import { reloadForNewerHostBundle } from '~/lib/bundleReload';
import { signalBars } from '~/lib/host/linkSignal';
import {
  artworkDataUrl,
  artworkStatus,
  type ArtworkStatus,
} from '~/lib/host/artwork';
import { ArtworkAlbums } from '~/lib/host/artworkAlbums';
import { ArtworkCoordinator } from '~/lib/host/artworkCoordinator';
import { TrafficPulses } from '~/lib/host/trafficPulses';
import { unavailableResult } from '~/lib/host/commandTracker';
import { ControlQueue, type ControlKey } from '~/lib/host/controlQueue';
import { libraryHostCommands } from '~/lib/host/hostCommands';
import { prefetchNextCover } from '~/lib/host/nextCover';
import { openBrowserSocket } from '~/lib/host/browserSocket';
import {
  HostClient,
  type HostChange,
  type HostPhase,
  type Readiness,
  type SocketLike,
} from '~/lib/host/client';
import { createCredentialStore } from '~/lib/host/credentials';
import {
  defaultRemoteName,
  remoteVersion,
  socketUrlFor,
} from '~/lib/host/endpoint';
import { browserStorage } from '~/lib/host/browserStorage';
import { randomUuid } from '~/lib/host/ids';
import { currentTasteDigest } from '~/lib/tasteDigestSource';
import { describeCommandResult } from '~/lib/host/messages';
import { readInvitationSecret } from '~/lib/host/pairing';
import type { Settle } from '~/lib/host/songRequests';
import type { SongDetails } from '~/lib/protocol/encode';
import { lyricsLevel, type LyricsLevel } from '~/lib/lyrics';
import { positionAt } from '~/lib/playback';
import { nextRepeat } from '~/lib/playbackModes';
import { reuseUnchanged } from '~/lib/snapshotIdentity';
import type {
  BrowsePage,
  BrowseRequest,
  CommandResult,
  HostUpdateStatus,
  LyricDocument,
  QueueActionKind,
  RepeatMode,
  SearchScope,
  Snapshot,
  Song,
  SongIdentity,
  RecommendationShelfItem,
  SongSuggestions,
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

// How long the slider keeps the value it sent while the Host's own volume catches up.
const volumeSettleMs = 2_000;

const defaultVolume = 50;

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
  const hostVersion = ref<string | null>(null);
  const hostUpdate = shallowRef<HostUpdateStatus | null>(null);
  const snapshot = shallowRef<Snapshot | null>(null);
  const clockOffsetMs = ref<number | null>(null);
  const clockTick = ref(0);
  const linkRoundTripMs = ref<number | null>(null);
  const traffic = new TrafficPulses();
  const lyrics = shallowRef<LyricsState | null>(null);
  const artworks = shallowRef<Record<string, string | null>>({});

  // Every track of an album shows one cover, so the cover already held stands in for the album's other songs.
  const albums = new ArtworkAlbums(
    (url) => (artworks.value[url] ?? null) !== null,
  );

  // Motion videos by artwork URL, so an album keeps its motion across its songs. Object URLs are revoked on eviction.
  const motionVideos = shallowRef<Record<string, string>>({});
  // The controls with a command queued or in flight. A control shows its own pending state while it is in here.
  const pendingControls = ref<ReadonlySet<ControlKey>>(new Set());
  // The volume the slider last sent, shown until the Host reports it. Null means the Host's own value is shown.
  const volumeTarget = ref<number | null>(null);
  // The shuffle and repeat the buttons last sent, shown until the Host reports them, like the volume.
  const shuffleTarget = ref<boolean | null>(null);
  const repeatTarget = ref<RepeatMode | null>(null);
  // A hidden page has no one to show progress to, so its tick stops until the page is visible again.
  const pageVisible = ref(!document.hidden);
  let lastAudibleVolume = defaultVolume;
  let volumeSettleTimer: ReturnType<typeof setTimeout> | null = null;
  let lastVolumeResult: CommandResult | null = null;
  // URLs whose image is the full one rather than the 32 pixel preview. A preview never replaces them.
  const fullImages = new Set<string>();
  // Web Bluetooth exists only in secure contexts and Chromium-based browsers. Where it exists the link is Bluetooth.
  // Where it is absent, pairing uses the QR and the link is the Host's WebSocket.
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

  const artwork = new ArtworkCoordinator(
    {
      support: () => client?.artworkSupport() ?? 'offline',
      supportsMotion: () => client?.supportsMotion() ?? false,
      request: (url, mode) => client?.requestArtwork(url, mode) ?? null,
      cancel: (requestId) => client?.cancelArtwork(requestId),
    },
    {
      hasImage: (url) => (artworks.value[albums.shown(url)] ?? null) !== null,
      hasFullImage: (url) => {
        const shown = albums.shown(url);

        return (
          fullImages.has(shown) && (artworks.value[shown] ?? null) !== null
        );
      },
      hasMotion: (url) => motionVideos.value[albums.shown(url)] !== undefined,
      markUnavailable: (url) => {
        if (!(url in artworks.value)) rememberArtwork(url, null);
      },
    },
    scheduleTask,
    () => performance.now(),
  );

  const controls = new ControlQueue(
    {
      awaitReadiness: (timeoutMs) =>
        client?.awaitReadiness(timeoutMs) ??
        Promise.resolve<Readiness>('offline'),
      awaitRevision: (minRevision, timeoutMs) =>
        client?.awaitRevision(minRevision, timeoutMs) ?? Promise.resolve(),
      latestSnapshot: () => client?.latestSnapshot() ?? null,
      send: (action) =>
        client?.sendCommand(action) ?? Promise.resolve(unavailableResult()),
      wait: (ms) => new Promise((resolve) => scheduleTask(resolve, ms)),
    },
    {
      pendingChanged: (pending) => {
        const hadVolume = pendingControls.value.has('volume');
        pendingControls.value = pending;

        if (hadVolume && !pending.has('volume')) settleVolume();
      },
      finished: (key, result) => {
        if (key === 'volume') lastVolumeResult = result;

        if (key === 'shuffle') {
          releaseTarget(shuffleTarget, () => snapshot.value?.shuffle, result);
        }

        if (key === 'repeat') {
          releaseTarget(repeatTarget, () => snapshot.value?.repeat, result);
        }

        showCommandResult(result);
      },
      notice: (message) => notices.show(message),
    },
  );

  watch(
    () => snapshot.value?.volume,
    (level) => {
      if (level !== undefined && level > 0) lastAudibleVolume = level;

      if (
        level === volumeTarget.value &&
        !pendingControls.value.has('volume')
      ) {
        volumeTarget.value = null;
      }
    },
  );

  watch(
    () => snapshot.value?.shuffle,
    (enabled) => {
      if (enabled === shuffleTarget.value) shuffleTarget.value = null;
    },
  );

  watch(
    () => snapshot.value?.repeat,
    (mode) => {
      if (mode === repeatTarget.value) repeatTarget.value = null;
    },
  );

  const current = computed(() => snapshot.value?.current ?? null);
  const isPlaying = computed(() => snapshot.value?.playing ?? false);
  const connected = computed(() => phase.value === 'connected');

  const linkBars = computed(() =>
    signalBars({
      connected: connected.value,
      roundTripMs: linkRoundTripMs.value,
    }),
  );

  const queue = computed(() => snapshot.value?.queue ?? []);
  const autoPlay = computed(() => snapshot.value?.autoPlay ?? []);
  const quality = computed(() => snapshot.value?.quality ?? 'unknown');

  const totalRemainingMs = computed(
    () => snapshot.value?.totalRemainingMs ?? null,
  );

  const canControl = computed(() => connected.value && current.value !== null);

  const supportsBrowse = computed(() =>
    capabilities.value.includes('library.browse'),
  );

  const supportsModes = computed(() =>
    capabilities.value.includes('playback.modes'),
  );

  const shuffleEnabled = computed(
    () => shuffleTarget.value ?? snapshot.value?.shuffle ?? false,
  );

  const repeatMode = computed<RepeatMode>(
    () => repeatTarget.value ?? snapshot.value?.repeat ?? 'off',
  );

  // The level shown by every volume control: what was just sent, otherwise what the Host reports.
  const volumePercent = computed(
    () => volumeTarget.value ?? snapshot.value?.volume ?? 0,
  );

  const muted = computed(() => volumePercent.value === 0);

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

    return url === null
      ? null
      : (motionVideos.value[albums.shown(url)] ?? null);
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
    [isPlaying, connected, pageVisible],
    ([playing, online, visible]) => {
      stopTicker();

      if (playing && online && visible) {
        clockTick.value += 1;
        ticker = setInterval(() => {
          clockTick.value += 1;
        }, progressIntervalMs);
      }
    },
    { immediate: true },
  );

  document.addEventListener('visibilitychange', () => {
    pageVisible.value = !document.hidden;
  });

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
      tasteDigest: currentTasteDigest,
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
        hostVersion.value = change.welcome.hostVersion;
        reloadForNewerHostBundle(change.welcome.hostVersion);

        return;
      case 'hostUpdate':
        hostUpdate.value = change.status;

        return;
      case 'snapshot':
        applySnapshot(change.snapshot);

        return;
      case 'clock':
        clockOffsetMs.value = change.offsetMs;
        linkRoundTripMs.value = change.roundTripMs;

        return;
      case 'traffic':
        traffic.record(change.direction, performance.now());

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
        artwork.artworkArrived(
          change.requestId,
          change.full,
          change.dataUrl !== null,
        );

        return;
      case 'motion':
        showMotion(change.artworkUrl, change.video);
        artwork.motionArrived(
          change.requestId,
          change.video !== null,
          change.unavailable,
        );

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
      // Requests in flight on the old socket were dropped, so artwork that is still missing is asked for again.
      lyrics.value = null;
      artwork.connected();
    } else {
      artwork.disconnected();
    }

    if (next === 'pairing-failed' && bluetoothSupported) {
      pairingFailure.value = message;
    }

    if (next === 'unpaired' || next === 'pairing-failed') {
      snapshot.value = null;
      clockOffsetMs.value = null;
      linkRoundTripMs.value = null;
      lyrics.value = null;
      artwork.setPlaying(null);

      if (next === 'unpaired') {
        hostName.value = null;
        hostVersion.value = null;
        hostUpdate.value = null;
      }
    }
  }

  function applySnapshot(received: Snapshot): void {
    const next = reuseUnchanged(snapshot.value, received);

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

    if (song !== null) albums.note(song.song);
    const upNext = next.queue[0]?.song;

    if (upNext !== undefined) albums.note(upNext);

    // Every snapshot, not only a song change, so a still or motion video that failed is asked for again.
    artwork.setPlaying(
      song === null
        ? null
        : {
            url:
              song.song.artworkUrl === null
                ? null
                : albums.shown(song.song.artworkUrl),
            occurrenceId: song.occurrenceId,
          },
    );
    // The next request's cover starts now, so it is on screen when its song begins.

    prefetchNextCover(
      artwork,
      albums,
      upNext?.artworkUrl,
      snapshot.value?.hostBudget,
    );

    if (song === null) return;
    const state = lyrics.value;

    if (state === null || state.occurrenceId !== song.occurrenceId) {
      lyrics.value = {
        occurrenceId: song.occurrenceId,
        document: null,
        unavailable: false,
      };
      client?.requestLyrics(song.occurrenceId);
    }
  }

  // A full image replaces the preview. A preview never replaces a full image, and a failure replaces neither.
  function applyArtwork(
    url: string,
    dataUrl: string | null,
    full: boolean,
  ): void {
    if (dataUrl === null || artworks.value[url] === dataUrl) return;

    if (full) fullImages.add(url);
    else if (fullImages.has(url)) return;

    rememberArtwork(url, dataUrl);

    if (full) albums.delivered(url);
  }

  // Motion is kept per album, so the album's next song needs no transfer. The oldest albums are evicted.
  function showMotion(
    artworkUrl: string,
    video: Uint8Array<ArrayBuffer> | null,
  ): void {
    if (video === null) return;

    const key = albums.shown(artworkUrl);
    const next = { ...motionVideos.value };
    const previous = next[key];

    if (previous !== undefined) URL.revokeObjectURL(previous);
    delete next[key];
    next[key] = URL.createObjectURL(new Blob([video], { type: 'video/mp4' }));

    for (const stale of Object.keys(next).slice(0, -motionLimit)) {
      const url = next[stale];

      if (url !== undefined) URL.revokeObjectURL(url);
      delete next[stale];
    }

    motionVideos.value = next;
  }

  function artworkStatusFor(url: string | null): ArtworkStatus {
    return artworkStatus(
      url === null ? null : albums.shown(url),
      artworks.value,
    );
  }

  function rememberArtwork(url: string, dataUrl: string | null): void {
    const next = { ...artworks.value, [url]: dataUrl };
    const urls = Object.keys(next);

    for (const stale of urls.slice(
      0,
      Math.max(0, urls.length - artworkLimit),
    )) {
      delete next[stale];
      fullImages.delete(stale);
    }

    artworks.value = next;
  }

  function artworkFor(url: string | null): string | null {
    if (url === null) return null;

    return artworks.value[albums.shown(url)] ?? null;
  }

  // Rows ask for the small preview. The playing song's full image and motion are asked for from each snapshot.
  function requestArtwork(url: string): void {
    artwork.wantPreview(url);
  }

  function showCommandResult(result: CommandResult): void {
    const message = describeCommandResult(result);

    if (message !== null) notices.show(message);
  }

  function toggleShuffle(): void {
    const enabled = !shuffleEnabled.value;

    shuffleTarget.value = enabled;
    controls.press({ key: 'shuffle', enabled });
  }

  function cycleRepeat(): void {
    const mode = nextRepeat(repeatMode.value);

    repeatTarget.value = mode;
    controls.press({ key: 'repeat', mode });
  }

  function togglePlayback(): void {
    controls.press({ key: 'toggle' });
  }

  function skipNext(): void {
    controls.press({ key: 'next' });
  }

  function skipPrevious(): void {
    controls.press({ key: 'previous' });
  }

  function seekTo(targetMs: number): void {
    const song = current.value;

    if (song === null) return;
    const duration = song.song.durationMs ?? targetMs;

    controls.press({
      key: 'seek',
      positionMs: Math.round(Math.min(Math.max(0, targetMs), duration)),
      occurrenceId: song.occurrenceId,
    });
  }

  // The slider shows the new level at once. Presses made while a command is in flight are folded into the latest level.
  function setVolume(percent: number): void {
    const level = Math.round(Math.min(100, Math.max(0, percent)));

    if (volumeSettleTimer !== null) clearTimeout(volumeSettleTimer);
    volumeSettleTimer = null;

    if (level > 0) lastAudibleVolume = level;
    volumeTarget.value = level;
    controls.press({ key: 'volume', percent: level });
  }

  // Mute returns to the level it replaced, which is remembered locally because the Host reports only the current one.
  function toggleMute(): void {
    if (volumePercent.value > 0) lastAudibleVolume = volumePercent.value;
    setVolume(volumePercent.value > 0 ? 0 : lastAudibleVolume);
  }

  // After the last volume command finished, the slider returns to the Host's value: at once when the change failed, and
  // when the Host reports it or after a short wait when it applied.
  function settleVolume(): void {
    const result = lastVolumeResult;

    if (
      result?.outcome !== 'applied' ||
      snapshot.value?.volume === volumeTarget.value
    ) {
      volumeTarget.value = null;

      return;
    }

    volumeSettleTimer = setTimeout(() => {
      volumeTarget.value = null;
      volumeSettleTimer = null;
    }, volumeSettleMs);
  }

  // Search and preparation are answered once or not at all. A null return means nothing was sent.
  function searchSongs(
    query: string,
    scope: SearchScope,
    settle: Settle<Song[]>,
  ): string | null {
    return client?.songs.search(query, scope, settle) ?? null;
  }

  // Suggestions need the Host to advertise them, so an older Host simply shows none.
  function suggestSongs(
    query: string,
    settle: Settle<SongSuggestions>,
  ): string | null {
    if (!capabilities.value.includes('search.suggest')) return null;

    return client?.songs.suggest(query, settle) ?? null;
  }

  function cancelSongRequest(requestId: string): void {
    client?.songs.cancel(requestId);
  }

  // Browse is answered once or not at all, like search. A null return means nothing was sent.
  function browse(
    request: BrowseRequest,
    settle: Settle<BrowsePage>,
  ): string | null {
    if (!supportsBrowse.value) return null;

    return client?.songs.browse(request, settle) ?? null;
  }

  function abortBrowse(requestId: string): void {
    client?.songs.abort(requestId);
  }

  function prepareSong(
    song: SongIdentity,
    settle: Settle<null>,
    details?: SongDetails,
  ): boolean {
    return (client?.songs.prepare(song, settle, details) ?? null) !== null;
  }

  // A request goes through the same queue as a playback press, so it is sent once, against the newest state. settled
  // gets null when nothing was sent; the queue has already said why.
  function requestHostUpdate(action: 'check' | 'install'): void {
    client?.requestHostUpdate(action);
  }

  function queueSong(
    song: SongIdentity,
    kind: QueueActionKind,
    settled: (result: CommandResult | null) => void,
  ): void {
    controls.press({ key: 'queue', kind, song, settled });
  }

  const hostCommands = libraryHostCommands(controls.pressHost.bind(controls));

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
    hostVersion,
    hostUpdate,
    requestHostUpdate,
    snapshot,
    current,
    isPlaying,
    connected,
    linkBars,
    linkOverBluetooth: bluetoothSupported,
    rxPulse: traffic.incoming,
    txPulse: traffic.outgoing,
    canControl,
    supportsBrowse,
    supportsModes,
    shuffleEnabled,
    repeatMode,
    queue,
    autoPlay,
    quality,
    totalRemainingMs,
    positionMs,
    lyricsDocument,
    lyricsStatus,
    lyricsLoading,
    pendingControls,
    volumePercent,
    muted,
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
    ...hostCommands,
    toggleMute,
    toggleShuffle,
    cycleRepeat,
    searchSongs,
    suggestSongs,
    shelf: (settle: Settle<RecommendationShelfItem[]>) =>
      client?.songs.shelves(settle) ?? null,
    artistMotion: (artistName: string) =>
      client?.artistMotion.request(artistName) ?? Promise.resolve(null),
    cancelSongRequest,
    browse,
    abortBrowse,
    prepareSong,
    playVideo: (song: SongIdentity, settle: Settle<null>) =>
      client?.songs.playVideo(song, settle) ?? null,
    queueSong,
    renameRemote,
    forgetBrowser,
  };
});

// A mode the person just set stays on screen until the Host reports it. A change that did not apply is dropped at once,
// and one that did apply is dropped after a short wait if the Host's own report never matches.
function releaseTarget<Value>(
  target: Ref<Value | null>,
  reported: () => Value | undefined,
  result: CommandResult,
): void {
  if (result.outcome !== 'applied' || reported() === target.value) {
    target.value = null;

    return;
  }

  const held = target.value;

  setTimeout(() => {
    if (target.value === held) target.value = null;
  }, volumeSettleMs);
}

function scheduleTask(callback: () => void, delayMs: number): () => void {
  const handle = setTimeout(callback, delayMs);

  return () => clearTimeout(handle);
}
