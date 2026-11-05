import { bestClockEstimate, type ClockProbe } from './clock';
import {
  encodeArtworkGet,
  encodeClock,
  encodeCommand,
  encodeCommandStatus,
  encodeCreditAck,
  encodeHello,
  encodeLyricsGet,
  encodePair,
  encodeRemoteConfigure,
  type PairingProof,
} from '../protocol/encode';
import { decodeHostMessage, type HostMessage } from '../protocol/decode';
import { artworkDataUrl } from './artwork';
import {
  ArtworkAssembly,
  base64ToBytes,
  bytesToBase64,
  digestMatches,
} from './artworkAssembly';
import type { CredentialStore, StoredCredential } from './credentials';
import { traceEvent, traceFrame, type TraceTransport } from './trace';
import type {
  ClockSample,
  CommandAction,
  CommandResult,
  LyricDocument,
  Snapshot,
  Welcome,
} from '../protocol/types';

export type HostPhase =
  | 'unpaired'
  | 'pairing'
  | 'pairing-failed'
  | 'connecting'
  | 'connected'
  | 'reconnecting'
  | 'bluetooth-idle';

export type HostChange =
  | { kind: 'phase'; phase: HostPhase; attempt: number; message: string | null }
  | { kind: 'welcome'; welcome: Welcome }
  | { kind: 'snapshot'; snapshot: Snapshot }
  | { kind: 'clock'; offsetMs: number }
  | { kind: 'lyrics'; lyrics: LyricDocument }
  | { kind: 'lyricsUnavailable'; occurrenceId: string | null }
  | { kind: 'artwork'; artworkUrl: string; dataUrl: string | null }
  | { kind: 'commandResolved'; result: CommandResult }
  | { kind: 'notice'; message: string };

// Only the methods the client uses. Browser WebSocket instances are adapted to this shape by the app.
export interface SocketLike {
  onOpen: (() => void) | null;
  onMessage: ((text: string) => void) | null;
  onClose: (() => void) | null;
  send(text: string): void;
  close(): void;
}

export interface HostClientOptions {
  url: string;
  remoteVersion: string;
  defaultName: string;
  openSocket: (url: string) => SocketLike;
  credentials: CredentialStore;
  monotonicNow: () => number;
  schedule: (callback: () => void, delayMs: number) => () => void;
  newId: () => string;
  onChange: (change: HostChange) => void;
  // Asks for a preview before the full artwork. Only the Bluetooth page sets this, and only the Host's capability enables it.
  progressiveArtwork?: boolean;
}

type ArtworkChunkMessage = Extract<HostMessage, { type: 'artwork.chunk' }>;

interface PendingCommand {
  resolve: (result: CommandResult) => void;
}

interface PendingPairing {
  proof: PairingProof;
  name: string;
}

type PendingRequest =
  | { kind: 'clock'; sentAtRemoteMs: number }
  | { kind: 'lyrics'; occurrenceId: string }
  | { kind: 'artwork'; artworkUrl: string }
  | { kind: 'rename'; name: string };

const handshakeTimeoutMs = 8_000;

// The Host refuses a command whose deadline is more than one second ahead of its clock. Cadenza Remote uses 900 ms
// less the clock uncertainty, and so does this page. A longer deadline is rejected as invalid_deadline.
const commandDeadlineMs = 900;

// The first probes come back to back and set the offset. After that one probe runs every few seconds, so the offset
// follows the link as its round trip changes.
const clockProbeCount = 4;
const clockProbeIntervalMs = 5_000;

// The offset comes from the fastest round trip in this window. A slow probe carries more asymmetric queuing delay.
const clockWindowSize = 12;

const reconnectDelaysMs = [1_000, 2_000, 4_000, 8_000, 16_000, 30_000];
const artworkCapability = 'artwork.host-cache';
const progressiveArtworkCapability = 'artwork.progressive';

