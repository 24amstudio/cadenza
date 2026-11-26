import { describe, expect, test } from 'bun:test';
import { traceEvent } from '../app/lib/host/trace';
import { sharedLocalLog } from '../app/lib/host/localLog';

// The trace text is what the Host receives from this page's log, so it is read back from there.
function lastRecordedText(): string {
  const entries = sharedLocalLog().pending();
  const last = entries[entries.length - 1];

  return last?.message ?? '';
}

describe('Bluetooth trace details', () => {
  test('a failure is recorded by its name and message, not as an empty object', () => {
    traceEvent(
      'bluetooth: connection failed',
      new DOMException('Unable to connect', 'NetworkError'),
    );

    expect(lastRecordedText()).toContain('"name":"NetworkError"');
    expect(lastRecordedText()).toContain('"message":"Unable to connect"');
    expect(lastRecordedText()).not.toContain('{}');
  });

  test('ordinary details are recorded unchanged', () => {
    traceEvent('bluetooth: notifications on', { attempt: 1 });

    expect(lastRecordedText()).toContain('{"attempt":1}');
  });
});
