#!/bin/bash
# Packages a fetched Sing model directory as the release archive that Cadenza Host downloads and verifies.
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "$0")" && pwd)"
[[ "$#" -eq 2 ]] || { printf '%s\n' 'Usage: package_model.sh <model-directory> <output-directory>' >&2; exit 2; }
source "$script_directory/model.env"
model_directory="$1"
output_directory="$2"
for file in model.safetensors config.json LICENSE; do
  [[ -f "$model_directory/$file" ]] || { printf 'The Sing model directory is missing %s.\n' "$file" >&2; exit 2; }
done
mkdir -p "$output_directory"
archive="$output_directory/cadenza-sing-model-$model_version.tar.gz"
rm -f "$archive"
# COPYFILE_DISABLE keeps AppleDouble metadata out of the archive. Cadenza Host accepts exactly these three entries.
COPYFILE_DISABLE=1 /usr/bin/tar -czf "$archive" -C "$model_directory" model.safetensors config.json LICENSE
printf '%s\n' "$archive"
