import {
  isJsonArray,
  isJsonObject,
  isJsonString,
  parseJson,
  type JsonValue,
} from '../protocol/json';

// Session logs for the browser console. They show each frame in the order it crossed the transport, so the whole
// conversation can be followed in DevTools. Secrets and base64 payloads are replaced before anything is logged.
export type TraceDirection = 'out' | 'in';

export type TraceTransport = 'websocket' | 'bluetooth';

const secretKeys = new Set(['token', 'secret', 'pin']);
const payloadKeys = new Set(['artwork_data_base64', 'data_base64']);

export function traceEvent(message: string, ...details: unknown[]): void {
  console.debug(`[cadenza] ${message}`, ...details);
}

export function traceFrame(
  direction: TraceDirection,
  transport: TraceTransport,
  text: string,
): void {
  const frame = parseJson(text);

  if (frame === null) {
    traceEvent(
      `${direction} ${transport} unparseable frame`,
      `${text.length} characters`,
    );

    return;
  }

  const type =
    isJsonObject(frame) && isJsonString(frame.type) ? frame.type : 'unknown';

  traceEvent(`${direction} ${transport} ${type}`, redact(frame));
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
