import { describe, expect, test } from 'bun:test';
import { IdleTimer } from '../app/lib/idleTimer';

// A scheduler the test advances by hand, so the countdown runs without waiting.
class ManualClock {
  now = 0;
  private tasks: { at: number; run: () => void; cancelled: boolean }[] = [];

  schedule = (callback: () => void, delayMs: number): (() => void) => {
    const task = { at: this.now + delayMs, run: callback, cancelled: false };

    this.tasks.push(task);

    return () => {
      task.cancelled = true;
    };
  };

  advance(ms: number): void {
    const target = this.now + ms;

    for (;;) {
      const due = this.tasks
        .filter((task) => !task.cancelled && task.at <= target)
        .sort((first, second) => first.at - second.at)[0];

      if (due === undefined) break;

      this.now = due.at;
      this.tasks = this.tasks.filter((task) => task !== due);
      due.run();
    }

    this.now = target;
  }
}

function timerWith(clock: ManualClock, changes: boolean[]): IdleTimer {
  return new IdleTimer({
    timeoutMs: 10_000,
    schedule: clock.schedule,
    onChange: (idle) => changes.push(idle),
  });
}

describe('idle timer', () => {
  test('reports idle after the timeout, and activity brings the controls back', () => {
    const clock = new ManualClock();
    const changes: boolean[] = [];
    const timer = timerWith(clock, changes);

    timer.setEnabled(true);
    clock.advance(9_000);
    timer.activity();
    clock.advance(9_000);

    expect(changes).toEqual([]);

    clock.advance(1_000);
    expect(changes).toEqual([true]);

    timer.activity();
    expect(changes).toEqual([true, false]);
  });

  test('disabling clears idleness and stops the countdown, so a paused song keeps its controls', () => {
    const clock = new ManualClock();
    const changes: boolean[] = [];
    const timer = timerWith(clock, changes);

    timer.setEnabled(true);
    clock.advance(10_000);
    timer.setEnabled(false);
    clock.advance(60_000);

    expect(changes).toEqual([true, false]);
  });
});
