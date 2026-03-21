#!/usr/bin/env bash
# Download and unpack Zig for x86_64-windows matching Ghostty's minimum_zig_version.
# Usage from Ghostty repo root:
#   ./msys2/ensure-zig.sh
#
# Also supported:
#   ./msys2/ensure-zig.sh PATH_TO_GHOSTTY_REPO
#   GHOSTTY_SRC=/path/to/ghostty ./msys2/ensure-zig.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPO_ROOT=""
if [[ -n "${1:-}" ]]; then
  if [[ -d "$1" && -f "$1/build.zig.zon" ]]; then
    REPO_ROOT="$(cd "$1" && pwd)"
  else
    echo "error: first arg is not a Ghostty repo: $1" >&2
    exit 1
  fi
elif [[ -n "${GHOSTTY_SRC:-}" ]]; then
  REPO_ROOT="$(cd "$GHOSTTY_SRC" && pwd)"
elif [[ -f "$PWD/build.zig.zon" ]]; then
  REPO_ROOT="$PWD"
elif [[ -f "$SCRIPT_DIR/../build.zig.zon" ]]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  echo "usage: $0 [PATH_TO_GHOSTTY_REPO]" >&2
  echo "   run from repo root: ./msys2/ensure-zig.sh" >&2
  echo "   or: GHOSTTY_SRC=/path/to/ghostty $0" >&2
  exit 1
fi

ZON="$REPO_ROOT/build.zig.zon"

if [[ ! -f "$ZON" ]]; then
  echo "error: build.zig.zon not found at $ZON" >&2
  exit 1
fi

# minimum_zig_version = "0.15.2"
ZIG_VER="$(sed -n 's/^[[:space:]]*\.minimum_zig_version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ZON" | head -1)"
if [[ -z "$ZIG_VER" ]]; then
  echo "error: could not parse minimum_zig_version from $ZON" >&2
  exit 1
fi

DEST="${ZIG_INSTALL_ROOT:-$HOME/.local/zig}/$ZIG_VER"
ZIP="zig-x86_64-windows-$ZIG_VER.zip"
URL="https://ziglang.org/download/$ZIG_VER/$ZIP"

if [[ -x "$DEST/zig.exe" ]]; then
  echo "Zig already present: $DEST/zig.exe"
  echo "Add to PATH for this session:"
  echo "  export PATH=\"$DEST:\$PATH\""
  exit 0
fi

echo "==> installing Zig $ZIG_VER to $DEST"
mkdir -p "$(dirname "$DEST")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "$TMP/$ZIP" "$URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "$TMP/$ZIP" "$URL"
else
  echo "error: need curl or wget to download Zig" >&2
  exit 1
fi

unzip -q "$TMP/$ZIP" -d "$TMP"
EXTRACT_DIR="$TMP/zig-x86_64-windows-$ZIG_VER"
if [[ ! -d "$EXTRACT_DIR" ]]; then
  echo "error: unexpected zip layout under $TMP" >&2
  ls -la "$TMP" >&2
  exit 1
fi

rm -rf "$DEST"
mv "$EXTRACT_DIR" "$DEST"

echo "==> installed: $DEST/zig.exe"
echo "Add to PATH:"
echo "  export PATH=\"$DEST:\$PATH\""
