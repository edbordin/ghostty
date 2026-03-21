#!/usr/bin/env bash
# Install MinGW packages needed for experimental Ghostty Windows builds.
# Default build-ghostty-gtk.sh uses GTK; optional GHOSTTY_APP_RUNTIME=glfw for #773 experiments.
# Typical invocation from the Ghostty repo root: ./msys2/bootstrap-pkgs.sh
# Run from MINGW64, UCRT64, or CLANG64 (not plain MSYS).

set -euo pipefail

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
# GLFW path: glfw3 + freetype (pkg-config). GTK path: gtk4 + libadwaita; Zig builds other deps from build.zig.zon.
pacman -S --needed --noconfirm \
  base-devel \
  git \
  unzip \
  "${MINGW_PACKAGE_PREFIX}-toolchain" \
  "${MINGW_PACKAGE_PREFIX}-glfw" \
  "${MINGW_PACKAGE_PREFIX}-freetype" \
  "${MINGW_PACKAGE_PREFIX}-gtk4" \
  "${MINGW_PACKAGE_PREFIX}-libadwaita" \
  "${MINGW_PACKAGE_PREFIX}-blueprint-compiler" \
  "${MINGW_PACKAGE_PREFIX}-pkgconf" \
  "${MINGW_PACKAGE_PREFIX}-glib2" \
  "${MINGW_PACKAGE_PREFIX}-libffi" \
  "${MINGW_PACKAGE_PREFIX}-libiconv"

echo "==> done."
echo "    Optional: ${MINGW_PACKAGE_PREFIX}-pandoc if you enable docs."
echo "    If zig build fails missing a system lib, try: pacman -Ss <name> and install the ${MINGW_PACKAGE_PREFIX} package."
