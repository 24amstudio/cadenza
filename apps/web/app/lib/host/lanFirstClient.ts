import type { Welcome } from '../protocol/types';
import { HostClient, type HostClientOptions } from './client';
import type { SocketLike } from './clientTypes';
import { lanEndpointFrom, lanSocketUrls } from './endpoint';

// A socket that has not welcomed within this window is abandoned, so the next address is tried without a long wait.
const lanAttemptMs = 3_000;

// While `url` is set, every socket the client opens goes there instead of to the page's own origin.
interface LanRoute {
  url: string | null;
  socket: SocketLike | null;
}

// A paired browser reaches the Host over the LAN before Bluetooth. It tries the Host's Bonjour name, then the last
// recorded address. When neither welcomes, the session moves to `onUnavailable` (Bluetooth), and that welcome records the
// Host's current address. After a welcome, a dropped link reconnects to the address that welcomed, and moves on to the
// next address only when a reconnect fails.
export class LanFirstHostClient extends HostClient {
  private readonly route: LanRoute;
  private readonly credentials: HostClientOptions['credentials'];
  private readonly schedule: HostClientOptions['schedule'];
  private fallback: (() => void) | null = null;
  private cancelAttempt: (() => void) | null = null;
  private urls: string[] = [];
  private index = 0;
  private welcomedOnLan = false;

  constructor(options: HostClientOptions) {
    const route: LanRoute = { url: null, socket: null };

    super({
      ...options,
      openSocket: (url) => {
        const socket = options.openSocket(route.url ?? url);
        route.socket = socket;

        return socket;
      },
    });
    this.route = route;
    this.credentials = options.credentials;
    this.schedule = options.schedule;
  }

  // Returns false when no LAN endpoint is recorded, so the caller can use Bluetooth straight away.
  connectOverLan(onUnavailable: () => void): boolean {
    const lan = this.credential?.lan;

    if (!lan) return false;

    this.urls = lanSocketUrls(lan);
    this.index = 0;
    this.fallback = onUnavailable;
    this.attemptUrl();

    return true;
  }

  // Opens the current address and gives it the attempt window.
  private attemptUrl(): void {
    this.route.url = this.urls[this.index] ?? null;
    this.start(null);
    const socket = this.route.socket;
    this.cancelAttempt = this.schedule(() => {
      if (this.fallback !== null) socket?.close();
    }, lanAttemptMs);
  }

  protected override onWelcome(welcome: Welcome): void {
    super.onWelcome(welcome);
    this.fallback = null;
    this.cancelAttempt?.();
    this.cancelAttempt = null;
    this.welcomedOnLan = this.route.url !== null;

    if (this.credential === null) return;

    // Every welcome carries the Host's current address, so the recorded endpoint follows a network change.
    const lan = lanEndpointFrom(
      welcome.hostAddress,
      welcome.webHost,
      welcome.webPort,
    );

    this.credential = { ...this.credential, lan };
    this.credentials.write(this.credential);

    if (lan !== null) {
      this.urls = lanSocketUrls(lan);
      this.index = Math.max(0, this.urls.indexOf(this.route.url ?? ''));
    }
  }

  protected override scheduleReconnect(): void {
    const welcomed = this.welcomedOnLan;
    const fallback = this.fallback;

    this.welcomedOnLan = false;
    this.cancelAttempt?.();
    this.cancelAttempt = null;

    if (fallback !== null) {
      this.index += 1;

      if (this.index < this.urls.length) {
        this.attemptUrl();

        return;
      }

      this.fallback = null;
      this.route.url = null;
      fallback();

      return;
    }

    if (this.route.url === null || this.urls.length === 0) {
      super.scheduleReconnect();

      return;
    }

    if (!welcomed) this.index = (this.index + 1) % this.urls.length;
    this.route.url = this.urls[this.index] ?? null;
    super.scheduleReconnect();
  }
}
