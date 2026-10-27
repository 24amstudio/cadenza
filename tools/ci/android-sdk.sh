#!/bin/bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
export ANDROID_USER_HOME="$project_root/.cache/android-user"
mkdir -p "$ANDROID_USER_HOME"
sdkmanager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
[[ -x "$sdkmanager" ]] || { printf '%s\n' 'The runner must provide Android SDK command-line tools.' >&2; exit 2; }
"$sdkmanager" --install 'platforms;android-37.0' 'build-tools;36.0.0'
