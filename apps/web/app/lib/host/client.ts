import { ClockSync } from './clockSync';
import { commandExpiryMs, commandWindowMs } from './commandWindow';
import { CommandTracker, unavailableResult } from './commandTracker';
import { Waiters } from './waiters';
import { SongRequests } from './songRequests';
import type { ArtworkSupport } from './artworkCoordinator';
import {
  encodeArtworkCancel,
  encodeArtworkGet,
  encodeCommand,
  encodeCommandStatus,
  encodeCreditAck,
  encodeHello,
  encodeHostUpdate,
  encodeLyricsGet,
  encodeMotionGet,
  encodePair,
  encodeRemoteConfigure,
  encodeSessionStatus,
} from '../protocol/encode';
import { decodeHostMessage, type HostMessage } from '../protocol/decode';
import { artworkDataUrl } from './artwork';
import { ArtworkChunks } from './artworkTransfer';
import { MotionTransfer } from './motionTransfer';
import { ArtistMotion } from './artistMotion';
import type { StoredCredential } from './credentials';
import type {
  ArtworkMode,
  HostClientOptions,
  HostPhase,
  PendingPairing,
  PendingRequest,
  Readiness,
  SocketLike,
} from './clientTypes';
import { traceEvent, traceFrame, type TraceTransport } from './trace';
import { flushLocalLog } from './localLog';
import type {
  CommandAction,
  CommandResult,
  LyricDocument,
  Snapshot,
  Welcome,
} from '../protocol/types';

export type {
  ArtworkLane,
  ArtworkMode,
  HostChange,
  HostClientOptions,
  HostPhase,
  Readiness,
  SocketLike,
} from './clientTypes';

const handshakeTimeoutMs = 8_000;

// The Host gates dispatch by the deadline, then gives a dispatched playback change up to 2 s to verify it. A result that
// still has not arrived after both windows is looked up with command.status, which frees the controls. A late result is still shown.
const commandSettleMs = 4_000;

const reconnectDelaysMs = [1_000, 2_000, 4_000, 8_000, 16_000, 30_000];
const artworkCapability = 'artwork.host-cache';
const progressiveArtworkCapability = 'artwork.progressive';
const motionCapability = 'motion.host-cache';

// Owns one browser Remote session. Mutations are sent once. If the socket closes before a result, the command is
// reported as unconfirmed and only queried by its original ID after reconnecting; it is never sent again.
export class HostClient {
  private readonly options: HostClientOptions;
  private socket: SocketLike | null = null;
  protected credential: StoredCredential | null;
  private pendingPairing: PendingPairing | null = null;
  // A Bluetooth link is opened by a user gesture, so it is never reopened here. Losing one ends the session.
  private linkedOverBluetooth = false;
  private phase: HostPhase = 'unpaired';
  private attempt = 0;
  private welcomed = false;
  private capabilities: string[] = [];
  private snapshot: Snapshot | null = null;
  private readonly clock: ClockSync;
  private readonly commands: CommandTracker;
  private readonly waiters: Waiters;
  // Artist Details headers ask for their motion video through here. Their chunks never share the song's lanes.
  readonly artistMotion: ArtistMotion;
  readonly songs: SongRequests;
  private readonly artworkChunks = new ArtworkChunks({
    artworkRequest: (requestId) => {
      const request = this.requests.get(requestId);

      return request?.kind === 'artwork' ? request.artworkUrl : null;
    },
    deliver: (requestId, artworkUrl, dataUrl) =>
      this.onArtwork(artworkUrl, dataUrl, requestId),
  });
  private readonly motion = new MotionTransfer({
    motionRequest: (requestId, occurrenceId) => {
      const request = this.requests.get(requestId);

      return request?.kind === 'artwork' &&
        request.lane === 'motion' &&
        request.occurrenceId === occurrenceId
        ? request.artworkUrl
        : null;
    },
    finish: (requestId, artworkUrl, video) => {
      this.requests.delete(requestId);
      this.options.onChange({
        kind: 'motion',
        artworkUrl,
        video,
        unavailable: false,
        requestId,
      });
    },
  });
  private readonly requests = new Map<string, PendingRequest>();
  private cancelHandshake: (() => void) | null = null;
  private cancelReconnect: (() => void) | null = null;

