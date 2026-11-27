// Playout core for the Wi-Fi Remote audio worklet. It has no imports, so the worklet loads it as a module and the Bun
// tests import it directly. Frames are written at absolute sample positions on the AudioContext timeline, which is the
// position the Host's clock mapping computed. Reads follow the output clock at a rate that a PI controller trims by at
// most ±500 ppm, so the buffer stays at its target fill without dropping or repeating samples.

/** Proportional gain, per millisecond of fill error. */
export const proportionalGain = 0.00015;
/** Integral gain, per millisecond of fill error and second. */

export const integralGain = 0.000008;
/** The largest rate correction: ±500 ppm. */

export const maximumCorrection = 0.0005;
/** A 3 ms raised-cosine crossfade across each gap, at 48 kHz. */

export const gapFadeSamples = 144;

export class PiRateController {
  #integral = 0;

  /** Returns the rate correction for one fill error. The integral is clamped, so it cannot wind up past the limit. */
  update(errorMs, seconds) {
    const limit = Math.abs(maximumCorrection);
    const integralLimit = limit / integralGain;

    this.#integral = Math.min(
      integralLimit,
      Math.max(-integralLimit, this.#integral + errorMs * seconds),
    );

    return Math.min(
      limit,
      Math.max(
        -limit,
        proportionalGain * errorMs + integralGain * this.#integral,
      ),
    );
  }

  reset() {
    this.#integral = 0;
  }
}

/** Multiplies the first `count` samples of `samples` by a rising raised cosine. */
export function applyFadeIn(samples, count) {
  const length = Math.min(count, samples.length);

  for (let index = 0; index < length; index += 1) {
    samples[index] *= 0.5 - 0.5 * Math.cos((Math.PI * index) / length);
  }
}

/** Multiplies the last `count` samples of `samples` by a falling raised cosine. */
export function applyFadeOut(samples, count) {
  const length = Math.min(count, samples.length);
  const start = samples.length - length;

  for (let index = 0; index < length; index += 1) {
    samples[start + index] *= 0.5 + 0.5 * Math.cos((Math.PI * index) / length);
  }
}

export class RemoteAudioCore {
  #left;
  #right;
  #capacity;
  #sampleRate;
  #targetFill;
  #pi = new PiRateController();
  /** The output position being read, in AudioContext frames. Null until the first write after a flush. */
  #readPosition = null;
  /** The first frame that holds written audio. Reads before it are silence. */
  #validFrom = null;
  /** The frame after the last written sample. */
  #writeEnd = null;
  #rate = 1;

  constructor(sampleRate, capacity = 65_536) {
    this.#sampleRate = sampleRate;
    this.#capacity = capacity;
    this.#left = new Float32Array(capacity);
    this.#right = new Float32Array(capacity);
    this.#targetFill = Math.round(0.028 * sampleRate);
  }

  /**
   * The fill the controller holds, in frames. At a locked clock, the fill is the Host's jitter cushion plus one frame,
   * so the receiver sets this from each telemetry message. A fixed value would hold a constant pitch offset.
   */
  setTargetFill(frames) {
    this.#targetFill = Math.max(1, Math.round(frames));
  }

  get rate() {
    return this.#rate;
  }

