#!/usr/bin/env bash
# Experimental: build Ghostty on Windows (MinGW) with GTK.
# Tip: use UCRT64 (ucrt64.exe) when possible — fewer CRT/link quirks than MINGW64 for GTK + Zig.
#
# Usage from Ghostty repo root:
#   ./msys2/build-ghostty-gtk.sh [zig build args…]
#
# Also supported:
#   ./msys2/build-ghostty-gtk.sh PATH_TO_GHOSTTY_REPO [zig build args…]
#   GHOSTTY_SRC=/path/to/ghostty ./msys2/build-ghostty-gtk.sh [zig build args…]
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${MSYSTEM:-}" in
MINGW64 | UCRT64 | CLANG64) ;;
*)
  echo "error: use MINGW64, UCRT64, or CLANG64 shell." >&2
  exit 1
  ;;
esac

# Zig uses pkg-config to resolve native libs. If the wrong pkg-config is first
# on PATH (e.g. MSYS /usr/bin), you get "searched paths: none".
if [[ -z "${MINGW_PREFIX:-}" ]]; then
  # Prefer the explicit Git SDK sysroot layout when present.
  # Example: C:\git-sdk-64\mingw64 -> /c/git-sdk-64/mingw64
  case "${MSYSTEM:-}" in
  UCRT64)
    if [[ -d "/c/git-sdk-64/ucrt64" ]]; then
      MINGW_PREFIX="/c/git-sdk-64/ucrt64"
    else
      MINGW_PREFIX="/ucrt64"
    fi
    ;;
  MINGW64)
    if [[ -d "/c/git-sdk-64/mingw64" ]]; then
      MINGW_PREFIX="/c/git-sdk-64/mingw64"
    else
      MINGW_PREFIX="/mingw64"
    fi
    ;;
  CLANG64)
    if [[ -d "/c/git-sdk-64/clang64" ]]; then
      MINGW_PREFIX="/c/git-sdk-64/clang64"
    else
      MINGW_PREFIX="/clang64"
    fi
    ;;
  esac
fi

# In MSYS shells MINGW_PREFIX is often preset to /mingw64|/ucrt64|/clang64.
# Canonicalize to explicit Git SDK path when available so downstream Windows-native
# tools (including Zig package build scripts) can reliably derive Windows paths.
case "${MINGW_PREFIX}" in
/mingw64 | /ucrt64 | /clang64)
  if [[ -d "/c/git-sdk-64${MINGW_PREFIX}" ]]; then
    MINGW_PREFIX="/c/git-sdk-64${MINGW_PREFIX}"
  fi
  ;;
esac
# Must be exported: Zig's build reads MINGW_PREFIX for gtk_blueprint_compiler lib/include paths.
export MINGW_PREFIX
export PKG_CONFIG_LIBDIR="${MINGW_PREFIX}/lib/pkgconfig:${MINGW_PREFIX}/share/pkgconfig"
export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}:${PKG_CONFIG_PATH:-}"
export PATH="${MINGW_PREFIX}/bin:${PATH}"

