// Playout core for the Wi-Fi Remote audio worklet. It has no imports, so the worklet loads it as a module and the Bun
// tests import it directly. Frames are written at absolute sample positions on the AudioContext timeline, which is the
// position the Host's clock mapping computed. Reads follow the output clock at a rate that a PI controller trims by at

/** Proportional gain, per millisecond of fill error. */
export const proportionalGain = 0.00015;
/** Integral gain, per millisecond of fill error and second. */

export const integralGain = 0.000008;
/** The largest rate correction: ±500 ppm. */

export const maximumCorrection = 0.0005;
/** A 3 ms raised-cosine crossfade across each gap, at 48 kHz. */

export const gapFadeSamples = 144;
export const concealMaxGapFrames = 2_400;
export const concealBudgetFrames = 480;
export const concealRampFrames = 144;

const concealMinLag = 32;
const concealMaxLag = 480;
const concealWindowFrames = 480;

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

function fadeInGain(index, length) {
  return 0.5 - 0.5 * Math.cos((Math.PI * index) / length);
}

function fadeOutGain(index, length) {
  return 0.5 + 0.5 * Math.cos((Math.PI * index) / length);
}

function concealGain(index, budget) {
  const hold = budget / 2;

  if (index < hold) return 1;

  const position = Math.min(1, (index - hold) / (budget - hold));

  return 0.5 + 0.5 * Math.cos(Math.PI * position);
}

function joinWeight(index, ramp) {
  return index < ramp ? 1 - index / ramp : 0;
}

export class RemoteAudioCore {
  #left;
  #right;
  #mask;
  #sampleRate;
  #targetFill;
  #pi = new PiRateController();
  /** The output position being read, in AudioContext frames. Null until the first write after a flush. */
  #readPosition = null;
  /** The first frame that holds written audio. Reads before it are silence. */
  #validFrom = null;
  /** The frame after the last written sample. */
  #writeEnd = null;
  #stopAt = null;
  #fadeInNext = false;
  #runDryStart = null;
  #runDryLag = 0;
  #runDryJoinLeft = 0;
  #runDryJoinRight = 0;
  #rate = 1;
  #concealedFrames = 0;
  #underrunFrames = 0;

