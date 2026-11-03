// The Host serves this app and its socket from one origin, so the socket path is relative to the page.
export const socketPath = '/v1/socket';

// Sent in pairing and hello frames so the Host can report which web build a Remote runs.
export const remoteVersion = 'cadenza-web 1';

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
