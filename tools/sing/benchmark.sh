#!/bin/bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(cd -- "$script_directory/../.." && pwd)"
model_directory="${1:-$project_root/apps/host/.build/sing-model}"
duration_seconds="${2:-1}"
iterations="${3:-3}"

cd "$project_root/apps/host"
/usr/bin/swift run -c release --arch arm64 CadenzaSingBenchmark \
    "$model_directory" "$duration_seconds" "$iterations"
