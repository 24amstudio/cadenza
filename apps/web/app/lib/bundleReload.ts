import { isOlderRelease } from '~/lib/version';

// The bundle's own release. The build replaces this identifier with the version in package.json.
declare const __CADENZA_WEB_VERSION__: string;

const reloadedForKey = 'cadenza.web.reloadedFor';

// A page loaded before a Host update keeps its old bundle. Once a newer Host says so, the page clears cached assets and
// loads the Host's bundle. One reload per Host release stops a stale cache from looping.
export function reloadForNewerHostBundle(hostVersion: string | null): void {
  if (!hostVersion || !isOlderRelease(__CADENZA_WEB_VERSION__, hostVersion))
    return;

  const storage = sessionStorageOrNull();

  if (storage?.getItem(reloadedForKey) === hostVersion) return;

  storage?.setItem(reloadedForKey, hostVersion);

  void (async () => {
    if ('caches' in globalThis) {
      for (const name of await caches.keys()) await caches.delete(name);
    }

    location.reload();
  })();
}

function sessionStorageOrNull(): Storage | null {
  try {
    return globalThis.sessionStorage;
  } catch {
    // Storage can be blocked. The reload then runs without its once-per-release guard.
    return null;
  }
}
