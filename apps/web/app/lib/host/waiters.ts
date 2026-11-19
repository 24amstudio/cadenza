export type Schedule = (callback: () => void, delayMs: number) => () => void;

interface Waiter {
  test: () => boolean;
  settle: (satisfied: boolean) => void;
}

// Promises that resolve when a condition on the client's state becomes true, or give up after a deadline. The owner calls
// notify after each change to that state.
export class Waiters {
  private readonly waiting = new Set<Waiter>();
  private readonly schedule: Schedule;

  constructor(schedule: Schedule) {
    this.schedule = schedule;
  }

  until(test: () => boolean, timeoutMs: number): Promise<boolean> {
    if (test()) return Promise.resolve(true);

    return new Promise((resolve) => {
      const cancel = this.schedule(() => waiter.settle(false), timeoutMs);

      const waiter: Waiter = {
        test,
        settle: (satisfied) => {
          this.waiting.delete(waiter);
          cancel();
          resolve(satisfied);
        },
      };

      this.waiting.add(waiter);
    });
  }

  notify(): void {
    for (const waiter of [...this.waiting]) {
      if (waiter.test()) waiter.settle(true);
    }
  }
}
