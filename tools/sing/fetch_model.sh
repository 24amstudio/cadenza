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
model_sha256='312c38e5b698f8dfaa4d6064e8f79010744825828917871a9d22673a43eb7fe5'
config_bytes='833'
config_sha256='3300eacac960ab46933ef6df6b838eb35de1f0321db9242c1b06e6d2a6a62b58'
license_bytes='1500'
license_sha256='1aa245b55067df5c63c847894e7040f76fa79ddde83e9e5ed8a5c29ef1865c14'
base_url="https://huggingface.co/$repository/resolve/$revision"
download_query='?download=true'
temporary_directory="${output_directory}.tmp.$$"
chunk_bytes=$((16 * 1024 * 1024))

[[ "$model_sha256" =~ ^[0-9a-f]{64}$ ]] || {
    printf '%s\n' 'The pinned Sing model SHA-256 must contain 64 lowercase hexadecimal characters.' >&2
    exit 2
}

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

rm -f "$temporary_directory/model.safetensors"
chunk_directory="$temporary_directory/model-chunks"
mkdir -p "$chunk_directory"
chunk_start=0
chunk_index=0
while (( chunk_start < model_bytes )); do
    chunk_end=$((chunk_start + chunk_bytes - 1))
    (( chunk_end >= model_bytes )) && chunk_end=$((model_bytes - 1))
    expected_chunk_bytes=$((chunk_end - chunk_start + 1))
    chunk_path="$chunk_directory/$(printf '%04d' "$chunk_index")"
    chunk_attempt=1
    while (( chunk_attempt <= 3 )); do
        rm -f "$chunk_path"
        if /usr/bin/curl --fail --location --http1.1 --header 'Accept-Encoding: identity' \
            --range "$chunk_start-$chunk_end" --retry 3 --retry-all-errors --retry-delay 2 \
            --silent --show-error "$base_url/model.safetensors$download_query" \
            --output "$chunk_path" \
            && [[ "$(wc -c < "$chunk_path" | tr -d ' ')" == "$expected_chunk_bytes" ]]; then
            break
        fi
        if (( chunk_attempt == 3 )); then
            printf 'The pinned Sing model range %s-%s could not be downloaded.\n' \
                "$chunk_start" "$chunk_end" >&2
            exit 1
        fi
        chunk_attempt=$((chunk_attempt + 1))
    done
    cat "$chunk_path" >> "$temporary_directory/model.safetensors"
    chunk_start=$((chunk_end + 1))
    chunk_index=$((chunk_index + 1))
done
rm -rf "$chunk_directory"
matches_pin "$temporary_directory/model.safetensors" "$model_bytes" "$model_sha256" || {
    actual_bytes="$(wc -c < "$temporary_directory/model.safetensors" | tr -d ' ')"
    actual_sha256="$(/usr/bin/shasum -a 256 "$temporary_directory/model.safetensors" | awk '{print $1}')"
    printf 'The pinned Sing model bytes or hash did not match after range assembly (expected %s/%s, got %s/%s).\n' \
        "$model_bytes" "$model_sha256" "$actual_bytes" "$actual_sha256" >&2
    exit 1
}
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
