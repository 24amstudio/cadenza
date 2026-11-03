import {
  counterField,
  isJsonObject,
  parseJson,
  stringField,
} from '../protocol/json';

// The Host credential proves this browser is a paired Remote. It is stored for this origin only and is never placed in
// a URL or logged. Reads are validated, and storage failures fall back to memory so the page still works for the session.
export interface StoredCredential {
  remoteId: string;
  token: string;
  name: string;
  lastCreditSequence: number;
}

export interface CredentialStore {
  read(): StoredCredential | null;
  write(credential: StoredCredential): void;
  clear(): void;
}

const storageKey = 'cadenza.web.credential';

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function parseStoredCredential(text: string): StoredCredential | null {
  const value = parseJson(text);

  if (!isJsonObject(value)) return null;
  const remoteId = stringField(value, 'remoteId');
  const token = stringField(value, 'token');
  const name = stringField(value, 'name');
  const lastCreditSequence = counterField(value, 'lastCreditSequence');

  if (
    remoteId === null ||
    !uuidPattern.test(remoteId) ||
    token === null ||
    token.length < 32 ||
    token.length > 128 ||
    name === null ||
    name.length < 1 ||
    name.length > 80 ||
    lastCreditSequence === null
  ) {
    return null;
  }

  return { remoteId, token, name, lastCreditSequence };
}

export type CredentialStorage = Pick<
  Storage,
  'getItem' | 'setItem' | 'removeItem'
>;

export function createCredentialStore(
  storage: CredentialStorage | null,
): CredentialStore {
  let memory: StoredCredential | null = null;

  return {
    read() {
      if (storage === null) return memory;

      try {
        const text = storage.getItem(storageKey);

        return text === null ? memory : parseStoredCredential(text);
      } catch {
        return memory;
      }
    },
    write(credential) {
      memory = credential;

      try {
        storage?.setItem(storageKey, JSON.stringify(credential));
      } catch {
        // Private browsing can refuse storage. The memory copy keeps this page session paired.
      }
    },
    clear() {
      memory = null;

      try {
        storage?.removeItem(storageKey);
      } catch {
        // Nothing else to clear when storage is unavailable.
      }
    },
  };
}
