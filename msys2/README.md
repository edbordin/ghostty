# Building Ghostty GTK on Windows with MSYS2

> Note: this build path is purely for development purposes and will likely
> never be an official Ghostty configuration. As such, the build scripts have
> been left as AI slop.

1. Install MSYS2 first:
   https://www.msys2.org/

2. Open the MSYS2 `UCRT64` terminal (`ucrt64.exe`) and run the bootstrap
   script from this directory:

   ```bash
   ./bootstrap-pkgs.sh
   ```

   This script may close your terminal the first time it runs. If that happens,
   restart MSYS2 and run it one more time.

3. Build Ghostty's GTK app for Windows.

   Development/debug build:

   ```bash
   ./build-ghostty-gtk.sh
   ```

   Release build:

   ```bash
   ./build-ghostty-gtk.sh -Doptimize=ReleaseFast
   ```

   The built executable is written under `zig-out/bin/` (for example
   `zig-out/bin/ghostty.exe`).
