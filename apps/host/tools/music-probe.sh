#!/bin/bash
# Read-only feasibility tool. No installation, playback changes, or network access.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'Cadenza Music probe requires macOS. No changes were made.' >&2
  exit 2
fi

script_directory="$(cd -- "$(dirname -- "$0")" && pwd)"
command="${1:-status}"
cache_root="${HOME}/Library/Caches/com.apple.Music/fsCachedData"

usage() {
  printf '%s\n' \
    'Usage: bash music-probe.sh status|dictionary|cache|lyrics <catalog-song-id>' \
    'cache inspects at most 512 regular files and 32 MiB; it prints metadata only.' \
    'lyrics writes the matching first-record TTML to stdout when available.'
}

read_field() {
  /usr/bin/plutil -extract "$2" raw -o - -- "$1" 2>/dev/null
}

scan_cache() {
  local candidate file_bytes song_id title scanned bytes matched
  scanned=0
  bytes=0
  matched=0
  if [[ ! -d "$cache_root" || -L "$cache_root" ]]; then
    printf '%s\n' 'Music lyric cache is missing, inaccessible, or a symbolic link.' >&2
    return 3
  fi
  for candidate in "$cache_root"/*; do
    [[ -f "$candidate" && ! -L "$candidate" ]] || continue
    file_bytes="$(/usr/bin/stat -f '%z' "$candidate")" || continue
    case "$file_bytes" in ''|*[!0-9]*) continue ;; esac
    (( file_bytes <= 4194304 )) || continue
    if (( scanned >= 512 || bytes + file_bytes > 33554432 )); then
      printf '%s\n' 'Cache scan reached its limit; results may be incomplete.' >&2
      break
    fi
    scanned=$((scanned + 1))
    bytes=$((bytes + file_bytes))
    song_id="$(read_field "$candidate" 'data.0.id')" || continue
    case "$song_id" in ''|*[!0-9]*) continue ;; esac
    if [[ "$command" == "lyrics" && "$song_id" != "$2" ]]; then
      continue
    fi
    if [[ "$command" == "cache" ]]; then
      if /usr/bin/grep -q 'ttmlLocalizations' "$candidate"; then
        title="$(read_field "$candidate" 'data.0.attributes.name')" || title='unavailable'
        printf 'catalog_id=%s title=%s\n' "$song_id" "$title"
        matched=$((matched + 1))
      fi
    elif read_field "$candidate" 'data.0.relationships.syllable-lyrics.data.0.attributes.ttmlLocalizations'; then
      return 0
    elif read_field "$candidate" 'data.0.relationships.lyrics.data.0.attributes.ttmlLocalizations'; then
      return 0
    fi
  done
  if [[ "$command" == "cache" ]]; then
    printf 'scanned_files=%s lyric_candidates=%s\n' "$scanned" "$matched"
    return 0
  fi
  printf '%s\n' 'No matching cached TTML in this bounded scan. Open Music lyrics and play the song, then retry.' >&2
  return 3
}

case "$command" in
  status)
    [[ "$#" -le 1 ]] || { usage >&2; exit 2; }
    exec /usr/bin/osascript "$script_directory/music-status.applescript"
    ;;
  dictionary)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    exec /usr/bin/sdef /System/Applications/Music.app
    ;;
  cache)
    [[ "$#" -eq 1 ]] || { usage >&2; exit 2; }
    scan_cache "$command" ''
    ;;
  lyrics)
    [[ "$#" -eq 2 ]] || { usage >&2; exit 2; }
    case "$2" in ''|*[!0-9]*) usage >&2; exit 2 ;; esac
    scan_cache "$command" "$2"
    ;;
  *) usage >&2; exit 2 ;;
esac
