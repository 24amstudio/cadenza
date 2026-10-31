# Sing model backends

The default Host backend is the pinned MIT-licensed MLX implementation and
the `mlx-community/mel-roformer-kim-vocal-2-mlx` checkpoint. Production Host
archives bundle the exact model snapshot after `fetch_model.sh` verifies its
weight, configuration, license, size, and SHA-256 pins. Development runs may fall back to the local Hugging Face
cache. All inference stays on Apple Silicon; the Remote never receives model
or audio data.

To prepare the verified archive resource manually on macOS:

```bash
bash tools/sing/fetch_model.sh apps/host/.build/sing-model
```

Run the native Apple Silicon inference benchmark against that verified model:

```bash
bash tools/sing/benchmark.sh apps/host/.build/sing-model 1 3
```

The command reports model load time, mean/min/max inference time, and realtime
factor for one-second stereo windows. Record its output with the release build,
alongside Activity Monitor or Instruments CPU, resident memory, dropped-buffer,
route-recovery, and end-to-end latency measurements.

The checkpoint is described at
<https://huggingface.co/mlx-community/mel-roformer-kim-vocal-2-mlx> and is
based on [Mel-Band RoFormer](https://arxiv.org/abs/2310.01809).

## Optional Core ML conversion

Host loads an optional `SingSeparator.mlmodelc` from its resources. The model
must expose this fixed Core ML interface:

- input `audio`: Float32 `[1, 2, frames]`;
- output `vocals`: Float32 `[1, 2, frames]`.

To create a package from a licensed TorchScript model on an Apple Silicon Mac:

```bash
python3 -m pip install torch numpy coremltools
python3 tools/sing/convert_waveform_model.py \
  --torchscript /path/to/your/separator.pt \
  --output apps/host/Resources/SingSeparator.mlpackage
```

Compile or add the generated package to the Host target so the application
bundle contains `SingSeparator.mlmodelc`. The source model must already be
available locally, and its weights, conversion code, and runtime license must
be reviewed before distribution. The tool does not fetch model files.

The converter assumes the supplied model already performs any STFT/ISTFT and
overlap-add work needed by its waveform interface. A MelBandRoformer backbone
that exposes spectrogram tensors needs a separate wrapper before conversion;
see [docs/SING.md](../../docs/SING.md).
