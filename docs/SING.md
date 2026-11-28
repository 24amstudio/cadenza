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

Capture uses a reusable pool of 128 blocks, about 1.4 seconds at 48 kHz with
512-frame device blocks. The worker queue accepts up to the same number of
blocks, so a window that takes a while to separate does not drop device audio.
A full pool still drops a block, and the worker releases every accepted buffer
after processing. It never allocates an unbounded backlog on the real-time
callback.

Sing stays on across songs. When the current song changes, Host ends the old
occurrence, prepares the new one, and enables Sing again. A Turn off from a
Remote, or a failed start, ends that. A fresh start with the vocal level at zero
sets it to 100 percent, the unprocessed output volume. Every lower level is
quieter, because the stem mixer removes part of the vocal. The level
persists across songs until the person changes it.

Starting Sing also selects Host for the karaoke lyrics. Host then shows the
lyrics full screen in a Sing window on its Mac. The window loads `/sing` from
the Host's own Cadenza Web listener on `127.0.0.1`, and enters full screen when
it appears and leaves it when it hides. It hides when no song plays or the
karaoke output moves to This device, which is the Cast receiver. Closing the
window keeps it closed for the rest of that song. The page reads the lyrics and
the lyric clock from `/sing/live`, which accepts only the window's per-launch
access token. Another client gets 403 there.

## MLX backend (quarantined)

The intended production backend uses the MIT-licensed
[`mlx-community/mel-roformer-kim-vocal-2-mlx`](https://huggingface.co/mlx-community/mel-roformer-kim-vocal-2-mlx)
checkpoint through the pinned MIT-licensed
[`mel-roformer-mlx-swift`](https://github.com/xocialize/mel-roformer-mlx-swift)
package. It runs the model's native STFT, mel-band split, transformer, mask,
and inverse-STFT path on Apple Silicon. The model implements the
[Mel-Band RoFormer](https://arxiv.org/abs/2310.01809).

The release pins the model snapshot to commit
`64cbfcb004e39430e5f584552c05949440ec39ce`. It validates the model's
checkpoint family, sample rate, STFT, and transformer dimensions before loading
weights. A mutable Hugging Face `main` branch is never used for runtime
inference.

The roughly 456 MB checkpoint and its MIT license are never bundled in the Host
app. The release build packages the exact pinned revision as
`cadenza-sing-model-<version>.tar.gz`, publishes it beside the Host archive, and
records its size and SHA-256 in the Host's Info.plist and in the signed release
manifest. A Host installs the model only when a user presses Download in Settings,
or when a release needs a newer model than the installed one. The archive is
verified before extraction, must contain exactly the three expected files, and
replaces the installed model atomically from `Cadence Host/models/sing/`. Sing
never downloads while it prepares. Without an installed model, development builds
report `sing_model_not_installed`, and production builds keep the model-free
stereo fallback. Audio, model bytes, and cache paths never cross the
authenticated Remote session.

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

Development builds use the MLX backend, which loads its model when Sing is
prepared rather than at launch. Production builds keep the deterministic
stereo-center separator, because it is the only backend the production
capability check advertises. The MLX backend has not yet passed a release-build
validation, and no crash report for the earlier native model-load failure is
recorded. The stereo fallback is not presented as neural separation; it keeps
Sing available and lets Host report ordinary audio errors through its normal
Swift recovery path.

## Backend and licensing policy

The MLX runtime and checkpoint are MIT licensed. Their notices and source
references are recorded in [`docs/credits.md`](credits.md). The other reviewed
karaoke projects remain inspiration and reference material; Cadenza does not
copy their source, model weights, or device-specific integrations.

Before the MLX backend can be re-enabled, it must be benchmarked on a
supported Apple Silicon Host with the release build. Record real-time factor,
end-to-end latency, CPU, resident memory, dropped buffers, model download
behavior, and recovery after output-device changes. Portable tests cannot
establish these native audio properties.

## Optional Core ML backend

The repository also retains a source-only converter for a separately licensed
Core ML waveform model. That experimental contract is:

- input `audio`: Float32 `[1, 2, frames]`;
- output `vocals`: Float32 `[1, 2, frames]`.

See [`tools/sing/README.md`](../tools/sing/README.md). A MelBandRoFormer
backbone with spectrogram tensors needs its STFT, band-index, mask, and
inverse-STFT processing outside the model; the MLX backend already supplies
that complete path.