// Owns one browser Remote session. Mutations are sent once. If the socket closes before a result, the command is
// reported as unconfirmed and only queried by its original ID after reconnecting; it is never sent again.
export class HostClient {
  private readonly options: HostClientOptions;
  private socket: SocketLike | null = null;
  private credential: StoredCredential | null;
  private pendingPairing: PendingPairing | null = null;
  // A Bluetooth link is opened by a user gesture, so it is never reopened here. Losing one ends the session.
  private linkedOverBluetooth = false;
  private phase: HostPhase = 'unpaired';
  private attempt = 0;
  private welcomed = false;
  private capabilities: string[] = [];
  private snapshot: Snapshot | null = null;
  private offsetMs: number | null = null;
  private uncertaintyMs = 0;
  private probes: ClockProbe[] = [];
  private readonly pendingCommands = new Map<string, PendingCommand>();
  private readonly artworkAssemblies = new Map<string, ArtworkAssembly>();
  private readonly orphanedCommands = new Set<string>();
  private readonly requests = new Map<string, PendingRequest>();
  private cancelHandshake: (() => void) | null = null;
  private cancelReconnect: (() => void) | null = null;
  private cancelClockRefresh: (() => void) | null = null;

  constructor(options: HostClientOptions) {
    this.options = options;
    this.credential = options.credentials.read();
  }

  start(invitationSecret: string | null): void {
    if (invitationSecret !== null) {
      this.pendingPairing = {
        proof: { secret: invitationSecret },
        name: this.options.defaultName,
      };
    }

    if (this.pendingPairing === null && this.credential === null) {
      this.setPhase('unpaired', null);

      return;
    }

    this.connect();
  }

  // Bluetooth pages start with no socket. With a stored credential and a remembered device, the page starts in the
  // connecting state, so the pairing view never flashes while it reconnects silently. Returns true when the store
  // should attempt that reconnect now.
  startBluetooth(deviceRemembered: boolean): boolean {
    if (this.credential === null) {
      this.setPhase('unpaired', null);

      return false;
    }

    this.setPhase(deviceRemembered ? 'connecting' : 'bluetooth-idle', null);

    return deviceRemembered;
  }

  // The silent reconnect found no permitted device, so the user must choose the Host again.
  bluetoothReconnectFailed(): void {
    if (this.credential !== null && !this.welcomed) {
      this.setPhase('bluetooth-idle', null);
    }
  }

  pairOverBluetooth(socket: SocketLike, pin: string, name: string): void {
    this.pendingPairing = { proof: { pin }, name };
    this.attachBluetooth(socket);
  }

  connectOverBluetooth(socket: SocketLike): void {
    if (this.credential === null) return;
    this.attachBluetooth(socket);
  }

  retry(): void {
    if (this.pendingPairing === null && this.credential === null) return;
    this.cancelReconnect?.();
    this.cancelReconnect = null;
    this.connect();
  }

  remoteName(): string {
    return this.credential?.name ?? this.options.defaultName;
  }

  // Milliseconds on the Host's monotonic timeline, or null until a clock estimate exists.
  hostNowMs(): number | null {
    if (this.offsetMs === null) return null;

    return this.options.monotonicNow() + this.offsetMs;
  }

  sendCommand(action: CommandAction): Promise<CommandResult> {
    const socket = this.socket;
    const snapshot = this.snapshot;
    const hostNow = this.hostNowMs();

    if (
      !this.welcomed ||
      socket === null ||
      snapshot === null ||
      hostNow === null
    ) {
      return Promise.resolve(unavailableResult());
    }

    const commandId = this.options.newId();

    return new Promise((resolve) => {
      this.pendingCommands.set(commandId, { resolve });
      this.transmit(
        socket,
        encodeCommand({
          commandId,
          hostEpoch: snapshot.hostEpoch,
          expiresAtHostMs: Math.max(
            0,
            Math.round(hostNow + commandDeadlineMs - this.uncertaintyMs),
          ),
          expectedRevision: snapshot.revision,
          action,
        }),
      );
    });
  }

  requestLyrics(occurrenceId: string): void {
    const socket = this.socket;

    if (!this.welcomed || socket === null) return;
    this.dropRequests('lyrics');
    const requestId = this.options.newId();
    this.requests.set(requestId, { kind: 'lyrics', occurrenceId });
    this.transmit(socket, encodeLyricsGet(requestId));
  }

