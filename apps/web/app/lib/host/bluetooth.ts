import type { SocketLike } from './client';
import { traceEvent } from './trace';

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

// Each acknowledged 20-byte write costs a radio round trip, and a command frame is about a dozen of them. The chunks go
// without a response, which the Host's characteristic allows. Only the last chunk waits for one: it confirms the Host
// has the frame's bytes before the next frame starts.
export async function writeFrameChunks(
  writer: BluetoothFrameWriter,
  chunks: Uint8Array<ArrayBuffer>[],
): Promise<void> {
  const last = chunks.length - 1;

  for (const [index, chunk] of chunks.entries()) {
    if (index === last || !writer.properties.writeWithoutResponse) {
      await writer.writeValueWithResponse(chunk);
    } else {
      await writer.writeValueWithoutResponse(chunk);
    }
  }
}

// Bytes are written into one buffer that is compacted in place. Copying the whole backlog for every 20-byte value made
// a large artwork response quadratic in the number of notifications.
export class BluetoothFrameReader {
  private storage: Uint8Array<ArrayBuffer> = new Uint8Array(
    new ArrayBuffer(4096),
  );
  private start = 0;
  private end = 0;
  private expectedBytes: number | null = null;

  // Returns every message completed by this chunk. A malformed length or encoding throws, and the caller ends the link.
  append(chunk: Uint8Array): string[] {
    this.reserve(chunk.length);
    this.storage.set(chunk, this.end);
    this.end += chunk.length;
    const messages: string[] = [];

    for (;;) {
      if (this.expectedBytes === null) {
        if (this.end - this.start < 4) return messages;

        const length = readUint32(this.storage, this.start);

        if (length > maximumBluetoothFrameBytes) {
          throw new Error('Cadenza Host sent an invalid Bluetooth frame.');
        }

        this.expectedBytes = length;
        this.start += 4;
      }

      if (this.end - this.start < this.expectedBytes) return messages;

      messages.push(
        decoder.decode(
          this.storage.subarray(this.start, this.start + this.expectedBytes),
        ),
      );
      this.start += this.expectedBytes;
      this.expectedBytes = null;
    }
  }

  // Makes room for `extra` bytes. Unread bytes move to the front, or into a larger buffer if they still do not fit.
  private reserve(extra: number): void {
    if (this.end + extra <= this.storage.length) return;

    const pending = this.end - this.start;

    if (pending + extra > this.storage.length) {
      const grown = new Uint8Array(
        new ArrayBuffer(Math.max(this.storage.length * 2, pending + extra)),
      );

      grown.set(this.storage.subarray(this.start, this.end));
      this.storage = grown;
    } else {
      this.storage.copyWithin(0, this.start, this.end);
    }

    this.start = 0;
    this.end = pending;
  }
}

function readUint32(bytes: Uint8Array, offset: number): number {
  return (
    (bytes[offset] ?? 0) * 0x1000000 +
    ((bytes[offset + 1] ?? 0) << 16) +
    ((bytes[offset + 2] ?? 0) << 8) +
    (bytes[offset + 3] ?? 0)
  );
}

// Web Bluetooth types are not part of TypeScript's DOM library, so this declares only the calls the Remote makes.
interface BluetoothApi {
  requestDevice(options: {
    filters: { services: string[] }[];
  }): Promise<BluetoothDevice>;
  getDevices(): Promise<BluetoothDevice[]>;
}

interface BluetoothDevice {
  readonly id: string;
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

export interface BluetoothFrameWriter {
  readonly properties: { readonly writeWithoutResponse: boolean };
  writeValueWithResponse(value: BufferSource): Promise<void>;
  writeValueWithoutResponse(value: BufferSource): Promise<void>;
}

interface BluetoothRemoteGATTCharacteristic extends BluetoothFrameWriter {
  readonly value?: DataView;
  startNotifications(): Promise<BluetoothRemoteGATTCharacteristic>;
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
export interface BluetoothLink {
  socket: SocketLike;
  deviceId: string;
}

export async function openBluetoothSocket(): Promise<BluetoothLink> {
  const api = bluetoothApi();

  if (api === null) {
    throw new Error('Bluetooth is not available in this browser.');
  }

  const device = await api.requestDevice({
    filters: [{ services: [bluetoothServiceUuid] }],
  });

  return connectDevice(device);
}

// Reconnects to a device the browser already permits, so no chooser or user gesture is needed. Resolves to null when
// the device is not among the permitted ones or the browser cannot list them.
export async function reconnectBluetoothLink(
  deviceId: string,
): Promise<BluetoothLink | null> {
  const api = bluetoothApi();

  if (api === null) return null;

  let devices: BluetoothDevice[];

  try {
    devices = await api.getDevices();
  } catch {
    return null;
  }

  const device = devices.find((candidate) => candidate.id === deviceId);

  return device === undefined ? null : connectDevice(device);
}

async function connectDevice(device: BluetoothDevice): Promise<BluetoothLink> {
  const gatt = device.gatt;

  if (gatt === undefined) {
    throw new Error('The chosen device has no GATT server.');
  }

  traceEvent('bluetooth: connecting to GATT server');

  try {
    const server = await gatt.connect();
    const service = await server.getPrimaryService(bluetoothServiceUuid);
    const write = await service.getCharacteristic(writeCharacteristicUuid);
    const notify = await service.getCharacteristic(notifyCharacteristicUuid);
    const socket = linkSocket(device, gatt, write, notify);

    await notify.startNotifications();
    traceEvent('bluetooth: notifications on');

    return { socket, deviceId: device.id };
  } catch (error) {
    traceEvent('bluetooth: connection failed', error);
    gatt.disconnect();
    throw error;
  }
}

// The browser's device identifier for the Host this page paired with. It lets a reload reconnect silently.
const rememberedDeviceKey = 'cadenza.web.bluetoothDevice';

export function rememberedBluetoothDevice(): string | null {
  try {
    return localStorage.getItem(rememberedDeviceKey);
  } catch {
    return null;
  }
}

export function rememberBluetoothDevice(deviceId: string): void {
  try {
    localStorage.setItem(rememberedDeviceKey, deviceId);
  } catch {
    // Without storage the next visit asks for the device once more.
  }
}

export function forgetBluetoothDevice(): void {
  try {
    localStorage.removeItem(rememberedDeviceKey);
  } catch {
    // Nothing else to clear when storage is unavailable.
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
      const chunks = bluetoothChunks(text);

      // Writes run one at a time, because a Bluetooth link accepts one pending write at once.
      writes = writes.then(() => writeFrameChunks(write, chunks));

      writes.catch((error) => {
        traceEvent('bluetooth: write failed', error);
        gatt.disconnect();
      });
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
    traceEvent('bluetooth: GATT server disconnected');
    socket.onClose?.();
  });

  return socket;
}