# gtk_blueprint_compiler is a native Windows process. MSYS2's Meson-installed `blueprint-compiler`
# is a Python script (not a PE .exe), so we export GHOSTTY_BLUEPRINT_PYTHON + GHOSTTY_BLUEPRINT_SCRIPT.
# Alternatively set GHOSTTY_BLUEPRINT_COMPILER or BLUEPRINT_COMPILER to a real .exe.
ensure_ghostty_blueprint_compiler() {
  if [[ -n "${GHOSTTY_BLUEPRINT_PYTHON:-}" && -n "${GHOSTTY_BLUEPRINT_SCRIPT:-}" ]]; then
    return 0
  fi
  if [[ -n "${GHOSTTY_BLUEPRINT_COMPILER:-}" || -n "${BLUEPRINT_COMPILER:-}" ]]; then
    return 0
  fi
  if ! command -v cygpath >/dev/null 2>&1; then
    echo "error: cygpath not found. Use an MSYS2 or Git for Windows SDK MinGW shell, or export" >&2
    echo "  GHOSTTY_BLUEPRINT_PYTHON + GHOSTTY_BLUEPRINT_SCRIPT (see HACKING.md)." >&2
    return 1
  fi

  local sc="${MINGW_PREFIX}/bin/blueprint-compiler"
  local py=""
  for candidate in "${MINGW_PREFIX}/bin/python3.exe" "${MINGW_PREFIX}/bin/python.exe"; do
    if [[ -e "$candidate" ]]; then
      py="$candidate"
      break
    fi
  done
  if [[ -n "$py" && -e "$sc" ]]; then
    export GHOSTTY_BLUEPRINT_PYTHON="$(cygpath -aw "$py")"
    export GHOSTTY_BLUEPRINT_SCRIPT="$(cygpath -aw "$sc")"
    return 0
  fi

  # Rare: standalone PE launcher under MinGW bin.
  local bc=""
  for cand in \
    "${MINGW_PREFIX}/bin/blueprint-compiler.exe" \
    "${MINGW_PREFIX}/bin/blueprint-compiler.cmd" \
    "${MINGW_PREFIX}/bin/blueprint-compiler"
  do
    if [[ -e "$cand" ]]; then
      bc="$cand"
      break
    fi
  done
  if [[ -z "$bc" ]] && command -v blueprint-compiler >/dev/null 2>&1; then
    local v
    v="$(command -v blueprint-compiler)"
    case "$v" in
    "${MINGW_PREFIX}"/*) bc="$v" ;;
    esac
  fi
  if [[ -z "$bc" ]] || [[ ! -e "$bc" ]]; then
    echo "error: could not find MinGW python + ${sc} (normal MSYS2 layout)." >&2
    echo "  try: ls -la \"${MINGW_PREFIX}/bin/python\"*.exe \"${sc}\"" >&2
    echo "  try: pacman -Ql \"\${MINGW_PACKAGE_PREFIX}-blueprint-compiler\" | grep /bin/" >&2
    echo "  pacman -S --needed \"\${MINGW_PACKAGE_PREFIX}-blueprint-compiler\" \"\${MINGW_PACKAGE_PREFIX}-python\"" >&2
    return 1
  fi
  export GHOSTTY_BLUEPRINT_COMPILER="$(cygpath -aw "$bc")"
}

# Meson's blueprint-compiler script embeds a Unix sys.path; native Windows Python may not resolve it,
# so `import blueprintcompiler` can fail even when GHOSTTY_BLUEPRINT_* spawn python + script correctly.
# PYTHONPATH is the same kind of env var as GHOSTTY_* (inherited by zig → gtk_blueprint_compiler → python);
# it only extends Python's import search path, it does not locate the script or python.exe.
ensure_ghostty_blueprint_pythonpath() {
  local site=""
  if command -v python3 >/dev/null 2>&1; then
    site="$(
      python3 -c 'import importlib.util, pathlib; s = importlib.util.find_spec("blueprintcompiler"); print(pathlib.Path(s.origin).resolve().parent.parent if s and s.origin else "")' 2>/dev/null || true
    )"
  fi
  if [[ -z "$site" || ! -d "$site/blueprintcompiler" ]]; then
    local d
    for d in "${MINGW_PREFIX}/lib"/python*/site-packages; do
      [[ -d "$d/blueprintcompiler" ]] || continue
      site="$d"
      break
    done
  fi
  if [[ -n "$site" && -d "$site/blueprintcompiler" ]]; then
    export PYTHONPATH="${site}${PYTHONPATH:+:${PYTHONPATH}}"
  fi
}

if ! command -v pkg-config >/dev/null 2>&1 && ! command -v pkgconf >/dev/null 2>&1; then
  echo "error: pkg-config/pkgconf not found. Install the MinGW pkgconf package (see msys2/bootstrap-pkgs.sh)." >&2
  exit 1