  requestArtwork(artworkUrl: string): void {
    const socket = this.socket;

    if (
      !this.welcomed ||
      socket === null ||
      !this.capabilities.includes(artworkCapability)
    ) {
      this.options.onChange({ kind: 'artwork', artworkUrl, dataUrl: null });

      return;
    }

    const requestId = this.options.newId();
    this.requests.set(requestId, { kind: 'artwork', artworkUrl });
    this.transmit(
      socket,
      encodeArtworkGet(
        requestId,
        artworkUrl,
        this.options.progressiveArtwork === true &&
          this.capabilities.includes(progressiveArtworkCapability),
      ),
    );
  }

  renameRemote(name: string): void {
    const socket = this.socket;

    if (!this.welcomed || socket === null) {
      this.emitNotice('Connect to Cadenza Host before renaming this browser.');

      return;
    }

    const requestId = this.options.newId();
    this.requests.set(requestId, { kind: 'rename', name });
    this.transmit(socket, encodeRemoteConfigure(requestId, name));
  }

  // Forgets this browser's credential locally. The Host keeps the pairing until its owner revokes it there.
  forget(): void {
    this.options.credentials.clear();
    this.credential = null;
    this.pendingPairing = null;
    this.closeSocket();
    this.cancelTimers();
    this.setPhase('unpaired', null);
  }

  dispose(): void {
    this.closeSocket();
    this.cancelTimers();
  }

  private connect(): void {
    this.cancelReconnect?.();
    this.cancelReconnect = null;
    this.closeSocket();
    this.welcomed = false;
    this.linkedOverBluetooth = false;

    if (this.attempt === 0) {
      this.setPhase(
        this.pendingPairing === null ? 'connecting' : 'pairing',
        null,
      );
    }

    const socket = this.options.openSocket(this.options.url);
    this.socket = socket;
    socket.onOpen = () => this.handshake(socket);
    socket.onMessage = (text) => this.receive(socket, text);
    socket.onClose = () => this.handleClose(socket);
    this.cancelHandshake = this.options.schedule(() => {
      if (this.socket === socket && !this.welcomed) socket.close();
    }, handshakeTimeoutMs);
  }

  private attachBluetooth(socket: SocketLike): void {
    this.closeSocket();
    this.cancelReconnect?.();
    this.cancelReconnect = null;
    this.welcomed = false;
    this.linkedOverBluetooth = true;
    this.socket = socket;
    socket.onMessage = (text) => this.receive(socket, text);
    socket.onClose = () => this.handleClose(socket);
    this.cancelHandshake = this.options.schedule(() => {
      if (this.socket === socket && !this.welcomed) socket.close();
    }, handshakeTimeoutMs);
    this.setPhase(
      this.pendingPairing === null ? 'connecting' : 'pairing',
      null,
    );
    this.handshake(socket);
  }

  private handshake(socket: SocketLike): void {
    if (this.socket !== socket) return;

    if (this.pendingPairing !== null) {
      this.transmit(
        socket,
        encodePair(
          this.pendingPairing.proof,
          this.pendingPairing.name,
          this.options.remoteVersion,
        ),
      );

      return;
    }

    if (this.credential === null) return;
    this.transmit(
      socket,
      encodeHello({
        remoteId: this.credential.remoteId,
        token: this.credential.token,
        lastCreditSequence: this.credential.lastCreditSequence,
        name: this.credential.name,
        remoteVersion: this.options.remoteVersion,
      }),
    );
  }

  private receive(socket: SocketLike, text: string): void {
    if (this.socket !== socket) return;
    traceFrame('in', this.transport(), text);
    const message = decodeHostMessage(text);

    if (message === null) return;
    this.dispatch(socket, message);
  }

  private transport(): TraceTransport {
    return this.linkedOverBluetooth ? 'bluetooth' : 'websocket';
  }

  private transmit(socket: SocketLike, text: string): void {
    traceFrame('out', this.transport(), text);
    socket.send(text);
  }

