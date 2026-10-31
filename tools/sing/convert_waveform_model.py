#!/usr/bin/env python3
"""Convert a supplied waveform separator to Cadenza's Core ML Sing contract.

The source model must accept Float32 [1, 2, frames] and return Float32
[1, 2, frames] vocal samples. This tool never downloads weights. Review the
source model license before distributing the generated package.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--torchscript", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--frames", type=int, default=352_800)
    parser.add_argument("--minimum-macos", default="15")
    return parser.parse_args()


def convert(args: argparse.Namespace) -> None:
    try:
        import numpy as np
        import torch
        import coremltools as ct
    except ImportError as error:
        raise SystemExit(
            "Install torch, numpy, and coremltools before converting a model: "
            "python -m pip install torch numpy coremltools"
        ) from error

    if args.frames <= 0:
        raise SystemExit("--frames must be positive.")
    if not args.torchscript.is_file():
        raise SystemExit(f"TorchScript model does not exist: {args.torchscript}")

    model = torch.jit.load(str(args.torchscript), map_location="cpu")
    model.eval()
    sample = torch.zeros((1, 2, args.frames), dtype=torch.float32)
    traced = torch.jit.trace(model, sample, strict=False, check_trace=False)
    output = ct.convert(
        traced,
        inputs=[ct.TensorType(name="audio", shape=sample.shape, dtype=np.float32)],
        outputs=[ct.TensorType(name="vocals", dtype=np.float32)],
        compute_units=ct.ComputeUnit.ALL,
        minimum_deployment_target=getattr(ct.target, f"macOS{args.minimum_macos}"),
        convert_to="mlprogram",
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.author = "Cadenza contributors"
    output.short_description = "Cadenza Sing waveform vocal separator"
    output.version = "1"
    output.user_defined_metadata.update(
        {
            "cadenza_input": "audio [1, 2, frames] Float32",
            "cadenza_output": "vocals [1, 2, frames] Float32",
            "cadenza_frames": str(args.frames),
            "cadenza_license_review": "required before distribution",
        }
    )
    output.save(str(args.output))
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    convert(parse_args())
