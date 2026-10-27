#!/bin/bash
set -euo pipefail
remote_root="$(cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(cd -- "$remote_root/../.." && pwd)"
export GRADLE_USER_HOME="$project_root/.cache/gradle"
export ANDROID_USER_HOME="$project_root/.cache/android-user"
configured_sdk="$(printenv ANDROID_HOME || true)"
if [[ -z "$configured_sdk" ]]; then configured_sdk="$project_root/.tools/android-sdk"; fi
export ANDROID_HOME="$configured_sdk"
export ANDROID_SDK_ROOT="$configured_sdk"
export TMPDIR="$project_root/.cache/tmp"
mkdir -p "$TMPDIR"
[[ -f "$ANDROID_HOME/platforms/android-37.0/android.jar" ]] || { printf '%s\n' 'Android SDK platform android-37.0 is required for native checks. Nothing was downloaded.' >&2; exit 2; }
command -v javac >/dev/null || { printf '%s\n' 'An existing JDK 17+ is required.' >&2; exit 2; }
cd "$remote_root"
bash ./gradlew :app:ktlintCheck :app:testDebugUnitTest :app:testReleaseUnitTest :app:lintDebug :app:lintRelease :app:compileDebugKotlin :app:compileReleaseKotlin --no-daemon
