import {
  initialReceiverState,
  karaokeNamespace,
  reduceKaraoke,
} from './karaoke-state.js';

// The Cast receiver shows the title and, in Full Suite, the karaoke line from the Host. Playback is Music's on the Host, so
// the receiver only draws what the Host sends.
const context = cast.framework.CastReceiverContext.getInstance();
const stage = document.getElementById('stage');
const title = document.getElementById('title');
const line = document.getElementById('line');
const next = document.getElementById('next');

let state = initialReceiverState();

function render() {
  stage.dataset.mode = state.mode;
  title.textContent = state.title;
  line.textContent = state.line;
  next.textContent = state.next;
}

context.addCustomMessageListener(karaokeNamespace, (event) => {
  state = reduceKaraoke(state, event.data);
  render();
});

render();
context.start();