  private dispatch(socket: SocketLike, message: HostMessage): void {
    switch (message.type) {
      case 'welcome':
        this.onWelcome(message.welcome);

        return;
      case 'state':
        this.snapshot = message.snapshot;
        this.options.onChange({ kind: 'snapshot', snapshot: message.snapshot });

        return;
      case 'command.result':
        this.onCommandResult(message.result);

        return;
      case 'error':
        this.onError(message.requestId, message.errorCode, message.message);

        return;
      case 'lyrics':
        this.onLyrics(message.lyrics);

        return;
      case 'lyrics.unavailable':
        this.dropRequests('lyrics');
        this.options.onChange({
          kind: 'lyricsUnavailable',
          occurrenceId: message.occurrenceId,
        });

        return;
      case 'artwork':
        if (message.variant === 'preview') {
          this.onArtworkPreview(
            message.artworkUrl,
            artworkDataUrl(message.dataBase64),
            message.requestId,
          );
        } else {
          this.onArtwork(
            message.artworkUrl,
            artworkDataUrl(message.dataBase64),
            message.requestId,
          );
        }

        return;
      case 'artwork.chunk':
        this.onArtworkChunk(message);

        return;
      case 'artwork.unavailable':
        this.onArtwork(message.artworkUrl, null, message.requestId);

        return;
      case 'clock':
        this.onClock(message.requestId, message.sample);

        return;
      case 'remote.configured':
        this.onRemoteConfigured(message.requestId);

        return;
      case 'analytics.credit':
        this.onCredit(socket, message.sequence);

        return;
    }
  }

  private onWelcome(welcome: Welcome): void {
    this.welcomed = true;
    this.attempt = 0;
    this.capabilities = welcome.capabilities;
    this.cancelHandshake?.();
    this.cancelHandshake = null;

    if (this.pendingPairing !== null) {
      if (welcome.token === null) {
        this.failPairing(
          'Cadenza Host did not issue a credential. Pair again.',
        );

        return;
      }

      this.credential = {
        remoteId: welcome.remoteId,
        token: welcome.token,
        name: this.pendingPairing.name,
        lastCreditSequence: 0,
      };
      this.options.credentials.write(this.credential);
      this.pendingPairing = null;
    }

    this.options.onChange({ kind: 'welcome', welcome });
    this.setPhase('connected', null);
    this.refreshClock();
    this.reconcileOrphanedCommands();
  }

  private onCommandResult(result: CommandResult): void {
    const pending = this.pendingCommands.get(result.commandId);

    if (pending !== undefined) {
      this.pendingCommands.delete(result.commandId);
      pending.resolve(result);

      return;
    }

    if (this.orphanedCommands.delete(result.commandId)) {
      this.options.onChange({ kind: 'commandResolved', result });
    }
  }

  private onError(
    requestId: string | null,
    errorCode: string,
    message: string,
  ): void {
    const request =
      requestId === null ? undefined : this.requests.get(requestId);

    if (requestId !== null) this.requests.delete(requestId);

    if (request !== undefined) {
      this.onRequestError(request, message);

      return;
    }

    if (this.welcomed) {
      this.emitNotice(message);

      return;
    }

    if (errorCode === 'authentication' || errorCode === 'revoked') {
      if (this.pendingPairing !== null) {
        this.failPairing(message);
      } else {
        this.unpairForRevocation();
      }

      return;
    }

    if (this.pendingPairing !== null) this.failPairing(message);
    else this.emitNotice(message);
  }

  private onRequestError(request: PendingRequest, message: string): void {
    switch (request.kind) {
      case 'lyrics':
        this.options.onChange({
          kind: 'lyricsUnavailable',
          occurrenceId: request.occurrenceId,
        });

        return;
      case 'artwork':
        this.options.onChange({
          kind: 'artwork',
          artworkUrl: request.artworkUrl,
          dataUrl: null,
        });

        return;
      case 'rename':
      case 'clock':
        this.emitNotice(message);

        return;
    }
  }

  private onLyrics(lyrics: LyricDocument): void {
    this.dropRequests('lyrics');
    this.options.onChange({ kind: 'lyrics', lyrics });
  }

  // The preview is shown at once. The request stays open, because the full image follows on it.
  private onArtworkPreview(
    artworkUrl: string,
    dataUrl: string | null,
    requestId: string,
  ): void {
    if (this.requests.get(requestId)?.kind !== 'artwork') return;

    this.options.onChange({ kind: 'artwork', artworkUrl, dataUrl });
  }

