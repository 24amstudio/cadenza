// Wire values arrive as JSON from the Host. Every field is narrowed here before the rest of the app sees it.
export type JsonValue =
  string | number | boolean | null | JsonValue[] | { [key: string]: JsonValue };

export type JsonObject = { [key: string]: JsonValue };

export function parseJson(text: string): JsonValue | null {
  try {
    const value: JsonValue = JSON.parse(text);

    return value;
  } catch {
    return null;
  }
}

// Guards avoid runtime typeof checks. Object(value) returns the same reference only for objects, and String(value)
// returns the same string only for strings, so each comparison is exact for the JSON value set.
export function isJsonObject(
  value: JsonValue | undefined,
): value is JsonObject {
  return (
    value !== undefined &&
    value !== null &&
    !Array.isArray(value) &&
    Object(value) === value
  );
}

export function isJsonArray(
  value: JsonValue | undefined,
): value is JsonValue[] {
  return Array.isArray(value);
}

export function isJsonString(value: JsonValue | undefined): value is string {
  return value !== undefined && String(value) === value;
}

export function isJsonBoolean(value: JsonValue | undefined): value is boolean {
  return value === true || value === false;
}

// Protocol counters are nonnegative integers no larger than 2^53 - 1.
export function isCounter(value: JsonValue | undefined): value is number {
  return Number.isSafeInteger(value) && Number(value) >= 0;
}

export function stringField(object: JsonObject, key: string): string | null {
  const value = object[key];

  return isJsonString(value) ? value : null;
}

export function booleanField(object: JsonObject, key: string): boolean | null {
  const value = object[key];

  return isJsonBoolean(value) ? value : null;
}

export function counterField(object: JsonObject, key: string): number | null {
  const value = object[key];

  return isCounter(value) ? value : null;
}

export function objectField(
  object: JsonObject,
  key: string,
): JsonObject | null {
  const value = object[key];

  return isJsonObject(value) ? value : null;
}

export function arrayField(
  object: JsonObject,
  key: string,
): JsonValue[] | null {
  const value = object[key];

  return isJsonArray(value) ? value : null;
}

export function stringArrayField(
  object: JsonObject,
  key: string,
): string[] | null {
  const value = arrayField(object, key);

  if (value === null) return null;
  const strings = value.filter(isJsonString);

  return strings.length === value.length ? strings : null;
}
