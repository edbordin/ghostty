#!/usr/bin/env bash
# Unified MSYS2 bootstrap for Ghostty Windows GTK experiments.
# Default behavior:
#   1) install MinGW packages
#   2) install/ensure Zig matching build.zig.zon minimum_zig_version
#
# Usage from Ghostty repo root:
#   ./msys2/bootstrap-pkgs.sh
#
# Options:
#   --pkgs-only            Install MinGW packages only
#   --zig-only             Install/ensure Zig only
#   --repo PATH            Explicit Ghostty repo root for Zig detection
#   -h, --help             Show help
#
# This script must run from MINGW64, UCRT64, or CLANG64 (not plain MSYS).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<EOF
usage: $0 [--pkgs-only|--zig-only] [--repo PATH]

examples:
  ./msys2/bootstrap-pkgs.sh
  ./msys2/bootstrap-pkgs.sh --pkgs-only
  ./msys2/bootstrap-pkgs.sh --zig-only
  ./msys2/bootstrap-pkgs.sh --zig-only --repo /c/path/to/ghostty
EOF
}

do_pkgs=1
do_zig=1
repo_arg=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --pkgs-only)
    do_zig=0
    shift
    ;;
  --zig-only)
    do_pkgs=0
    shift
    ;;
  --repo)
    if [[ $# -lt 2 ]]; then
      echo "error: --repo requires a path argument" >&2
      usage
      exit 1
    fi
    repo_arg="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown argument: $1" >&2
    usage
    exit 1
    ;;
  esac
done

if [[ "$do_pkgs" -eq 1 ]]; then
  case "${MSYSTEM:-}" in
  MINGW64 | UCRT64 | CLANG64) ;;
  *)
    echo "error: run this script from a MinGW shell (MINGW64, UCRT64, or CLANG64)." >&2
    echo "  Current MSYSTEM=${MSYSTEM:-<unset>}" >&2
    exit 1
    ;;
  esac

  if [[ -z "${MINGW_PACKAGE_PREFIX:-}" ]]; then
    echo "error: MINGW_PACKAGE_PREFIX is unset; your MSYS2 environment may be broken." >&2
    exit 1
  fi

  echo "==> pacman sync (you may need to restart the shell if pacman asks)"
  pacman -Syyu --noconfirm || true

  echo "==> installing Ghostty build dependencies (${MINGW_PACKAGE_PREFIX}-*)"
  # GTK path: gtk4 + libadwaita; Zig builds other deps from build.zig.zon.
  pacman -S --needed --noconfirm \
    base-devel \
    git \
    unzip \
    "${MINGW_PACKAGE_PREFIX}-toolchain" \
    "${MINGW_PACKAGE_PREFIX}-freetype" \
    "${MINGW_PACKAGE_PREFIX}-gtk4" \
    "${MINGW_PACKAGE_PREFIX}-libadwaita" \
    "${MINGW_PACKAGE_PREFIX}-blueprint-compiler" \
    "${MINGW_PACKAGE_PREFIX}-pkgconf" \
    "${MINGW_PACKAGE_PREFIX}-glib2" \
    "${MINGW_PACKAGE_PREFIX}-libffi" \
    "${MINGW_PACKAGE_PREFIX}-libiconv"

  echo "==> packages done."
  echo "    Optional: ${MINGW_PACKAGE_PREFIX}-pandoc if you enable docs."
  echo "    If zig build fails missing a system lib, try: pacman -Ss <name> and install the ${MINGW_PACKAGE_PREFIX} package."
fi

if [[ "$do_zig" -eq 1 ]]; then
  REPO_ROOT=""
  if [[ -n "$repo_arg" ]]; then
    if [[ -d "$repo_arg" && -f "$repo_arg/build.zig.zon" ]]; then
      REPO_ROOT="$(cd "$repo_arg" && pwd)"
    else
      echo "error: --repo is not a Ghostty repo: $repo_arg" >&2
      exit 1
    fi
  elif [[ -n "${GHOSTTY_SRC:-}" ]]; then
    REPO_ROOT="$(cd "$GHOSTTY_SRC" && pwd)"
  elif [[ -f "$PWD/build.zig.zon" ]]; then
    REPO_ROOT="$PWD"
  elif [[ -f "$SCRIPT_DIR/../build.zig.zon" ]]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  else
    echo "error: could not locate Ghostty repo for Zig version detection." >&2
    echo "  run from repo root, set GHOSTTY_SRC, or pass --repo PATH." >&2
    exit 1
  fi

  ZON="$REPO_ROOT/build.zig.zon"
  ZIG_VER="$(sed -n 's/^[[:space:]]*\.minimum_zig_version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ZON" | head -1)"
  if [[ -z "$ZIG_VER" ]]; then
    echo "error: could not parse minimum_zig_version from $ZON" >&2
    exit 1
  fi

  DEST="${ZIG_INSTALL_ROOT:-$HOME/.local/zig}/$ZIG_VER"
  ZIP="zig-x86_64-windows-$ZIG_VER.zip"
  URL="https://ziglang.org/download/$ZIG_VER/$ZIP"

  if [[ -x "$DEST/zig.exe" ]]; then
    echo "==> Zig already present: $DEST/zig.exe"
    echo "    export PATH=\"$DEST:\$PATH\""
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

  echo "==> Zig installed: $DEST/zig.exe"
  echo "    export PATH=\"$DEST:\$PATH\""
fi