  private onArtworkChunk(message: ArtworkChunkMessage): void {
    const request = this.requests.get(message.requestId);

    if (request?.kind !== 'artwork') return;
    let assembly = this.artworkAssemblies.get(message.requestId);

    if (assembly === undefined) {
      if (!ArtworkAssembly.accepts(message.count, message.totalBytes)) return;
      assembly = new ArtworkAssembly(
        message.count,
        message.totalBytes,
        message.sha256,
      );
      this.artworkAssemblies.set(message.requestId, assembly);
      traceEvent('artwork transfer started', {
        requestId: message.requestId,
        chunks: message.count,
        bytes: message.totalBytes,
      });
    }

    const file = assembly.add(message.index, base64ToBytes(message.dataBase64));

    if (file === null) return;
    this.artworkAssemblies.delete(message.requestId);
    void this.deliverFullArtwork(
      message.requestId,
      request.artworkUrl,
      file,
      assembly.sha256,
    );
  }

  // A file that fails its digest is dropped. The preview stays on screen, and the request is released.
  private async deliverFullArtwork(
    requestId: string,
    artworkUrl: string,
    file: Uint8Array,
    sha256: string,
  ): Promise<void> {
    const verified = await digestMatches(file, sha256);

    if (this.requests.get(requestId)?.kind !== 'artwork') return;

    if (!verified) {
      traceEvent('artwork failed verification; keeping the preview');
      this.requests.delete(requestId);

      return;
    }

    // A file that is not a recognised image keeps the preview on screen rather than clearing it.
    const dataUrl = artworkDataUrl(bytesToBase64(file));

    if (dataUrl === null) {
      traceEvent('artwork is not a recognised image; keeping the preview');
      this.requests.delete(requestId);

      return;
    }

    traceEvent('artwork verified', { requestId, bytes: file.length });
    this.onArtwork(artworkUrl, dataUrl, requestId);
  }

  private onArtwork(
    artworkUrl: string,
    dataUrl: string | null,
    requestId: string,
  ): void {
    this.requests.delete(requestId);
    this.options.onChange({ kind: 'artwork', artworkUrl, dataUrl });
  }

  private onClock(requestId: string, sample: ClockSample): void {
    const request = this.requests.get(requestId);
    this.requests.delete(requestId);

    if (request === undefined || request.kind !== 'clock') return;
    this.probes.push({
      sentAtRemoteMs: request.sentAtRemoteMs,
      receivedAtRemoteMs: this.options.monotonicNow(),
      receivedAtHostMs: sample.receivedAtHostMs,
      sentAtHostMs: sample.sentAtHostMs,
    });
    this.probes.splice(0, Math.max(0, this.probes.length - clockWindowSize));

    if (this.probes.length < clockProbeCount) {
      this.sendClockProbe();

      return;
    }

    this.updateClockEstimate();
    this.cancelClockRefresh?.();
    this.cancelClockRefresh = this.options.schedule(
      () => this.sendClockProbe(),
      clockProbeIntervalMs,
    );
  }

  private updateClockEstimate(): void {
    const estimate = bestClockEstimate(this.probes);

    if (estimate === null) return;
    this.offsetMs = estimate.offsetMs;
    this.uncertaintyMs = estimate.uncertaintyMs;
    traceEvent('clock offset estimated', {
      offsetMs: estimate.offsetMs,
      roundTripMs: estimate.roundTripMs,
      uncertaintyMs: estimate.uncertaintyMs,
    });
    this.options.onChange({ kind: 'clock', offsetMs: estimate.offsetMs });
  }

  private onRemoteConfigured(requestId: string | null): void {
    const request =
      requestId === null ? undefined : this.requests.get(requestId);

    if (requestId !== null) this.requests.delete(requestId);

    if (
      request === undefined ||
      request.kind !== 'rename' ||
      this.credential === null
    )
      return;
    this.credential = { ...this.credential, name: request.name };
    this.options.credentials.write(this.credential);
    this.emitNotice('This browser name is saved on Cadenza Host.');
  }

  private onCredit(socket: SocketLike, sequence: number): void {
    this.transmit(socket, encodeCreditAck(sequence));

    if (
      this.credential === null ||
      sequence <= this.credential.lastCreditSequence
    )
      return;
    this.credential = { ...this.credential, lastCreditSequence: sequence };
    this.options.credentials.write(this.credential);
  }

  private refreshClock(): void {
    this.cancelClockRefresh?.();
    this.probes = [];
    this.sendClockProbe();
  }

