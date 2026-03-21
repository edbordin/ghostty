#!/usr/bin/env bash
# Compatibility wrapper.
# Zig bootstrap is now integrated into ./msys2/bootstrap-pkgs.sh.
#
# Usage from Ghostty repo root:
#   ./msys2/ensure-zig.sh
#   ./msys2/ensure-zig.sh PATH_TO_GHOSTTY_REPO
#
# This wrapper forwards to:
#   ./msys2/bootstrap-pkgs.sh --zig-only [--repo PATH]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${1:-}" ]]; then
  exec "$SCRIPT_DIR/bootstrap-pkgs.sh" --zig-only --repo "$1"
fi

exec "$SCRIPT_DIR/bootstrap-pkgs.sh" --zig-only
