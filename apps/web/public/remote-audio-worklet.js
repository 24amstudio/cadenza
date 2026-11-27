// Plays the Wi-Fi Remote audio stream. The main thread posts each frame with its absolute AudioContext position, and
// the core holds the buffer at its target fill with a PI-trimmed read rate. The core is shared with the Bun tests.
import { RemoteAudioCore } from './remote-audio/core.js';

class CadenzaRemoteAudioProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.core = new RemoteAudioCore(sampleRate);
    this.port.onmessage = (event) => {
      const message = event.data;

      if (message.type === 'frame') {
        this.core.write(
          message.startFrame,
          message.left,
          message.right,
          currentFrame,
        );
      } else if (message.type === 'target') {
        this.core.setTargetFill(message.frames);
      } else if (message.type === 'flush') {
        this.core.flush();
      }
    };
  }

  process(_inputs, outputs) {
    const output = outputs[0];
    const left = output[0];
    const right = output[1] ?? output[0];

    this.core.render(left, right);

    return true;
  }
}

registerProcessor('cadenza-remote-audio', CadenzaRemoteAudioProcessor);
