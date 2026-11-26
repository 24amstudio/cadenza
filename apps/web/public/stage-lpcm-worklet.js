// Plays raw float32 PCM for the Tier-2 stage. The main thread posts interleaved chunks and flushes, so no shared memory is
// needed. Each chunk is read in order, and a flush drops everything that is queued.
class CadenzaLpcmProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.chunks = [];
    this.position = 0;
    this.port.onmessage = (event) => {
      if (event.data.type === 'flush') {
        this.chunks = [];
        this.position = 0;

        return;
      }

      if (event.data.type === 'pcm' && this.chunks.length < 256) {
        this.chunks.push({
          channels: event.data.channels,
          samples: event.data.samples,
        });
      }
    };
  }

  process(_inputs, outputs) {
    const output = outputs[0];
    const frames = output[0].length;

    for (let frame = 0; frame < frames; frame += 1) {
      const chunk = this.chunks[0];

      if (!chunk) {
        for (const channel of output) channel[frame] = 0;
        continue;
      }

      const base = this.position * chunk.channels;

      for (let channel = 0; channel < output.length; channel += 1) {
        const source = Math.min(channel, chunk.channels - 1);
        output[channel][frame] = chunk.samples[base + source] ?? 0;
      }

      this.position += 1;

      if (this.position * chunk.channels >= chunk.samples.length) {
        this.chunks.shift();
        this.position = 0;
      }
    }

    return true;
  }
}

registerProcessor('cadenza-lpcm', CadenzaLpcmProcessor);
