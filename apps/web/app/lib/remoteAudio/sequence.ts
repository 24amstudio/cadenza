// Classifies each audio frame's sequence number. The Host numbers every frame it produces, including the frames its
// stale-frame guard drops, so a gap tells the receiver that audio went missing on the way.

const modulus = 2 ** 32;
const half = 2 ** 31;

export type SequenceStep =
  | { kind: 'start' }
  | { kind: 'in_order' }
  | { kind: 'gap'; missing: number }
  | { kind: 'late' };

/** How a received sequence number relates to the one expected next. */
export function sequenceStep(
  expected: number | null,
  received: number,
): SequenceStep {
  if (expected === null) return { kind: 'start' };

  const difference = (((received - expected) % modulus) + modulus) % modulus;

  if (difference === 0) return { kind: 'in_order' };

  // A small positive difference is a gap, and a large one is an old frame that arrived late or twice.
  if (difference < half) return { kind: 'gap', missing: difference };

  return { kind: 'late' };
}

/** The sequence number expected after `received`. */
export function nextSequence(received: number): number {
  return (received + 1) % modulus;
}
