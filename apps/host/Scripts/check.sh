#!/bin/bash
set -euo pipefail
script_directory="$(cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_directory/.."

[[ "$(uname -s)" == Darwin ]] || { printf '%s\n' 'Native Host checks require macOS.' >&2; exit 2; }
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
/usr/bin/swift format lint --strict --recursive Package.swift Sources Tests
/usr/bin/swift test -Xswiftc -warnings-as-errors
