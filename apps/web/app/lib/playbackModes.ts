import type { RepeatMode } from './protocol/types';

// Pressing Repeat steps through off, all, then one, as Music's own control does.
const repeatCycle: Record<RepeatMode, RepeatMode> = {
  off: 'all',
  all: 'one',
  one: 'off',
};

export function nextRepeat(mode: RepeatMode): RepeatMode {
  return repeatCycle[mode];
}

const repeatNames: Record<RepeatMode, string> = {
  off: 'off',
  all: 'all songs',
  one: 'this song',
};

// States the current setting and what a press does, so the button reads the same to a screen reader as it looks.
export function repeatLabel(mode: RepeatMode): string {
  return `Repeat ${repeatNames[mode]}. Press to ${
    mode === 'one'
      ? 'turn repeat off'
      : `repeat ${repeatNames[nextRepeat(mode)]}`
  }.`;
}
