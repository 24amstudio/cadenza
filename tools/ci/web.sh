#!/bin/bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "$0")/../.." && pwd)"
export BUN_INSTALL_CACHE_DIR="$project_root/.cache/bun"
export TMPDIR="$project_root/.cache/tmp"
mkdir -p "$TMPDIR"
# CI bootstrap only. Local development always uses the Bun already on the system PATH.
archive="$TMPDIR/bun.zip"
curl --fail --location --proto '=https' --tlsv1.2 'https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-linux-x64.zip' -o "$archive"
printf '%s\n' 'bf8ccbfb2b0b80159e0f9a6d15c55317add8077534dbc6130a3edb52fccb395c  '"$archive" | sha256sum --check --strict
unzip -q "$archive" -d "$TMPDIR/bun-install"
mkdir -p "$HOME/.bun/bin"
install -m 755 "$TMPDIR/bun-install/bun-linux-x64/bun" "$HOME/.bun/bin/bun"
export PATH="$HOME/.bun/bin:$PATH"
export SYSTEM_BUN="$(command -v bun)"
"$SYSTEM_BUN" --version
cd "$project_root/apps/web"
"$SYSTEM_BUN" install --frozen-lockfile
"$SYSTEM_BUN" run typecheck
"$SYSTEM_BUN" run lint
"$SYSTEM_BUN" run format:check
"$SYSTEM_BUN" run test
"$SYSTEM_BUN" run generate
# The browser Remote is served as static files by Cadenza Host, so the build must not produce a server bundle.
test ! -e .output/server
