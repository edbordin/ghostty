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

> **Note**: Only build Debug unless explicitly asked. ReleaseFast builds take significantly longer and are rarely needed during development iteration.

This runs Zig and then syncs the raw Zig artifacts (`zig-out\lib\ghostty.lib` and `zig-out\lib\ghostty.dll`) into the Windows host output directories.

Artifact script roles (keep both while iterating):

- `windows\ensure-ghostty-artifacts.ps1`: pre-build guard/orchestrator. It checks whether Zig outputs are stale for the requested optimize mode, runs Zig build only when needed, then calls sync.
- `windows\sync-ghostty-artifacts.ps1`: copy-only sync step. It copies `ghostty.lib/.dll` (and runtime deps like `glslang.dll`, `spirv_cross.dll`) from `.zig-cache` into `zig-out\lib`, and mirrors them into host output directories to avoid stale runtime DLLs.
- `windows\rebuild-ghostty-lib.ps1`: explicit "always rebuild then sync" path for manual refreshes.

MSBuild integration:

- `GhosttyHost`/`GhosttyHostV2` run `ensure-ghostty-artifacts.ps1` as a pre-build step.
- Host post-build events then copy from `zig-out\lib` into canonical `windows\bin\<Configuration>\x64\`.

## Quick iteration from WSL2

**For day-to-day development, prefer calling the checked-in PowerShell scripts over direct `zig.exe` invocation.** The scripts handle DLL syncing, artifact copying, and build orchestration automatically.

For rapid renderer/DLL development iteration, you don't need a full MSBuild rebuild:

```bash
# 1. Rebuild just the ghostty library (zig build + DLL sync)
#    The script handles zig build invocation and artifact syncing.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
  "$(wslpath -w /mnt/c/Users/Ed/Documents/pdev/ghostty-win/ghostty/windows/rebuild-ghostty-lib.ps1)" \
  -Optimize Debug

# 2. Close the running GhosttyHostV2.exe process if open
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Stop-Process -Name GhosttyHostV2 -ErrorAction SilentlyContinue"

# 3. Relaunch the app
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath 'C:\Users\Ed\Documents\pdev\ghostty-win\ghostty\windows\bin\Debug\x64\GhosttyHostV2.exe'"
```

**Only use direct `zig.exe` invocation** when you need custom build options not exposed by the scripts (e.g., specific test targets, verbose output, etc.). Example:
```bash
# Only when you need custom zig commands
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "C:\Users\Ed\.local\zig\0.15.2\zig.exe build -Doptimize=Debug --summary all"
```

The DLLs are hot-loaded by the exe, so after step 1 completes you only need to restart the exe process to pick up changes.

**Development builds are Debug only.** Release builds take significantly longer and are rarely needed during iteration. The canonical build output is `windows\bin\Debug\x64\`.

## Debugging

Log file location: `windows\bin\Debug\x64\GhosttyHostV2.log`

The batch file `RunGhosttyHostV2.bat` sets `GHOSTTY_LOG=stderr` and captures output to the log file, then tails it on exit. For direct log viewing from WSL2:
```bash
tail -f "$(wslpath -u 'C:\Users\Ed\Documents\pdev\ghostty-win\ghostty\windows\bin\Debug\x64\GhosttyHostV2.log')"
```

## WSL2 PowerShell notes

**Prefer checked-in scripts for common tasks.** Use direct PowerShell commands only when scripts don't cover your use case.

Useful invocation patterns from a WSL2 bash shell:

```bash
# Rebuild ghostty library (most common during renderer iteration)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
  "$(wslpath -w /mnt/c/Users/Ed/Documents/pdev/ghostty-win/ghostty/windows/rebuild-ghostty-lib.ps1)" \
  -Optimize Debug