  /** Buffered audio ahead of the read position, in frames. Zero before the first write. */
  get fillFrames() {
    if (this.#writeEnd === null || this.#readPosition === null) return 0;

    return this.#writeEnd - this.#readPosition;
  }

  /** Empties the buffer. The next write starts a new stream, and every read is silence until then. */
  flush() {
    this.#readPosition = null;
    this.#validFrom = null;
    this.#writeEnd = null;
    this.#rate = 1;
    this.#pi.reset();
  }

  /**
   * Writes one frame at its playout position. `currentFrame` is the output clock. Audio older than the read position
   * is dropped. A gap before the frame gets a fade-out at its start and a fade-in at its end.
   */
  write(startFrame, left, right, currentFrame) {
    const frames = Math.min(left.length, right.length);

    if (this.#writeEnd === null) {
      this.#validFrom = startFrame;
      this.#writeEnd = startFrame;
      this.#readPosition = Math.min(currentFrame, startFrame);
    }

    let from = startFrame;
    let count = frames;
    let source = 0;

    if (this.#readPosition !== null && from < this.#readPosition) {
      const skip = Math.min(frames, this.#readPosition - from);
      from += skip;
      source += skip;
      count -= skip;
    }

    if (count <= 0 || from + count - this.#readPosition > this.#capacity) {
      return;
    }

    const gapStart = this.#writeEnd;
    // A gap of a frame or two is rounding in the Host's timeline, so it is filled without a fade.
    const gapFrames = from - gapStart;
    const isGap = gapFrames > 2;
    const newSegment = new Float32Array(count);
    const newRight = new Float32Array(count);

    for (let index = 0; index < count; index += 1) {
      newSegment[index] = left[source + index];
      newRight[index] = right[source + index];
    }

    if (gapFrames > 0) {
      this.#zeroRange(gapStart, from);
    }

    if (isGap) {
      this.#fadeTail(gapStart);
      applyFadeIn(newSegment, gapFadeSamples);
      applyFadeIn(newRight, gapFadeSamples);
    }

    for (let index = 0; index < count; index += 1) {
      const slot = (from + index) % this.#capacity;

      this.#left[slot] = newSegment[index];
      this.#right[slot] = newRight[index];
    }

    this.#writeEnd = Math.max(this.#writeEnd, from + count);
  }

  /** Fills one render quantum. Silence is written until the first write, and it advances the output clock. */
  render(outLeft, outRight) {
    const frames = outLeft.length;

    if (this.#writeEnd === null || this.#readPosition === null) {
      outLeft.fill(0);
      outRight.fill(0);

      return;
    }

    this.#updateRate(frames);

    for (let index = 0; index < frames; index += 1) {
      const position = this.#readPosition;

      if (position >= this.#validFrom && position < this.#writeEnd) {
        const base = Math.floor(position);
        const fraction = position - base;
        const slot = base % this.#capacity;
        const next = (slot + 1) % this.#capacity;

        outLeft[index] =
          this.#left[slot] + (this.#left[next] - this.#left[slot]) * fraction;
        outRight[index] =
          this.#right[slot] +
          (this.#right[next] - this.#right[slot]) * fraction;
      } else {
        outLeft[index] = 0;
        outRight[index] = 0;
      }

      this.#readPosition += this.#rate;
    }
  }

  #updateRate(frames) {
    const errorMs =
      ((this.fillFrames - this.#targetFill) / this.#sampleRate) * 1_000;

    this.#rate = 1 + this.#pi.update(errorMs, frames / this.#sampleRate);
  }

  #zeroRange(from, to) {
    for (let frame = from; frame < to; frame += 1) {
      const slot = frame % this.#capacity;

      this.#left[slot] = 0;
      this.#right[slot] = 0;
    }
  }

  /** Fades out the unread tail before a gap, so the cut is not a click. */
  #fadeTail(gapStart) {
    const fadeFrom = Math.max(gapStart - gapFadeSamples, this.#readPosition);
    const count = gapStart - fadeFrom;

    if (count <= 0) return;

    const left = new Float32Array(count);
    const right = new Float32Array(count);

    for (let index = 0; index < count; index += 1) {
      const slot = (fadeFrom + index) % this.#capacity;

      left[index] = this.#left[slot];
      right[index] = this.#right[slot];
    }

    applyFadeOut(left, gapFadeSamples);
    applyFadeOut(right, gapFadeSamples);

    for (let index = 0; index < count; index += 1) {
      const slot = (fadeFrom + index) % this.#capacity;

      this.#left[slot] = left[index];
      this.#right[slot] = right[index];
    }
  }
}
