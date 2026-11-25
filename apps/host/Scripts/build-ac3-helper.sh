#!/bin/bash
# Builds the AC-3 encoder helper that Cast uses for six-channel output. The helper is FFmpeg 9.0.2 configured with the
# AC-3 encoder, the raw float input, and nothing else. It is LGPL-2.1-or-later: no GPL or nonfree component is enabled.
# Output: .helpers/cadenza-ac3 and its license, which build.sh copies into the app bundle.
set -euo pipefail
script_directory="$(cd -- "$(dirname -- "$0")" && pwd)"
host_root="$(cd -- "$script_directory/.." && pwd)"
version="9.0.2"
expected_sha256="8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
work="$host_root/.helpers/work"
output="$host_root/.helpers"

rm -rf "$work"
mkdir -p "$work"
curl -fsSL -o "$work/ffmpeg.tar.xz" "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz"
printf '%s  %s\n' "$expected_sha256" "$work/ffmpeg.tar.xz" | shasum -a 256 -c -
tar -xf "$work/ffmpeg.tar.xz" -C "$work"
cd "$work/ffmpeg-$version"
./configure \
  --prefix="$PWD/install" \
  --disable-everything --disable-autodetect --disable-doc --disable-network --disable-debug \
  --enable-small --disable-gpl --disable-nonfree \
  --enable-avcodec --enable-avformat --enable-avutil --enable-swresample --disable-swscale --disable-avdevice \
  --enable-avfilter --enable-filter=aresample \
  --enable-ffmpeg --disable-ffprobe --disable-ffplay \
  --enable-encoder=ac3_fixed --enable-decoder=pcm_f32le --enable-demuxer=pcm_f32le \
  --enable-muxer=ac3 --enable-demuxer=ac3 --enable-decoder=ac3 --enable-parser=ac3 \
  --enable-protocol=pipe --enable-protocol=file
make -j"$(sysctl -n hw.ncpu)"
mkdir -p "$output"
cp ffmpeg "$output/cadenza-ac3"
/usr/bin/strip -x "$output/cadenza-ac3"
cp COPYING.LGPLv2.1 "$output/COPYING.LGPLv2.1"
rm -rf "$work"
echo "Built $output/cadenza-ac3 (FFmpeg $version, LGPL-2.1-or-later)"