  constructor(options: HostClientOptions) {
    this.options = options;
    this.credential = options.credentials.read();
    this.commands = new CommandTracker(
      options.schedule,
      commandSettleMs,
      (commandId) => this.queryCommandStatus(commandId),
    );
    this.waiters = new Waiters(options.schedule);
    this.artistMotion = new ArtistMotion(
      (text) => {
        if (!this.welcomed || this.socket === null) return false;

        this.transmit(this.socket, text);

        return true;
      },
      () => options.newId(),
    );
    this.songs = new SongRequests({
      send: (text) => {
        if (!this.welcomed || this.socket === null) return false;
        this.transmit(this.socket, text);

        return true;
      },
      newId: options.newId,
      schedule: options.schedule,
    });
    this.clock = new ClockSync({
      send: (frame) => {
        if (this.socket !== null) this.transmit(this.socket, frame);
      },
      newId: options.newId,
      monotonicNow: options.monotonicNow,
      schedule: options.schedule,
      onEstimate: (estimate, burstDone) => {
        traceEvent('clock offset estimated', estimate);
        options.onChange({
          kind: 'clock',
          offsetMs: estimate.offsetMs,
          roundTripMs: estimate.roundTripMs,
        });
        this.waiters.notify();

        if (burstDone) this.reportStatus();
      },
    });
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
    return this.clock.hostNowMs();
  }

  // Whether a command can be sent now. 'syncing' means the link is up but the first state or clock estimate has not
  // arrived, which a reconnect resolves within a round trip or two.
  readiness(): Readiness {
    if (!this.welcomed || this.socket === null) return 'offline';

    return this.snapshot === null || this.clock.hostNowMs() === null
      ? 'syncing'
      : 'ready';
  }

  // Resolves once the link is ready or offline, or as 'syncing' when the wait runs out.
  async awaitReadiness(timeoutMs: number): Promise<Readiness> {
    await this.waiters.until(() => this.readiness() !== 'syncing', timeoutMs);

    return this.readiness();
  }

  // Resolves once the Host's state is at or past a revision, or the link is gone. A command carries the revision it was
  // sent against, so the next one waits for the state that the previous one produced.
  async awaitRevision(minRevision: number, timeoutMs: number): Promise<void> {
    await this.waiters.until(
      () =>
        this.readiness() === 'offline' ||
        (this.snapshot?.revision ?? -1) >= minRevision,
      timeoutMs,
    );
  }

  latestSnapshot(): Snapshot | null {
    return this.snapshot;
  }

  // Whether the Host can serve artwork over the current link, and whether it also has motion.
  artworkSupport(): ArtworkSupport {
    if (!this.welcomed || this.socket === null) return 'offline';

    return this.capabilities.includes(artworkCapability)
      ? 'ready'
      : 'unsupported';
  }

  supportsMotion(): boolean {
    return this.capabilities.includes(motionCapability);
  }

  // The envelope is built from the state at this instant: the newest revision and epoch, and a deadline from the current
  // clock estimate. It is sent once. If the result does not arrive, the command settles as unconfirmed and is never resent.
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

    const result = this.commands.track(commandId, {
      kind: action.kind,
      expectedRevision: snapshot.revision,
      windowMs: commandWindowMs(this.clock.uncertaintyMs),
      roundTripMs: this.clock.roundTripMs,
    });

    this.transmit(
      socket,
      encodeCommand({
        commandId,
        hostEpoch: snapshot.hostEpoch,
        expiresAtHostMs: commandExpiryMs(hostNow, this.clock.uncertaintyMs),
        expectedRevision: snapshot.revision,
        action,
      }),
    );