  private sendClockProbe(): void {
    const socket = this.socket;

    if (socket === null) return;
    const requestId = this.options.newId();
    const sentAtRemoteMs = this.options.monotonicNow();
    this.requests.set(requestId, { kind: 'clock', sentAtRemoteMs });
    this.transmit(socket, encodeClock(requestId, sentAtRemoteMs));
  }

  private reconcileOrphanedCommands(): void {
    const socket = this.socket;

    if (socket === null) return;

    for (const commandId of this.orphanedCommands) {
      this.transmit(socket, encodeCommandStatus(commandId));
    }
  }

  private handleClose(socket: SocketLike): void {
    if (this.socket !== socket) return;
    traceEvent(`${this.transport()} socket closed`, { phase: this.phase });
    this.socket = null;
    this.welcomed = false;
    this.cancelHandshake?.();
    this.cancelHandshake = null;
    this.cancelClockRefresh?.();
    this.cancelClockRefresh = null;
    this.offsetMs = null;
    this.snapshot = null;
    this.requests.clear();
    this.artworkAssemblies.clear();
    this.orphanCommands();

    if (this.phase === 'pairing-failed' || this.phase === 'unpaired') return;

    if (this.linkedOverBluetooth) {
      if (this.pendingPairing !== null) {
        this.failPairing(
          'The Bluetooth connection closed before Cadenza Host confirmed this browser.',
        );

        return;
      }

      this.setPhase(
        'bluetooth-idle',
        'The Bluetooth connection ended. Connect again to continue.',
      );

      return;
    }

    if (this.pendingPairing === null && this.credential === null) {
      this.setPhase('unpaired', null);

      return;
    }

    this.scheduleReconnect();
  }

  private orphanCommands(): void {
    for (const [commandId, pending] of this.pendingCommands) {
      this.orphanedCommands.add(commandId);
      pending.resolve({
        commandId,
        outcome: 'unconfirmed',
        revision: 0,
        message:
          'The connection closed before Cadenza Host confirmed this change.',
        errorCode: 'outcome_unknown',
      });
    }

    this.pendingCommands.clear();
  }

  private scheduleReconnect(): void {
    this.attempt += 1;
    const index = Math.min(this.attempt - 1, reconnectDelaysMs.length - 1);
    const delayMs = reconnectDelaysMs[index] ?? 30_000;
    this.setPhase('reconnecting', null);
    this.cancelReconnect = this.options.schedule(() => {
      this.cancelReconnect = null;
      this.connect();
    }, delayMs);
  }

  private failPairing(message: string): void {
    this.pendingPairing = null;
    this.closeSocket();
    this.cancelTimers();
    this.setPhase('pairing-failed', message);
  }

  private unpairForRevocation(): void {
    this.options.credentials.clear();
    this.credential = null;
    this.closeSocket();
    this.cancelTimers();
    this.setPhase(
      'unpaired',
      'This browser is no longer paired with Cadenza Host. Pair it again.',
    );
  }

  private dropRequests(kind: PendingRequest['kind']): void {
    for (const [requestId, request] of this.requests) {
      if (request.kind === kind) this.requests.delete(requestId);
    }
  }

  private closeSocket(): void {
    const socket = this.socket;
    this.socket = null;
    this.welcomed = false;
    socket?.close();
  }

  private cancelTimers(): void {
    this.cancelHandshake?.();
    this.cancelReconnect?.();
    this.cancelClockRefresh?.();
    this.cancelHandshake = null;
    this.cancelReconnect = null;
    this.cancelClockRefresh = null;
    this.attempt = 0;
  }

  private setPhase(phase: HostPhase, message: string | null): void {
    this.phase = phase;
    traceEvent(`phase: ${phase}`, { attempt: this.attempt, message });
    this.options.onChange({
      kind: 'phase',
      phase,
      attempt: this.attempt,
      message,
    });
  }

  private emitNotice(message: string): void {
    this.options.onChange({ kind: 'notice', message });
  }
}

function unavailableResult(): CommandResult {
  return {
    commandId: '',
    outcome: 'rejected',
    revision: 0,
    message: 'Cadenza Host is not connected.',
    errorCode: 'unavailable',
  };
}
