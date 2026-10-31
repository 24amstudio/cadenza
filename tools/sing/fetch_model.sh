#!/bin/bash
set -euo pipefail

output_directory="${1:-}"
[[ -n "$output_directory" ]] || {
    printf '%s\n' 'Usage: fetch_model.sh <output-directory>' >&2
    exit 2
}

repository='mlx-community/mel-roformer-kim-vocal-2-mlx'
revision='64cbfcb004e39430e5f584552c05949440ec39ce'
model_bytes='456483463'
model_sha256='312c38e5b698f8dfaa4d6064e8f79010744825828917871a9d22673a43eb7fe'
config_bytes='833'
config_sha256='3300eacac960ab46933ef6df6b838eb35de1f0321db9242c1b06e6d2a6a62b58'
license_bytes='1500'
license_sha256='1aa245b55067df5c63c847894e7040f76fa79ddde83e9e5ed8a5c29ef1865c14'
base_url="https://huggingface.co/$repository/resolve/$revision"
download_query='?download=true'
temporary_directory="${output_directory}.tmp.$$"

matches_pin() {
    local file="$1"
    local expected_bytes="$2"
    local expected_sha256="$3"
    [[ "$(wc -c < "$file" | tr -d ' ')" == "$expected_bytes" ]] \
        && [[ "$(/usr/bin/shasum -a 256 "$file" | awk '{print $1}')" == "$expected_sha256" ]]
}

mkdir -p "$(dirname "$output_directory")"
if [[ -f "$output_directory/model.safetensors" && -f "$output_directory/config.json" && -f "$output_directory/LICENSE" ]]; then
    if matches_pin "$output_directory/model.safetensors" "$model_bytes" "$model_sha256" \
        && matches_pin "$output_directory/config.json" "$config_bytes" "$config_sha256" \
        && matches_pin "$output_directory/LICENSE" "$license_bytes" "$license_sha256"; then
        printf '%s\n' "$output_directory"
        exit 0
    fi
fi

rm -rf "$temporary_directory"
mkdir -p "$temporary_directory"
trap 'rm -rf "$temporary_directory"' EXIT

model_attempt=1
while (( model_attempt <= 3 )); do
    rm -f "$temporary_directory/model.safetensors"
    if /usr/bin/curl --fail --location --http1.1 --header 'Accept-Encoding: identity' \
        --retry 3 --retry-all-errors --retry-delay 2 --silent --show-error \
        "$base_url/model.safetensors$download_query" --output "$temporary_directory/model.safetensors" \
        && matches_pin "$temporary_directory/model.safetensors" "$model_bytes" "$model_sha256"; then
        break
    fi
    if (( model_attempt == 3 )); then
        printf '%s\n' 'The pinned Sing model bytes or hash did not match.' >&2
        exit 1
    fi
    model_attempt=$((model_attempt + 1))
done
/usr/bin/curl --fail --location --http1.1 --header 'Accept-Encoding: identity' \
    --retry 3 --retry-all-errors --retry-delay 2 --silent --show-error \
    "$base_url/config.json$download_query" --output "$temporary_directory/config.json"
/usr/bin/curl --fail --location --http1.1 --header 'Accept-Encoding: identity' \
    --retry 3 --retry-all-errors --retry-delay 2 --silent --show-error \
    "$base_url/LICENSE$download_query" --output "$temporary_directory/LICENSE"

matches_pin "$temporary_directory/config.json" "$config_bytes" "$config_sha256" || {
    printf '%s\n' 'The pinned Sing model configuration did not match.' >&2
    exit 1
}
matches_pin "$temporary_directory/LICENSE" "$license_bytes" "$license_sha256" || {
    printf '%s\n' 'The pinned Sing model license did not match.' >&2
    exit 1
}

rm -rf "$output_directory"
mv "$temporary_directory" "$output_directory"
trap - EXIT
printf '%s\n' "$output_directory"