    return result;
  }

  requestLyrics(occurrenceId: string): void {
    const socket = this.socket;

    if (!this.welcomed || socket === null) return;
    this.dropRequests('lyrics');
    const requestId = this.options.newId();
    this.requests.set(requestId, { kind: 'lyrics', occurrenceId });
    this.transmit(socket, encodeLyricsGet(requestId));
  }

  // Returns the request ID, or null when the Host cannot serve it. A null return has already reported the failure.
  requestArtwork(artworkUrl: string, mode: ArtworkMode): string | null {
    const socket = this.socket;

    const supported =
      this.welcomed &&
      socket !== null &&
      this.capabilities.includes(artworkCapability) &&
      (mode.kind !== 'motion' || this.capabilities.includes(motionCapability));

    if (!supported || socket === null) {
      this.reportUnservedArtwork(artworkUrl, mode);

      return null;
    }

    const requestId = this.options.newId();

    this.requests.set(requestId, {
      kind: 'artwork',
      artworkUrl,
      lane: mode.kind,
      occurrenceId: mode.kind === 'motion' ? mode.occurrenceId : null,
    });

    if (mode.kind === 'motion') {
      this.transmit(socket, encodeMotionGet(requestId, mode.occurrenceId));

      return requestId;
    }

    this.transmit(
      socket,
      encodeArtworkGet(requestId, artworkUrl, {
        progressive:
          mode.kind === 'preview' ||
          (this.options.progressiveArtwork === true &&
            this.capabilities.includes(progressiveArtworkCapability)),
        previewOnly: mode.kind === 'preview',
      }),
    );

    return requestId;
  }

  private reportUnservedArtwork(artworkUrl: string, mode: ArtworkMode): void {
    this.options.onChange(
      mode.kind === 'motion'
        ? {
            kind: 'motion',
            artworkUrl,
            video: null,
            unavailable: true,
            requestId: null,
          }
        : {
            kind: 'artwork',
            artworkUrl,
            dataUrl: null,
            full: true,
            requestId: null,
          },
    );
  }

  // Abandons one request, such as a still or motion video for a song that is no longer playing, and tells the Host to
  // stop it. Anything that still arrives for it is ignored.
  cancelArtwork(requestId: string): void {
    if (!this.requests.delete(requestId)) return;
    this.artworkChunks.drop(requestId);
    this.motion.drop(requestId);

    if (this.socket !== null) {
      this.transmit(this.socket, encodeArtworkCancel(requestId));
    }
  }

  // Asks the Host to check for an update, or to install the one it found. Its answer arrives as a host.update.status.
  requestHostUpdate(action: 'check' | 'install'): void {
    const socket = this.socket;

    if (
      !this.welcomed ||
      socket === null ||
      !this.capabilities.includes('host.update')
    ) {
      this.emitNotice('Connect to Cadenza Host to update it.');

      return;
    }

    this.transmit(socket, encodeHostUpdate(this.options.newId(), action));
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
        tasteDigest: this.options.tasteDigest?.() ?? null,
      }),
    );
  }

  private receive(socket: SocketLike, text: string): void {
    if (this.socket !== socket) return;
    traceFrame('in', this.transport(), text);
    this.options.onChange({ kind: 'traffic', direction: 'in' });
    const message = decodeHostMessage(text);

    if (message !== null && !this.songs.receive(message)) {
      this.dispatch(socket, message);
    }

    flushLocalLog(
      (text) => socket.send(text),
      this.snapshot?.hostBudget,
      socket.queuedBytes ?? 0,
    );
  }

  private transport(): TraceTransport {
    return this.linkedOverBluetooth ? 'bluetooth' : 'websocket';
  }

  private transmit(socket: SocketLike, text: string): void {
    traceFrame('out', this.transport(), text);
    this.options.onChange({ kind: 'traffic', direction: 'out' });
    socket.send(text);
  }

  private dispatch(socket: SocketLike, message: HostMessage): void {
    switch (message.type) {
      case 'welcome':
        this.onWelcome(message.welcome);

        return;
      case 'host.update.status':
        this.options.onChange({ kind: 'hostUpdate', status: message.status });

        return;
      case 'state':
        this.snapshot = message.snapshot;
        this.options.onChange({ kind: 'snapshot', snapshot: message.snapshot });
        this.waiters.notify();

        return;
      case 'command.result':
        this.onCommandResult(message.result);

        return;
      case 'error':
        this.onError(message);

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
        this.artworkChunks.receive(message);

        return;
      case 'artwork.unavailable':
        this.onArtwork(message.artworkUrl, null, message.requestId);

        return;
      case 'motion.chunk':
        this.motion.receive(message);

        return;
      case 'motion.unavailable':
        this.onMotionUnavailable(message.requestId);

        return;
      case 'artist.motion.chunk':
      case 'artist.motion.unavailable':
        this.artistMotion.receive(message);

        return;
      case 'clock':
        this.clock.receive(message.requestId, message.sample);

        return;
      case 'remote.configured':
        this.onRemoteConfigured(message.requestId);

        return;
      case 'analytics.credit':
        this.onCredit(socket, message.sequence);

        return;
    }
  }

  protected onWelcome(welcome: Welcome): void {
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
    this.clock.start();
    this.reconcileOrphanedCommands();
  }

  private onCommandResult(result: CommandResult): void {
    const sent = this.commands.sentFor(result.commandId);
    const kind = this.commands.receive(result);

    if (result.outcome !== 'applied') {
      traceEvent(`command ${sent?.kind ?? 'unknown'} ${result.outcome}`, {
        errorCode: result.errorCode,
        message: result.message,
        expectedRevision: sent?.expectedRevision,
        hostRevision: result.revision,
        windowMs: sent?.windowMs,
        roundTripMs: sent?.roundTripMs,
        late: kind === 'late',
      });
    }

    if (kind === 'late') {
      this.options.onChange({ kind: 'commandResolved', result });
    }
  }

  private onError(error: Extract<HostMessage, { type: 'error' }>): void {
    if (this.commands.refuse(error)) return;

    const { requestId, errorCode, message } = error;

    const request =
      requestId === null ? undefined : this.requests.get(requestId);

    if (requestId !== null) this.requests.delete(requestId);

    if (request !== undefined && requestId !== null) {
      this.onRequestError(request, requestId, message);

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

  private onRequestError(
    request: PendingRequest,
    requestId: string,
    message: string,
  ): void {
    switch (request.kind) {
      case 'lyrics':
        this.options.onChange({
          kind: 'lyricsUnavailable',
          occurrenceId: request.occurrenceId,
        });

        return;
      case 'artwork':
        this.reportRequestFailure(request, requestId);

        return;
      case 'rename':
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
    const request = this.requests.get(requestId);

    if (request?.kind !== 'artwork') return;
    // A preview-only request is answered by its preview.

    if (request.lane === 'preview') this.requests.delete(requestId);
    this.options.onChange({
      kind: 'artwork',
      artworkUrl,
      dataUrl,
      full: false,
      requestId,
    });
  }

  private onArtwork(
    artworkUrl: string,
    dataUrl: string | null,
    requestId: string,
  ): void {
    this.requests.delete(requestId);
    this.options.onChange({
      kind: 'artwork',
      artworkUrl,
      dataUrl,
      full: true,
      requestId,
    });
  }

  // The Host refused the request or it failed. A motion request fails as a refusal, which means the song has none.
  private reportRequestFailure(
    request: Extract<PendingRequest, { kind: 'artwork' }>,
    requestId: string,
  ): void {
    if (request.lane === 'motion') {
      this.options.onChange({
        kind: 'motion',
        artworkUrl: request.artworkUrl,
        video: null,
        unavailable: true,
        requestId,
      });

      return;
    }

    this.onArtwork(request.artworkUrl, null, requestId);
  }

  private onMotionUnavailable(requestId: string): void {
    const request = this.requests.get(requestId);

    if (request?.kind !== 'artwork' || request.lane !== 'motion') return;
    this.requests.delete(requestId);
    this.reportRequestFailure(request, requestId);
  }

  // Each estimate refreshes the path the Host shows for this Remote, so its status stays current while connected.
  private reportStatus(): void {
    const socket = this.socket;

    const roundTripMs = this.clock.roundTripMs;

    if (!this.welcomed || socket === null || roundTripMs === null) return;
    this.transmit(
      socket,
      encodeSessionStatus({
        reportedAtMs: Math.round(this.options.monotonicNow()),
        transport: this.linkedOverBluetooth ? 'ble' : 'lan',
        rttMs: Math.round(roundTripMs),
      }),
    );
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

  private reconcileOrphanedCommands(): void {
    const socket = this.socket;

    if (socket === null) return;

    for (const commandId of this.commands.orphanedIds()) {
      this.transmit(socket, encodeCommandStatus(commandId));
    }
  }

  // Asks the Host for the receipt of a command that is late. The answer arrives as a command.result for that ID.
  private queryCommandStatus(commandId: string): boolean {
    if (!this.welcomed || this.socket === null) return false;
    this.transmit(this.socket, encodeCommandStatus(commandId));

    return true;
  }

  private handleClose(socket: SocketLike): void {
    if (this.socket !== socket) return;
    traceEvent(`${this.transport()} socket closed`, { phase: this.phase });
    this.socket = null;
    this.welcomed = false;
    this.cancelHandshake?.();
    this.cancelHandshake = null;
    this.clock.stop();
    this.snapshot = null;
    this.requests.clear();
    this.artworkChunks.reset();
    this.motion.reset();
    this.commands.orphanAll(
      'The connection closed before Cadenza Host confirmed this change.',
    );
    this.songs.abandon();
    this.waiters.notify();

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

  protected scheduleReconnect(): void {
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
    this.songs.abandon();
    socket?.close();
    this.waiters.notify();
  }

  private cancelTimers(): void {
    this.cancelHandshake?.();
    this.cancelReconnect?.();
    this.clock.stop();
    this.cancelHandshake = null;
    this.cancelReconnect = null;
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
