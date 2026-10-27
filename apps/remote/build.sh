#!/bin/bash
set -euo pipefail
remote_root="$(cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(cd -- "$remote_root/../.." && pwd)"
export GRADLE_USER_HOME="$project_root/.cache/gradle"
export ANDROID_USER_HOME="$project_root/.cache/android-user"
configured_sdk="$(printenv ANDROID_HOME || true)"
if [[ -z "$configured_sdk" ]]; then configured_sdk="$project_root/.tools/android-sdk"; fi
export ANDROID_HOME="$configured_sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export TMPDIR="$project_root/.cache/tmp"
mkdir -p "$TMPDIR"
variant=Debug
if [[ "$#" -ge 1 ]]; then variant="$1"; fi
[[ "$variant" == Debug || "$variant" == Release ]] || { printf '%s\n' 'Usage: build.sh [Debug|Release] [development|ci|production]' >&2; exit 2; }
profile="${2:-development}"
[[ "$profile" != production || "$variant" == Release ]] || { printf '%s\n' 'Production packaging requires Release.' >&2; exit 2; }
[[ -f "$ANDROID_HOME/platforms/android-37.0/android.jar" ]] || { printf '%s\n' 'Install Android SDK platform android-37.0 first; see docs/BUILDING.md. No SDK was downloaded.' >&2; exit 2; }
command -v javac >/dev/null || { printf '%s\n' 'An existing JDK 17+ is required.' >&2; exit 2; }
cd "$remote_root"
bash ./gradlew :app:ktlintCheck :app:testDebugUnitTest :app:lintDebug ":app:assemble$variant" "-Pcadenza.profile=$profile" --no-daemon
