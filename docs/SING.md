# Sing mode implementation

Sing keeps playback and all audio samples on Cadenza Host. Remote sends only
occurrence-bound controls and receives bounded state. The flow is:

```text
Music.app
   | Core Audio process tap
   v
stereo Float32 capture --> bounded worker queue --> separator --> AVAudioEngine output
                                                        |
                                                        +--> vocal mix control
```

The process tap is muted while the processed route is active. Host starts the
output graph before the tap, and stopping destroys the IO callback, aggregate
device, and process tap even when separation fails.

Unexpected output-engine shutdowns and final-window inference errors stop the
route and publish a failed Sing state so a Remote can offer a retry instead of
silently leaving playback muted.

AVAudioEngine configuration changes trigger one bounded output-graph rebuild;
if the new route cannot start, Host reports the failure and tears down Sing.

Capture uses a small reusable buffer pool. A full pool drops a device block and
the bounded worker queue releases every accepted buffer after processing. It
never allocates an unbounded backlog on the real-time callback.

## Production backend

The production backend uses the MIT-licensed
[`mlx-community/mel-roformer-kim-vocal-2-mlx`](https://huggingface.co/mlx-community/mel-roformer-kim-vocal-2-mlx)
checkpoint through the pinned MIT-licensed
[`mel-roformer-mlx-swift`](https://github.com/xocialize/mel-roformer-mlx-swift)
package. It runs the model's native STFT, mel-band split, transformer, mask,
and inverse-STFT path on Apple Silicon. The model implements the
[Mel-Band RoFormer](https://arxiv.org/abs/2310.01809).

The Host pins the Swift Hub client to commit
`573e5c9036c2f136b3a8a071da8e8907322403d0` and the model snapshot to commit
`64cbfcb004e39430e5f584552c05949440ec39ce`. It validates the model's
checkpoint family, sample rate, STFT, and transformer dimensions before loading
weights. A mutable Hugging Face `main` branch is never used for runtime
inference.

Production Host archives bundle the roughly 456 MB checkpoint and its MIT
license. The packaging script downloads the exact pinned revision, verifies its
size and SHA-256, and copies it into the signed Host resource bundle. Development
runs without a bundled archive fall back to the local Hugging Face cache; the
first preparation is represented by the published `preparing` state. Audio,
model bytes, and cache paths never cross the authenticated Remote session.

Cadenza resamples each device-rate window to 44.1 kHz, feeds one-second windows
with 50% overlap, and resamples the vocal estimate back to the device rate.
The model supports variable time axes, so this keeps the processing window
bounded while retaining overlap-add continuity. Preparation runs a real
one-second MLX warm-up and publishes its measured prime latency; steady-state
audio latency is measured separately in the native benchmark. Hosts that
cannot prime within the one-second live contract report failure instead of
entering a false ready state.
The vocal stem is mixed back into the original signal according to the
Remote's vocal percentage.

The deterministic stereo-center separator remains available to unit tests and
development route validation. It is not presented as neural separation.

## Backend and licensing policy

The MLX runtime and checkpoint are MIT licensed. Their notices and source
references are recorded in [`docs/credits.md`](credits.md). The other reviewed
karaoke projects remain inspiration and reference material; Cadenza does not
copy their source, model weights, or device-specific integrations.

The production backend must be benchmarked on a supported Apple Silicon Host
with the release build. Record real-time factor, end-to-end latency, CPU,
resident memory, dropped buffers, model download behavior, and recovery after
output-device changes. Portable tests cannot establish these native audio
properties.

## Optional Core ML backend

The repository also retains a source-only converter for a separately licensed
Core ML waveform model. That experimental contract is:

- input `audio`: Float32 `[1, 2, frames]`;
- output `vocals`: Float32 `[1, 2, frames]`.

See [`tools/sing/README.md`](../tools/sing/README.md). A MelBandRoFormer
backbone with spectrogram tensors needs its STFT, band-index, mask, and
inverse-STFT processing outside the model; the MLX backend already supplies
that complete path.
