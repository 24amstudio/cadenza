import {
  isJsonArray,
  isJsonObject,
  isJsonString,
  parseJson,
  type JsonValue,
} from '../protocol/json';
import { sharedLocalLog } from './localLog';

// Session logs for the browser console. They show each frame in the order it crossed the transport, so the whole
// conversation can be followed in DevTools. Secrets and base64 payloads are replaced before anything is logged.
export type TraceDirection = 'out' | 'in';

export type TraceTransport = 'websocket' | 'bluetooth';

const secretKeys = new Set(['token', 'secret', 'pin']);
const payloadKeys = new Set(['artwork_data_base64', 'data_base64']);

// Each trace is also kept in this browser's log, which the Host receives once it is connected.
export function traceEvent(message: string, ...details: unknown[]): void {
  console.debug(`[cadenza] ${message}`, ...details);

  const text = details
    .map((detail) => {
      try {
        // An Error's fields are not enumerable, so JSON.stringify would record it as {}. Its name and message are kept.
        const recorded =
          detail instanceof Error
            ? { name: detail.name, message: detail.message }
            : detail;

        return redactedText(JSON.stringify(recorded) ?? String(detail));
      } catch {
        return '(not recorded)';
      }
    })
    .join(' ');

  sharedLocalLog().record('info', message, text || message);
}

// A frame this large is an artwork or motion chunk. Parsing it only to hide its payload costs a copy of every transfer,
// so it is logged by type and size alone.
const parseLimitChars = 8_192;

export function traceFrame(
  direction: TraceDirection,
  transport: TraceTransport,
  text: string,
): void {
  if (text.length > parseLimitChars) {
    const type = /"type":"([^"]{1,64})"/.exec(text.slice(0, 256))?.[1];

    traceEvent(
      `${direction} ${transport} ${type ?? 'unknown'}`,
      `${text.length} characters`,
    );
    recordFrame(
      direction,
      transport,
      type ?? 'unknown',
      `${text.length} characters`,
    );

    return;
  }

  const frame = parseJson(text);

  if (frame === null) {
    traceEvent(
      `${direction} ${transport} unparseable frame`,
      `${text.length} characters`,
    );
    recordFrame(
      direction,
      transport,
      'unparseable',
      `${text.length} characters`,
    );

    return;
  }

  const type =
    isJsonObject(frame) && isJsonString(frame.type) ? frame.type : 'unknown';

  const shown = redact(frame);

  traceEvent(`${direction} ${transport} ${type}`, shown);

  recordFrame(direction, transport, type, JSON.stringify(shown));
}

function recordFrame(
  direction: TraceDirection,
  transport: TraceTransport,
  type: string,
  message: string,
): void {
  sharedLocalLog().record(
    'debug',
    `${direction} ${transport} ${type}`,
    message,
  );
}

function redactedText(text: string): string {
  const value = parseJson(text);

  return value === null ? text : JSON.stringify(redact(value));
}

function redact(value: JsonValue): JsonValue {
  if (isJsonArray(value)) return value.map(redact);

  if (!isJsonObject(value)) return value;

  return Object.fromEntries(
    Object.entries(value).map(([key, item]): [string, JsonValue] => [
      key,
      redactField(key, item),
    ]),
  );
}

function redactField(key: string, value: JsonValue): JsonValue {
  if (secretKeys.has(key)) return '[redacted]';

  if (payloadKeys.has(key) && isJsonString(value)) {
    return `[${value.length} base64 characters]`;
  }

  return redact(value);
}
