// Cadenza Host puts the native pairing invitation after "#" in its QR URL, for example
// http://192.168.1.20:43129/#CDZP:<base64url>. The fragment never reaches the Host as part of an HTTP request.
// Layout after base64url decoding: "CDZP" magic, version byte, length-prefixed host, 2-byte port, then a
// length-prefixed one-use secret. The browser needs only the secret because it already connects to the origin
// the QR code named.

const invitationPrefix = 'CDZP:';
const magic = [0x43, 0x44, 0x5a, 0x50];

// Older invitation layouts are refused rather than parsed.
const supportedVersion = 3;

export function readInvitationSecret(hash: string): string | null {
  const fragment = hash.startsWith('#') ? hash.slice(1) : hash;

  if (!fragment.startsWith(invitationPrefix)) return null;
  const bytes = base64UrlToBytes(fragment.slice(invitationPrefix.length));

  return bytes === null ? null : secretFromBytes(bytes);
}

function secretFromBytes(bytes: Uint8Array): string | null {
  if (bytes.length < magic.length + 1) return null;

  if (!magic.every((value, index) => bytes[index] === value)) return null;

  if (bytes[magic.length] !== supportedVersion) return null;
  const hostLengthIndex = magic.length + 1;

  const secretLengthIndex =
    hostLengthIndex + 1 + (bytes[hostLengthIndex] ?? 0) + 2;

  const secretLength = bytes[secretLengthIndex];

  if (secretLength === undefined) return null;
  const secretStart = secretLengthIndex + 1;
  const secretEnd = secretStart + secretLength;

  if (secretLength < 32 || secretLength > 128) return null;

  // The Host writes exactly these bytes, so anything after the secret means this is not a current invitation.
  if (bytes.length !== secretEnd) return null;

  return new TextDecoder().decode(bytes.slice(secretStart, secretEnd));
}

function base64UrlToBytes(encoded: string): Uint8Array | null {
  if (!/^[A-Za-z0-9_-]+$/.test(encoded)) return null;
  const padded = encoded.replace(/-/g, '+').replace(/_/g, '/');

  const binary = atob(
    padded.padEnd(padded.length + ((4 - (padded.length % 4)) % 4), '='),
  );

  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}
