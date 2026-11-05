import type { SocketLike } from './client';

// Same GATT layout as the native Remote. Each Host message is a 4-byte big-endian UTF-8 length followed by its bytes,
// split into characteristic values. The Host sends its own chunks, so the reader accepts any split point.
export const bluetoothServiceUuid = '9f4c0001-4b9c-4f2d-9c2a-1c8f8b3d4a10';
const writeCharacteristicUuid = '9f4c0002-4b9c-4f2d-9c2a-1c8f8b3d4a10';
const notifyCharacteristicUuid = '9f4c0003-4b9c-4f2d-9c2a-1c8f8b3d4a10';

export const maximumBluetoothFrameBytes = 1_048_576;

// Web Bluetooth exposes no MTU negotiation, so writes use the 20 bytes that every link supports (ATT MTU 23 less its
// 3-byte header).
const writeChunkBytes = 20;

const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });

export function bluetoothChunks(text: string): Uint8Array<ArrayBuffer>[] {
  const payload = encoder.encode(text);

  if (payload.length > maximumBluetoothFrameBytes) {
    throw new Error('The message is too large for Bluetooth.');
  }

  const framed = new Uint8Array(new ArrayBuffer(4 + payload.length));

  new DataView(framed.buffer).setUint32(0, payload.length);
  framed.set(payload, 4);

  const chunks: Uint8Array<ArrayBuffer>[] = [];

  for (let offset = 0; offset < framed.length; offset += writeChunkBytes) {
    chunks.push(framed.subarray(offset, offset + writeChunkBytes));
  }

  return chunks;
}

export class BluetoothFrameReader {
  private buffer: Uint8Array<ArrayBuffer> = new Uint8Array(new ArrayBuffer(0));
  private expectedBytes: number | null = null;

  // Returns every message completed by this chunk. A malformed length or encoding throws, and the caller ends the link.
  append(chunk: Uint8Array): string[] {
    this.buffer = concat(this.buffer, chunk);
    const messages: string[] = [];

    for (;;) {
      if (this.expectedBytes === null) {
        if (this.buffer.length < 4) return messages;

        const length = new DataView(
          this.buffer.buffer,
          this.buffer.byteOffset,
          4,
        ).getUint32(0);

        if (length > maximumBluetoothFrameBytes) {
          throw new Error('Cadenza Host sent an invalid Bluetooth frame.');
        }

        this.expectedBytes = length;
        this.buffer = this.buffer.slice(4);
      }

      if (this.buffer.length < this.expectedBytes) return messages;

      messages.push(
        decoder.decode(this.buffer.subarray(0, this.expectedBytes)),
      );
      this.buffer = this.buffer.slice(this.expectedBytes);
      this.expectedBytes = null;
    }
  }
}

function concat(
  first: Uint8Array<ArrayBuffer>,
  second: Uint8Array,
): Uint8Array<ArrayBuffer> {
  const joined = new Uint8Array(new ArrayBuffer(first.length + second.length));

  joined.set(first);
  joined.set(second, first.length);

  return joined;
}

// Web Bluetooth types are not part of TypeScript's DOM library, so this declares only the calls the Remote makes.
interface BluetoothApi {
  requestDevice(options: {
    filters: { services: string[] }[];
  }): Promise<BluetoothDevice>;
}

interface BluetoothDevice {
  readonly gatt?: BluetoothRemoteGATTServer;
  addEventListener(type: 'gattserverdisconnected', listener: () => void): void;
}

interface BluetoothRemoteGATTServer {
  connect(): Promise<BluetoothRemoteGATTServer>;
  disconnect(): void;
  getPrimaryService(service: string): Promise<BluetoothRemoteGATTService>;
}

interface BluetoothRemoteGATTService {
  getCharacteristic(
    characteristic: string,
  ): Promise<BluetoothRemoteGATTCharacteristic>;
}

interface BluetoothRemoteGATTCharacteristic {
  readonly value?: DataView;
  startNotifications(): Promise<BluetoothRemoteGATTCharacteristic>;
  writeValueWithResponse(value: BufferSource): Promise<void>;
  addEventListener(
    type: 'characteristicvaluechanged',
    listener: () => void,
  ): void;
}

// Web Bluetooth exists only in secure contexts. The Host's plain-HTTP LAN page therefore never has it.
export function bluetoothAvailable(): boolean {
  return (
    typeof window !== 'undefined' &&
    window.isSecureContext &&
    bluetoothApi() !== null
  );
}

function bluetoothApi(): BluetoothApi | null {
  if (typeof navigator === 'undefined' || !('bluetooth' in navigator)) {
    return null;
  }

  const api: unknown = navigator.bluetooth;

  return isBluetoothApi(api) ? api : null;
}

function isBluetoothApi(value: unknown): value is BluetoothApi {
  return value instanceof Object && 'requestDevice' in value;
}

// Opens a link to the Host's Bluetooth service. The device chooser needs a user gesture, so call this synchronously
// from the click handler. Resolves once notifications are on and the link can carry pairing or hello.
export async function openBluetoothSocket(): Promise<SocketLike> {
  const api = bluetoothApi();

  if (api === null) {
    throw new Error('Bluetooth is not available in this browser.');
  }

  const device = await api.requestDevice({
    filters: [{ services: [bluetoothServiceUuid] }],
  });

  const gatt = device.gatt;

  if (gatt === undefined) {
    throw new Error('The chosen device has no GATT server.');
  }

  try {
    const server = await gatt.connect();
    const service = await server.getPrimaryService(bluetoothServiceUuid);
    const write = await service.getCharacteristic(writeCharacteristicUuid);
    const notify = await service.getCharacteristic(notifyCharacteristicUuid);
    const socket = linkSocket(device, gatt, write, notify);

    await notify.startNotifications();

    return socket;
  } catch (error) {
    gatt.disconnect();
    throw error;
  }
}

function linkSocket(
  device: BluetoothDevice,
  gatt: BluetoothRemoteGATTServer,
  write: BluetoothRemoteGATTCharacteristic,
  notify: BluetoothRemoteGATTCharacteristic,
): SocketLike {
  const reader = new BluetoothFrameReader();
  let closed = false;
  let writes: Promise<void> = Promise.resolve();

  const socket: SocketLike = {
    onOpen: null,
    onMessage: null,
    onClose: null,
    send(text) {
      // Writes run one at a time, because a Bluetooth link accepts one pending write at once.
      for (const chunk of bluetoothChunks(text)) {
        writes = writes.then(() => write.writeValueWithResponse(chunk));
      }

      writes.catch(() => gatt.disconnect());
    },
    close() {
      gatt.disconnect();
    },
  };

  notify.addEventListener('characteristicvaluechanged', () => {
    const value = notify.value;

    if (value === undefined) return;

    try {
      const bytes = new Uint8Array(
        value.buffer,
        value.byteOffset,
        value.byteLength,
      );

      for (const message of reader.append(bytes)) socket.onMessage?.(message);
    } catch {
      gatt.disconnect();
    }
  });

  device.addEventListener('gattserverdisconnected', () => {
    if (closed) return;
    closed = true;
    socket.onClose?.();
  });

  return socket;
}
