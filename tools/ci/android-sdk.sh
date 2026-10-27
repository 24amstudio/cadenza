#!/bin/bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
export ANDROID_USER_HOME="$project_root/.cache/android-user"
mkdir -p "$ANDROID_USER_HOME"
sdkmanager="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
[[ -x "$sdkmanager" ]] || { printf '%s\n' 'The runner must provide Android SDK command-line tools.' >&2; exit 2; }
"$sdkmanager" --install 'platforms;android-37.0' 'build-tools;36.0.0'
debug_keystore="$ANDROID_USER_HOME/debug.keystore"
if [[ ! -f "$debug_keystore" ]]; then
  command -v keytool >/dev/null || { printf '%s\n' 'The runner must provide JDK keytool for the CI debug signer.' >&2; exit 2; }
  keytool -genkeypair \
    -keystore "$debug_keystore" \
    -storepass android \
    -keypass android \
    -alias AndroidDebugKey \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -noprompt \
    -dname 'CN=Android Debug,O=Android,C=US' \
    >/dev/null
fi