  constructor(sampleRate, capacity = 65_536) {
    if (
      !Number.isInteger(capacity) ||
      capacity <= 0 ||
      (capacity & (capacity - 1)) !== 0
    ) {
      throw new RangeError('The buffer capacity must be a power of two');
    }

    this.#sampleRate = sampleRate;
    this.#mask = capacity - 1;
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

  flush() {
    if (this.#readPosition !== null) {
      const start = Math.floor(this.#readPosition);

      const count = Math.max(
        0,
        Math.min(gapFadeSamples, this.#writeEnd - start),
      );

      this.#fadeOutBuffered(start, count);
      this.#writeEnd = start + count;
      this.#stopAt = this.#writeEnd;
    }

    this.#runDryStart = null;
    this.#fadeInNext = true;
    this.#rate = 1;
    this.#pi.reset();
  }

  /**
   * Writes one frame at its playout position. `currentFrame` is the output clock. Audio older than the read position
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

    const readFrame = Math.floor(this.#readPosition);

    if (from < readFrame) {
      const skip = Math.min(frames, readFrame - from);
      from += skip;
      source += skip;
      count -= skip;
    }

    if (count <= 0 || from + count - this.#readPosition > this.#left.length) {
      return false;
    }

    const gapStart = this.#writeEnd;
    // A gap of a frame or two is rounding in the Host's timeline, so it is filled without a fade.
    const gapFrames = from - gapStart;
    const isGap = gapFrames > 2;
    const fadeIn = isGap || this.#fadeInNext;
    const fadeLength = Math.min(gapFadeSamples, count);
    this.#fadeInNext = false;

    if (isGap && gapFrames <= concealMaxGapFrames) {
      if (!this.#concealGap(gapStart, from)) {
        this.#zeroRange(gapStart, from);
        this.#fadeOutTail(gapStart);
      }
    } else {
      if (gapFrames > 0) {
        this.#zeroRange(gapStart, from);
      }

      if (isGap) {
        this.#fadeOutTail(gapStart);
      }
    }

    const left_ = this.#left;
    const right_ = this.#right;

    for (let index = 0; index < count; index += 1) {
      const gain =
        fadeIn && index < fadeLength ? fadeInGain(index, fadeLength) : 1;

      const slot = (from + index) & this.#mask;

      left_[slot] = left[source + index] * gain;
      right_[slot] = right[source + index] * gain;
    }

    this.#runDryStart = null;
    this.#stopAt = null;
    this.#writeEnd = Math.max(this.#writeEnd, from + count);

    return true;
  }

  /** Fills one render quantum. Silence is written until the first write, and it advances the output clock. */
  render(outLeft, outRight) {
    const frames = outLeft.length;

    if (this.#writeEnd === null || this.#readPosition === null) {
      outLeft.fill(0);
      outRight.fill(0);

      return;
    }

    if (this.#stopAt === null) {
      this.#updateRate(frames);
      this.#runDry(Math.ceil(this.#readPosition) + frames + 1);
    }

    const left = this.#left;
    const right = this.#right;
    const mask = this.#mask;

    for (let index = 0; index < frames; index += 1) {
      const position = this.#readPosition;

      if (position >= this.#validFrom && position < this.#writeEnd) {
        const base = Math.floor(position);
        const fraction = position - base;
        const slot = base & mask;
        const next = (slot + 1) & mask;

        outLeft[index] = left[slot] + (left[next] - left[slot]) * fraction;
        outRight[index] = right[slot] + (right[next] - right[slot]) * fraction;
      } else {
        outLeft[index] = 0;
        outRight[index] = 0;

        if (this.#runDryStart !== null) this.#underrunFrames += 1;
      }

      this.#readPosition += this.#rate;
    }

    if (this.#stopAt !== null && this.#readPosition >= this.#stopAt) {
      this.#idle();
    }
  }

  takeStats() {
    const stats = {
      concealedFrames: this.#concealedFrames,
      underrunFrames: this.#underrunFrames,
    };

    this.#concealedFrames = 0;
    this.#underrunFrames = 0;

    return stats;
  }

  #idle() {
    this.#readPosition = null;
    this.#validFrom = null;
    this.#writeEnd = null;
    this.#stopAt = null;
    this.#runDryStart = null;
    this.#rate = 1;
  }

  #updateRate(frames) {
    const errorMs =
      ((this.fillFrames - this.#targetFill) / this.#sampleRate) * 1_000;

    this.#rate = 1 + this.#pi.update(errorMs, frames / this.#sampleRate);
  }

  #findPeriod(end) {
    const window = Math.min(concealWindowFrames, end - this.#validFrom);
    const maxLag = Math.min(concealMaxLag, Math.floor(window / 2));

    if (maxLag < concealMinLag) return null;

    const left = this.#left;
    const mask = this.#mask;
    let best = null;
    let bestScore = 0;

    for (let lag = concealMinLag; lag <= maxLag; lag += 1) {
      let cross = 0;
      let energyNow = 0;
      let energyPast = 0;

      for (let n = end - window + lag; n < end; n += 1) {
        const now = left[n & mask];
        const past = left[(n - lag) & mask];

        cross += now * past;
        energyNow += now * now;
        energyPast += past * past;
      }

      const norm = Math.sqrt(energyNow * energyPast);

      if (norm > 0) {
        const score = cross / norm;

        if (score > bestScore) {
          bestScore = score;
          best = lag;
        }
      }
    }

    return best;
  }

  #repeatLagAt(end) {
    const period = this.#findPeriod(end);

    if (period !== null) return period;

    if (end - this.#validFrom < concealMinLag) return null;

    return concealMinLag;
  }

  #concealGap(gapStart, end) {
    const lag = this.#repeatLagAt(gapStart);

    if (lag === null) return false;

    const left = this.#left;
    const right = this.#right;
    const mask = this.#mask;
    const budget = end - gapStart;
    const ramp = Math.min(concealRampFrames, budget);

    const joinLeft =
      left[(gapStart - 1) & mask] - left[(gapStart - lag) & mask];

    const joinRight =
      right[(gapStart - 1) & mask] - right[(gapStart - lag) & mask];

    for (let index = 0; index < budget; index += 1) {
      const source = (gapStart - lag + (index % lag)) & mask;
      const gain = concealGain(index, budget);
      const weight = joinWeight(index, ramp);
      const slot = (gapStart + index) & mask;

      left[slot] = left[source] * gain + joinLeft * weight;
      right[slot] = right[source] * gain + joinRight * weight;
    }

    this.#concealedFrames += budget;

    return true;
  }

  #runDry(needEnd) {
    if (this.#writeEnd === null || needEnd <= this.#writeEnd) return;

    if (this.#readPosition < this.#validFrom) return;

    if (this.#runDryStart === null) {
      const lag = this.#repeatLagAt(this.#writeEnd);

      if (lag === null) return;

      const mask = this.#mask;
      const last = (this.#writeEnd - 1) & mask;
      const past = (this.#writeEnd - lag) & mask;

      this.#runDryStart = this.#writeEnd;
      this.#runDryLag = lag;
      this.#runDryJoinLeft = this.#left[last] - this.#left[past];
      this.#runDryJoinRight = this.#right[last] - this.#right[past];
    }

    const start = this.#runDryStart;
    const lag = this.#runDryLag;
    const end = Math.min(needEnd, start + concealBudgetFrames);
    const mask = this.#mask;
    const left = this.#left;
    const right = this.#right;

    for (let frame = this.#writeEnd; frame < end; frame += 1) {
      const index = frame - start;
      const source = (start - lag + (index % lag)) & mask;
      const gain = concealGain(index, concealBudgetFrames);
      const weight = joinWeight(index, concealRampFrames);
      const slot = frame & mask;

      left[slot] = left[source] * gain + this.#runDryJoinLeft * weight;
      right[slot] = right[source] * gain + this.#runDryJoinRight * weight;
    }

    if (end > this.#writeEnd) {
      this.#underrunFrames += end - this.#writeEnd;
      this.#writeEnd = end;
    }
  }

  #zeroRange(from, to) {
    const mask = this.#mask;

    for (let frame = from; frame < to; frame += 1) {
      const slot = frame & mask;

      this.#left[slot] = 0;
      this.#right[slot] = 0;
    }
  }

  /** Fades out the unread tail before a gap, so the cut is not a click. */
  #fadeOutTail(gapStart) {
    const start = Math.max(
      gapStart - gapFadeSamples,
      Math.floor(this.#readPosition),
    );

    this.#fadeOutBuffered(start, gapStart - start);
  }

  #fadeOutBuffered(start, count) {
    const mask = this.#mask;

    for (let index = 0; index < count; index += 1) {
      const gain = fadeOutGain(index, count);
      const slot = (start + index) & mask;

      this.#left[slot] *= gain;
      this.#right[slot] *= gain;
    }
  }
}
