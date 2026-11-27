// The Host serves this app and its socket from one origin, so the socket path is relative to the page.
export const socketPath = '/v1/socket';

// Sent in pairing and hello frames so the Host can report which web build a Remote runs.
export const remoteVersion = 'cadenza-web 1';

export interface LanEndpoint {
  // The Host's IPv4 address from its last welcome.
  address: string;
  // The Host's Bonjour name, which a browser resolves to the current address. Null when the Host sent none.
  name: string | null;
  port: number;
}

// Chrome exempts a ws:// URL from mixed-content blocking when its host is an IP literal, a .local name, or localhost.
const ipv4Pattern =
  /^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$/;

const bonjourNamePattern = /^[a-z0-9-]{1,63}\.local$/;

export function lanEndpointFrom(
  address: string | null,
  name: string | null,
  port: number | null,
): LanEndpoint | null {
  if (address === null || port === null) return null;

  if (!ipv4Pattern.test(address) || port < 1 || port > 65_535) return null;

  const bonjour = name !== null && bonjourNamePattern.test(name) ? name : null;

  return { address, name: bonjour, port };
}

// The name comes first: it resolves to the Mac's current address, so a changed network address needs no Bluetooth.
export function lanSocketUrls(endpoint: LanEndpoint): string[] {
  const hosts =
    endpoint.name === null
      ? [endpoint.address]
      : [endpoint.name, endpoint.address];

  return hosts.map((host) => `ws://${host}:${endpoint.port}${socketPath}`);
}

export function socketUrlFor(pageUrl: string): string {
  const url = new URL(socketPath, pageUrl);
  url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
  url.hash = '';

  return url.toString();
}

// The Host requires a name of 1 to 80 characters without control characters.
export function isValidRemoteName(name: string): boolean {
  const characters = [...name.trim()];

  return (
    characters.length >= 1 &&
    characters.length <= 80 &&
    !characters.some((character) => {
      const code = character.codePointAt(0) ?? 0;

      return code < 32 || code === 127;
    })
  );
}

export function defaultRemoteName(userAgent: string): string {
  const platform = platformName(userAgent);

  return `Web browser on ${platform}`;
}

function platformName(userAgent: string): string {
  if (/iPhone|iPod/.test(userAgent)) return 'iPhone';

  if (/iPad/.test(userAgent)) return 'iPad';

  if (/Android/.test(userAgent)) return 'Android';

  if (/Macintosh|Mac OS X/.test(userAgent)) return 'Mac';

  if (/Windows/.test(userAgent)) return 'Windows';

  if (/Linux|X11/.test(userAgent)) return 'Linux';

  return 'this device';
}
