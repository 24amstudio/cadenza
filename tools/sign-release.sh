#!/bin/bash
set -euo pipefail
script_directory="$(cd -- "$(dirname -- "$0")" && pwd)"
project_root="$(cd -- "$script_directory/.." && pwd)"
[[ "$#" -eq 2 ]] || { printf '%s\n' 'Usage: sign-release.sh owner/repository /private/path/update-private.pem' >&2; exit 2; }
repository="$1"
key="$2"
version="$(awk -F= '$1 == "VERSION_NAME" {print $2}' "$project_root/shared/version.properties" | tr -d '\r')"
build="$(awk -F= '$1 == "VERSION_CODE" {print $2}' "$project_root/shared/version.properties" | tr -d '\r')"
version="${CADENZA_RELEASE_VERSION:-$version}"
build="${CADENZA_BUILD_NUMBER:-$build}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(_[0-9]{8}\.[0-9]+-[0-9a-f]{12})?$ && "$build" =~ ^[0-9]+$ ]] || {
  printf '%s\n' 'Invalid release version or build number.' >&2
  exit 2
}
cd "$project_root/apps/host"
/usr/bin/swift build -c release --arch arm64 --product CadenzaRelease -Xswiftc -warnings-as-errors
binary_root="$(/usr/bin/swift build -c release --arch arm64 --show-bin-path)"
host="$project_root/dist/Cadenza-Host-$version-arm64.zip"
remote="$project_root/dist/Cadenza-Remote-$version.apk"
[[ -f "$host" && -f "$remote" ]] || { printf '%s\n' 'Build both signed release artifacts first.' >&2; exit 2; }
source_id="$(node "$project_root/tools/build-info.mjs")"
host_id="$(/usr/bin/unzip -p "$host" 'Cadenza Host.app/Contents/Info.plist' | /usr/bin/plutil -extract CadenzaBuildID raw -o - -)"
host_profile="$(/usr/bin/unzip -p "$host" 'Cadenza Host.app/Contents/Info.plist' | /usr/bin/plutil -extract CadenzaBuildProfile raw -o - -)"
remote_id="$(/usr/bin/unzip -p "$remote" assets/build-identity.txt | head -c 200 | tr -d '\r\n')"
analyzer="${ANDROID_HOME:?Set ANDROID_HOME to the checked Android SDK}/cmdline-tools/latest/bin/apkanalyzer"
remote_profile="$("$analyzer" manifest print "$remote" | /usr/bin/xmllint --xpath 'string(/manifest/application/meta-data[@*[local-name()="name"]="app.cadenza.BUILD_PROFILE"]/@*[local-name()="value"])' -)"
remote_package="$("$analyzer" manifest application-id "$remote" | tr -d '\r\n')"
[[ "$host_profile" == production && "$remote_profile" == production && "$remote_package" == app.cadence.remote && "$host_id" == "$source_id" && "$remote_id" == "$source_id" ]] || {
  printf '%s\n' 'Both Production artifacts must have been built from this exact source identity. Rebuild before signing.' >&2
  exit 2
}
"$binary_root/CadenzaRelease" manifest "$repository" "$version" "$build" "$host" "$remote" "$key" "$project_root/dist" "$source_id" "$project_root/shared/changelog.json"
printf '%s\n' 'Release metadata signed. No GitHub upload was performed.'
