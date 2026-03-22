# Ghostty Windows Bootstrap

This folder is the Windows bring-up home for the Ghostty experimental branch.

## What this sets up

- Visual Studio Build Tools/VS components from `ghostty-windows.vsconfig`
- Windows SDK `10.0.22621.x` via VS component
- Zig (via `winget`, package id `zig.zig`)
- CMake (via `winget`, package id `Kitware.CMake`)

## Run bootstrap

Open an elevated PowerShell (Run as Administrator), then run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\windows\bootstrap.ps1
```

Optional flags:

```powershell
.\windows\bootstrap.ps1 -SkipCMake
.\windows\bootstrap.ps1 -SkipVisualStudio
.\windows\bootstrap.ps1 -SkipZig
.\windows\bootstrap.ps1 -WhatIf
```

## Build system guidance

For the Windows Terminal-derived fork path, prefer MSBuild/Visual Studio projects as the primary build system.

Use CMake for smaller standalone probes or helper programs that consume `libghostty-vt`, but do not make it the main integration path for the WT-style host shell.

## GhosttyIsland solution

`GhosttyIsland.sln` currently has two host projects:

- `GhosttyHost` (`.exe`): original minimal Win32 + XAML Island host kept as an archived reference baseline.
- `GhosttyHostV2` (`.exe`): active iteration host with Terminal-style structure for island hosting, input-routing hooks, and swapchain-panel ownership.

Default solution build now targets `GhosttyHostV2`. `GhosttyHost` remains in the solution but is not in default Build.0 entries.

Canonical build output for both hosts is `windows\bin\<Configuration>\x64\` (from `OutDir` in each `.vcxproj`).
Treat project-local folders such as `windows\GhosttyHostV2\bin\...` as non-canonical/manual run locations that may become stale.

Build both configurations from the repo root:

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
  .\windows\GhosttyIsland.sln /m /t:Rebuild /p:Configuration=Debug /p:Platform=x64

& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" `
  .\windows\GhosttyIsland.sln /m /t:Rebuild /p:Configuration=Release /p:Platform=x64
```

Use manual artifact rebuild (macOS-style explicit step) before building hosts:

```powershell
.\windows\rebuild-ghostty-lib.ps1 -Optimize Debug
.\windows\rebuild-ghostty-lib.ps1 -Optimize ReleaseFast
```

This runs Zig and then refreshes the MSVC-safe import library (`zig-out\lib\ghostty-msvc.lib`) from DLL exports. It avoids linking against the raw Zig import library symbol `_DllMainCRTStartup`, which conflicts with MSVC DLL CRT startup.

Current `GhosttyHost` scope is intentionally minimal: window creation, `WindowsXamlManager`, `DesktopWindowXamlSource`, and simple content creation.

`GhosttyHostV2` adds structure for:
- direct/special key handling from the Win32 message loop,
- Win32 wheel fallback dispatch into the terminal surface,
- WinUI input handlers on a dedicated terminal surface object,
- embedded `ghostty_app_t` runtime lifecycle wiring (config/app init, callbacks, wakeup->`ghostty_app_tick` dispatch on the Win32 thread),
- embedded `ghostty_surface_t` lifecycle wiring on Windows (`GHOSTTY_PLATFORM_WINDOWS` + host `HWND`),
- `SwapChainPanel` ownership and a swapchain attach method (`ISwapChainPanelNative2`) ready for renderer wiring.

Both hosts embed custom app manifests (`GhosttyHost.manifest` and `GhosttyHostV2.manifest`) with `maxversiontested` and `supportedOS`, required for XAML Islands activation in unpackaged Win32 mode.

## Runtime ownership (important)

- `GhosttyHost.exe` and `GhosttyHostV2.exe` are Win32 + XAML Island shells.
- `ghostty.dll` (built by Zig) runs in-process and is expected to own terminal core behavior.
- `GhosttyHostV2` initializes `ghostty_app_t`, creates `ghostty_surface_t` with `GHOSTTY_PLATFORM_WINDOWS`, and pumps runtime ticks on the Win32 thread.
- Current renderer state for Windows is a Zig D3D11 scaffold backend (presentation wiring only), so surface lifecycle and input routing run, but there is no visible terminal frame output yet.
- For Windows PTY/process flow, Ghostty uses ConPTY APIs internally (`CreatePseudoConsole` and process startup attributes). The host does not currently call `AttachConsole`/`AllocConsole` and does not own PTY lifecycle yet.

## Runtime toggles (GhosttyHostV2)

- `GHOSTTY_ENABLE_SURFACE` is enabled by default; set it to `0`, `false`, or `no` to disable `ghostty_surface_t` creation and run app-only mode (`ghostty_app_t` without surface/PTY path).
- `GHOSTTY_LOAD_DEFAULT_CONFIG=1` enables `ghostty_config_load_default_files`. If unset, runtime skips default config file loading.
- `GHOSTTY_TRACE_HOST=0` disables host-side `[host] ...` tracing. Default is enabled.
- `GHOSTTY_TRACE_EMBEDDED_EVENTS=0` disables embedded event tracing from `ghostty.dll`. Default is enabled.
- `RunGhosttyHostV2.bat` sets `GHOSTTY_LOG=stderr`, writes output to `GhosttyHostV2.log`, and prints the log tail on exit.
  If launched from `windows\GhosttyHostV2\`, it now redirects to the canonical `windows\bin\Debug\x64\` output when available.
