import { defineStore } from 'pinia';
import { computed, ref, shallowRef, watch } from 'vue';
import { openBrowserSocket } from '~/lib/host/browserSocket';
import { HostClient, type HostChange, type HostPhase } from '~/lib/host/client';
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
const progressIntervalMs = 250;

export const useHostStore = defineStore('host', () => {
  const notices = useNoticesStore();
  const phase = ref<HostPhase>('unpaired');
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
  const busyAction = ref<CommandAction['kind'] | null>(null);
  const artworkRequests = new Set<string>();
  let client: HostClient | null = null;
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

  // The position ticks only while music is playing and the socket is connected. Each tick is a cheap recomputation of
  // the Host-anchored position, not a network request.
  const positionMs = computed(() => {
    const song = current.value;

    if (song === null) return 0;
    void clockTick.value;
    const offset = clockOffsetMs.value;

    const hostNow =
      offset === null ? song.sampledAtHostMs : performance.now() + offset;

    return positionAt(song, isPlaying.value, hostNow);
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
      credentials: createCredentialStore(browserStorage()),
      monotonicNow: () => performance.now(),
      schedule: scheduleTask,
      newId: randomUuid,
      onChange: handleChange,
    });
    remoteName.value = client.remoteName();
    client.start(secret);
  }

  function retry(): void {
    client?.retry();
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
        artworkRequests.delete(change.artworkUrl);
        rememberArtwork(change.artworkUrl, change.dataUrl);

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
      artworkRequests.clear();
      lyrics.value = null;
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
    const song = next.current;

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

  function requestArtwork(url: string): void {
    if (url in artworks.value || artworkRequests.has(url)) return;
    artworkRequests.add(url);
    client?.requestArtwork(url);
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
    client?.forget();
    remoteName.value = '';
  }

  return {
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
    requestArtwork,
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
