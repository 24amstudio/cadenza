// crypto.randomUUID exists only in secure contexts, and the Host is reached over plain HTTP on the LAN. This builds a
// version 4 UUID from getRandomValues, which every context provides. Host protocol identifiers are lowercase UUIDs.
export function randomUuid(): string {
  const bytes = Array.from(
    crypto.getRandomValues(new Uint8Array(16)),
    (byte, index) => {
      if (index === 6) return (byte & 0x0f) | 0x40;

      if (index === 8) return (byte & 0x3f) | 0x80;

      return byte;
    },
  );

  const hex = bytes.map((byte) => byte.toString(16).padStart(2, '0')).join('');

  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
