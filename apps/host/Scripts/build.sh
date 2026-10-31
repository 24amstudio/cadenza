#!/bin/bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "$0")" && pwd)"
host_root="$(cd -- "$script_directory/.." && pwd)"
project_root="$(cd -- "$host_root/../.." && pwd)"
profile="${CADENZA_BUILD_PROFILE:-development}"
case "$profile" in development|ci|production) ;; *) printf '%s\n' 'Unknown build profile.' >&2; exit 2 ;; esac
[[ "$profile" != production || "${CI:-false}" != true ]] || { printf '%s\n' 'CI must not enable Production updates.' >&2; exit 2; }
# A stable identity keeps Keychain access across local builds; ad-hoc builds look like a new app to macOS.
local_signing_identity="Cadenza Host Local Signing"
if [[ -z "${CADENZA_MACOS_SIGNING_IDENTITY:-}" ]] &&
  /usr/bin/security find-identity -p codesigning 2>/dev/null | grep -qF "\"$local_signing_identity\""; then
  signing_identity="$local_signing_identity"
else
  signing_identity="${CADENZA_MACOS_SIGNING_IDENTITY:--}"
fi
printf 'Signing Host with %s\n' "$signing_identity"
if [[ "$profile" == production && "$signing_identity" == "-" ]]; then
  printf '%s\n' 'Production Host builds require CADENZA_MACOS_SIGNING_IDENTITY; ad-hoc signing would re-prompt for Keychain access after updates.' >&2
  exit 2
fi
build_identity="$(node "$project_root/tools/build-info.mjs")"
[[ "$build_identity" =~ ^([0-9a-f]{40}|source-[0-9a-f]{64})$ ]] || { printf '%s\n' 'Invalid immutable build ID.' >&2; exit 2; }

if [[ "$(uname -s)" != Darwin ]]; then
  printf '%s\n' 'Build Cadenza Host on macOS with an existing Swift 6.2+ toolchain.' >&2
  exit 2
fi

version="$(/usr/bin/awk -F= '$1 == "VERSION_NAME" {print $2}' "$project_root/shared/version.properties" | tr -d '\r')"
build="$(/usr/bin/awk -F= '$1 == "VERSION_CODE" {print $2}' "$project_root/shared/version.properties" | tr -d '\r')"
version="${CADENZA_RELEASE_VERSION:-$version}"
build="${CADENZA_BUILD_NUMBER:-$build}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(_[0-9]{8}\.[0-9]+-[0-9a-f]{12})?$ && "$build" =~ ^[0-9]+$ ]] || { printf '%s\n' 'Invalid release version or build number.' >&2; exit 2; }

export CLANG_MODULE_CACHE_PATH="$host_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$host_root/.build/module-cache"
mkdir -p "$project_root/dist" "$host_root/.build/staging"

cd "$host_root"
/usr/bin/swift build -c release --arch arm64 -Xswiftc -warnings-as-errors
binary_root="$(/usr/bin/swift build -c release --arch arm64 --show-bin-path)"
if [[ "$profile" == production ]]; then
  sing_model_directory="$host_root/.build/sing-model"
  /bin/bash "$project_root/tools/sing/fetch_model.sh" "$sing_model_directory" >/dev/null
  sing_resource_directory="$binary_root/CadenzaHost_CadenzaHost.bundle/Resources/SingModel"
  mkdir -p "$sing_resource_directory"
  cp "$sing_model_directory/model.safetensors" "$sing_resource_directory/model.safetensors"
  cp "$sing_model_directory/config.json" "$sing_resource_directory/config.json"
  cp "$sing_model_directory/LICENSE" "$sing_resource_directory/LICENSE"
else
  rm -rf "$binary_root/CadenzaHost_CadenzaHost.bundle/Resources/SingModel"
fi
stage="$(mktemp -d "$host_root/.build/staging/package.XXXXXX")"
application="$stage/Cadenza Host.app"
mkdir -p "$application/Contents/MacOS" "$application/Contents/Resources"

cp "$binary_root/CadenzaHost" "$application/Contents/MacOS/CadenzaHost"
cp "$binary_root/CadenzaUpdater" "$application/Contents/MacOS/CadenzaUpdater"
cp "$host_root/Resources/Info.plist" "$application/Contents/Info.plist"
cp -R "$binary_root/CadenzaHost_CadenzaHost.bundle" "$application/Contents/Resources/"
cp "$project_root/shared/release-config.json" "$application/Contents/Resources/release-config.json"
cp "$project_root/shared/changelog.json" "$application/Contents/Resources/changelog.json"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$application/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleVersion -string "$build" "$application/Contents/Info.plist"
/usr/bin/plutil -insert CadenzaBuildProfile -string "$profile" "$application/Contents/Info.plist"
/usr/bin/plutil -insert CadenzaBuildID -string "$build_identity" "$application/Contents/Info.plist"

/usr/bin/codesign --force --sign "$signing_identity" --timestamp=none "$application/Contents/MacOS/CadenzaUpdater"
/usr/bin/codesign --force --sign "$signing_identity" --timestamp=none --entitlements "$host_root/Resources/entitlements.plist" "$application"
/usr/bin/codesign --verify --deep --strict "$application"

archive="$project_root/dist/Cadenza-Host-$version-arm64.zip"
if [[ "$profile" != production ]]; then archive="$project_root/dist/Cadenza-Host-$version-$profile-arm64.zip"; fi
[[ ! -e "$archive" ]] || { printf '%s\n' "Archive already exists: $archive" >&2; exit 2; }
COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --keepParent "$application" "$archive"
printf '%s\n' "$application" "$archive"
