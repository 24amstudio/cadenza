import { RemoteAudioCore } from './remote-audio/core.js';

const reportEveryQuanta = 375;

class CadenzaRemoteAudioProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.core = new RemoteAudioCore(sampleRate);
    this.framePort = null;
    this.droppedFrames = 0;
    this.reportedDropped = 0;
    this.quanta = 0;
    this.port.onmessage = (event) => {
      if (event.data.type === 'frame-port') {
        this.framePort = event.data.port;
        this.framePort.onmessage = (frameEvent) =>
          this.handleFrameMessage(frameEvent.data);
      }
    };
  }

  handleFrameMessage(message) {
    if (message.type === 'frame') {
      if (
        !this.core.write(
          message.startFrame,
          message.left,
          message.right,
          currentFrame,
        )
      ) {
        this.droppedFrames += 1;
      }
    } else if (message.type === 'target') {
      this.core.setTargetFill(message.frames);
    } else if (message.type === 'flush') {
      this.core.flush();
    }
  }

  process(_inputs, outputs) {
    const output = outputs[0];
    const left = output[0];
    const right = output[1] ?? output[0];

    this.core.render(left, right);

    this.quanta += 1;

    if (this.quanta % reportEveryQuanta === 0) {
      this.report();
    }

    return true;
  }

  report() {
    const { concealedFrames, underrunFrames } = this.core.takeStats();
    const dropped = this.droppedFrames - this.reportedDropped;

    if (dropped === 0 && concealedFrames === 0 && underrunFrames === 0) return;

    this.reportedDropped = this.droppedFrames;
    this.framePort?.postMessage({
      type: 'stats',
      dropped,
      concealed: concealedFrames,
      underrun: underrunFrames,
    });
  }
}

registerProcessor('cadenza-remote-audio', CadenzaRemoteAudioProcessor);
