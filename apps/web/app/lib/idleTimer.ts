export interface IdleTimerOptions {
  timeoutMs: number;
  schedule: (callback: () => void, delayMs: number) => () => void;
  onChange: (idle: boolean) => void;
}

// Reports idleness after a stretch with no activity. It counts only while enabled, so a paused song or a song without
// lyrics never hides its controls. Any activity shows the controls again and restarts the countdown.
export class IdleTimer {
  private readonly options: IdleTimerOptions;
  private enabled = false;
  private idle = false;
  private cancelCountdown: (() => void) | null = null;

  constructor(options: IdleTimerOptions) {
    this.options = options;
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;

    if (!enabled) {
      this.stopCountdown();
      this.setIdle(false);

      return;
    }

    this.restartCountdown();
  }

  activity(): void {
    this.setIdle(false);

    if (this.enabled) this.restartCountdown();
  }

  private restartCountdown(): void {
    this.stopCountdown();
    this.cancelCountdown = this.options.schedule(() => {
      this.cancelCountdown = null;
      this.setIdle(true);
    }, this.options.timeoutMs);
  }

  private stopCountdown(): void {
    this.cancelCountdown?.();
    this.cancelCountdown = null;
  }

  private setIdle(idle: boolean): void {
    if (this.idle === idle) return;

    this.idle = idle;
    this.options.onChange(idle);
  }
}
