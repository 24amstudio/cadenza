import { randomUuid } from '~/lib/host/ids';
import { Favorites } from '~/lib/library/favorites';
import { History } from '~/lib/library/history';
import { browserLocalStorage, keyValueStore } from '~/lib/library/keyValue';
import {
  buildTasteDigest,
  tasteDigestOptedIn,
  type TasteDigest,
} from '~/lib/tasteDigest';

/** The digest from this browser's own history and favorites, or null until the listener opts in. */
export function currentTasteDigest(): TasteDigest | null {
  if (!tasteDigestOptedIn(browserLocalStorage())) return null;

  const store = keyValueStore(browserLocalStorage);

  return buildTasteDigest(
    new History(store, randomUuid).list(),
    new Favorites(store).list(),
  );
}