fi

if ! pkg-config --exists gtk4; then
  echo "error: pkg-config cannot find gtk4. Expected e.g. ${MINGW_PREFIX}/lib/pkgconfig/gtk4.pc" >&2
  echo "  which pkg-config; pacman -S \"\${MINGW_PACKAGE_PREFIX}-gtk4\" (run msys2/bootstrap-pkgs.sh)" >&2
  exit 1
fi
if ! pkg-config --exists libadwaita-1; then
  echo "error: pkg-config cannot find libadwaita-1. Install libadwaita for your MinGW flavor (msys2/bootstrap-pkgs.sh)." >&2
  exit 1
fi

REPO_ROOT=""
if [[ -n "${1:-}" && "${1}" != -* ]]; then
  if [[ -d "$1" && -f "$1/build.zig.zon" ]]; then
    REPO_ROOT="$(cd "$1" && pwd)"
    shift
  else
    echo "error: first arg is not a Ghostty repo: $1" >&2
    exit 1
  fi
fi

if [[ -z "${REPO_ROOT}" ]]; then
  if [[ -n "${GHOSTTY_SRC:-}" ]]; then
    REPO_ROOT="$(cd "$GHOSTTY_SRC" && pwd)"
  elif [[ -f "$PWD/build.zig.zon" ]]; then
    REPO_ROOT="$PWD"
  elif [[ -f "$SCRIPT_DIR/../build.zig.zon" ]]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  else
    echo "usage: $0 [PATH_TO_GHOSTTY_REPO] [zig-build-args…]" >&2
    echo "   run from repo root: ./msys2/build-ghostty-gtk.sh [zig-build-args…]" >&2
    echo "   or: GHOSTTY_SRC=/path/to/ghostty $0 [zig-build-args…]" >&2
    exit 1
  fi
fi

zig_args=("$@")

if [[ ! -f "$REPO_ROOT/build.zig.zon" ]]; then
  echo "error: not a Ghostty repo: $REPO_ROOT" >&2
  exit 1
fi

if ! command -v zig >/dev/null 2>&1; then
  echo "error: zig not on PATH. Run ./msys2/ensure-zig.sh and export PATH as printed." >&2
  exit 1
fi

cd "$REPO_ROOT"

echo "==> zig version: $(zig version)"
echo "==> app runtime: gtk"
echo "==> MINGW_PREFIX=${MINGW_PREFIX}"
echo "==> PKG_CONFIG_LIBDIR=${PKG_CONFIG_LIBDIR}"

ensure_ghostty_blueprint_compiler || exit 1
ensure_ghostty_blueprint_pythonpath
# Native Windows Python defaults to cp1252 for open(); Ghostty .blp files are UTF-8 (emoji, …).
export PYTHONUTF8=1
if [[ -n "${GHOSTTY_BLUEPRINT_PYTHON:-}" ]]; then
  echo "==> GHOSTTY_BLUEPRINT_PYTHON=${GHOSTTY_BLUEPRINT_PYTHON}"
  echo "==> GHOSTTY_BLUEPRINT_SCRIPT=${GHOSTTY_BLUEPRINT_SCRIPT}"
else
  echo "==> GHOSTTY_BLUEPRINT_COMPILER=${GHOSTTY_BLUEPRINT_COMPILER}"
fi
if [[ -n "${PYTHONPATH:-}" ]]; then
  echo "==> PYTHONPATH=${PYTHONPATH} (for blueprintcompiler under Zig-spawned Python)"
fi
echo "==> PYTHONUTF8=1 (blueprint-compiler reads .blp as UTF-8, not cp1252)"
echo "==> building (GTK, no X11/Wayland) …"
exec zig build \
  -Dapp-runtime=gtk \
  -Dgtk-x11=false \
  -Dgtk-wayland=false \
  "${zig_args[@]}"