```

```bash
# For complex commands/args, write a temp .ps1 file first (most reliable)
cat > /tmp/run_host_build.ps1 <<'PS1'
$ErrorActionPreference='Stop'
$msbuild='C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe'
Set-Location 'C:\Users\Ed\Documents\pdev\ghostty-win\ghostty\windows'
& $msbuild '.\GhosttyIsland.sln' '/m' '/t:GhosttyHostV2' '/p:Configuration=Debug' '/p:Platform=x64'
PS1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w /tmp/run_host_build.ps1)"
```

Notes:
- Prefer `-File` over `-Command` from bash to avoid quote/variable mangling.
- Use `wslpath -w` to convert Linux paths to Windows paths before passing to PowerShell.
- The scripts auto-detect zig via winget path or system PATH. Only use `-ZigExe` override if you have a custom zig installation.
- Common zig paths (for reference, when overriding via `-ZigExe`):
  - `C:\Users\Ed\.local\zig\0.15.2\zig.exe` (manual install)
  - `C:\Users\Ed\AppData\Local\Microsoft\WinGet\Links\zig.exe` (winget link)
  - Find via: `find /mnt/c/Users/Ed -name "zig.exe" 2>/dev/null | head -5`
- MSBuild (for full host rebuilds): `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe`

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
- Current renderer state for Windows is a Zig D3D11 backend with core terminal passes wired (`bg_color`, `bg_image`, `cell_bg`, `cell_text`, `image`) and visible frame output. Custom postprocess shaders now load via GLSL -> SPIR-V -> HLSL translation.
- For Windows PTY/process flow, Ghostty uses ConPTY APIs internally (`CreatePseudoConsole` and process startup attributes). The host does not currently call `AttachConsole`/`AllocConsole` and does not own PTY lifecycle yet.

## Shader architecture notes (Windows bring-up)

- `src/renderer/d3d11/**` is Windows-only backend code. It is only compiled when `build_config.renderer == .d3d11` (the Windows renderer selection), so non-Windows placeholder structs/branches are not required in those files.
- D3D11 backend bindings are sourced directly from `pkg/zwindows` with local per-file aliases (`const d3d = zw.d3d11; const dxgi = zw.dxgi;`). Avoid reintroducing a broad central passthrough shim.
- D3D11 refactor goal (Metal parity model):

| File | Ghostty abstraction | D3D 11 construct it maps to |
|---|---|---|
| `buffer.zig` | Generic GPU buffer wrapper | `ID3D11Buffer` (`CreateBuffer`, `Map/Unmap` or `UpdateSubresource`) |
| `Texture.zig` | Texture object + region updates | `ID3D11Texture2D` + `D3D11_TEXTURE2D_DESC`, updates via `UpdateSubresource` |
| `Sampler.zig` | Sampler wrapper | `ID3D11SamplerState` + `D3D11_SAMPLER_DESC` |
| `Pipeline.zig` | Render pipeline creation | VS/PS blobs + `ID3D11VertexShader`, `ID3D11PixelShader`, `ID3D11InputLayout`, blend/depth/rasterizer state objects |
| `RenderPass.zig` | Pass encoder + draw steps | Immediate/deferred context pass setup (`OMSetRenderTargets`, `RSSetViewports`, resource binds, `Draw*`) |
| `Frame.zig` | Per-frame submission lifecycle | Command submission on `ID3D11DeviceContext` + present via `IDXGISwapChain::Present` |
| `Target.zig` | Render target abstraction | `ID3D11Texture2D` render target + `ID3D11RenderTargetView` (plus `ID3D11ShaderResourceView` when sampled later) |

**D3D11 vs Metal architecture note**: D3D11 uses an immediate context model (commands execute immediately on the device context) whereas Metal uses deferred command buffers. The D3D11 `RenderPass.complete()` is intentionally empty because all state binding and draw calls happen during `step()`, and `present()` (called in `Frame.complete()`) is what triggers GPU execution. The driver manages the command queue implicitly. This is simpler than Metal's explicit encoder lifecycle but requires careful tracking of render target binding state (`swapchain_pass_bound` flag) to avoid clearing the swapchain when offscreen rendering is in progress. |
| `SwapChainPanel.zig` | Presentation bridge to view/layer | DXGI composition swapchain bridge (`IDXGISwapChain1/2` + `SwapChainPanel` binding) |
| `shaders.zig` | Shader/pipeline registry + shader ABI structs | HLSL shader blobs and cached D3D11 pipeline state bundles |
| `api.zig` | Typed bindings/constants used by wrappers | D3D11/DXGI enums and descriptors (`DXGI_FORMAT`, `D3D11_*_DESC`) plus device/swapchain creation APIs |
- Render-pass state binding policy: follow Metal/OpenGL style and bind required resources per step; do not add backend-local SRV/sampler binding caches unless profiling shows a clear, measured need.
- Metal reference mapping (same abstraction model):

| File | Ghostty abstraction | Metal construct it maps to |
|---|---|---|
| `buffer.zig` | Generic GPU buffer wrapper | `MTLBuffer` (`newBufferWithLength`, `newBufferWithBytes`, `contents`, `didModifyRange`) |
| `Texture.zig` | Texture object + region updates | `MTLTextureDescriptor`, `MTLTexture`, `replaceRegion` |
| `Sampler.zig` | Sampler wrapper | `MTLSamplerDescriptor`, `MTLSamplerState` |
| `Pipeline.zig` | Render pipeline creation | `MTLRenderPipelineDescriptor`, `MTLRenderPipelineState`, `MTLVertexDescriptor` |
| `RenderPass.zig` | Pass encoder + draw steps | `MTLRenderPassDescriptor`, `MTLRenderCommandEncoder`, `drawPrimitives` |
| `Frame.zig` | Per-frame submission lifecycle | `MTLCommandBuffer` (`commit`, `waitUntilCompleted`, `addCompletedHandler`) |
| `Target.zig` | Render target abstraction | IOSurface-backed `MTLTexture` (`newTextureWithDescriptor:iosurface:plane:`) |
| `IOSurfaceLayer.zig` | Presentation bridge to view/layer | `CALayer` + IOSurface `contents` bridge |
| `shaders.zig` | Shader/pipeline registry + shader ABI structs | `MTLLibrary` + cached `MTLRenderPipelineState` set |
| `api.zig` | Typed bindings/constants used by wrappers | Metal enums/structs and entry points (`MTLCreateSystemDefaultDevice`, etc.) |
- GLSL shaders in `src/renderer/shaders/glsl/` are not just effects in Ghostty overall. For the OpenGL backend, they are core rendering shaders (bg, cell bg, text, image, bg image).
- Metal backend core rendering uses `src/renderer/shaders/shaders.metal`; custom postprocess shaders are loaded from user GLSL and translated through SPIR-V tooling for Metal.
- Current D3D11 bring-up does not yet translate those core GLSL shaders directly. Core D3D11 paths are being implemented with explicit HLSL modules in `src/renderer/shaders/hlsl/`.
- Current D3D11 custom shader loading translates ShaderToy GLSL through SPIR-V into HLSL and compiles each translated shader as a postprocess pixel stage.

## Runtime toggles (GhosttyHostV2)

- `GHOSTTY_ENABLE_SURFACE` is enabled by default; set it to `0`, `false`, or `no` to disable `ghostty_surface_t` creation and run app-only mode (`ghostty_app_t` without surface/PTY path).
- `GHOSTTY_LOAD_DEFAULT_CONFIG=1` enables `ghostty_config_load_default_files`. If unset, runtime skips default config file loading.
- `GHOSTTY_TRACE_HOST=0` disables host-side `[host] ...` tracing. Default is enabled.
- `GHOSTTY_TRACE_EMBEDDED_EVENTS=0` disables embedded event tracing from `ghostty.dll`. Default is enabled.
- `RunGhosttyHostV2.bat` sets `GHOSTTY_LOG=stderr`, writes output to `GhosttyHostV2.log`, and prints the log tail on exit.
  If launched from `windows\GhosttyHostV2\`, it now redirects to the canonical `windows\bin\Debug\x64\` output when available.
