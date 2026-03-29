# Ghostty Windows Development

This is a Windows bring-up fork of Ghostty. For development build instructions, workflow, and architecture notes, see **[windows/README.md](windows/README.md)**.

## Quick Links

- **Build instructions**: [windows/README.md](windows/README.md)
- **Quick iteration**: `windows/rebuild-ghostty-lib.ps1`
- **Log location**: `windows/bin/Debug/x64/GhosttyHostV2.log`
- **Main executable**: `windows/bin/Debug/x64/GhosttyHostV2.exe`

## Key Differences from Upstream

This fork uses D3D11 rendering on Windows instead of Metal (macOS) or OpenGL (Linux). The renderer backend is in `src/renderer/d3d11/`.

For Windows-specific development workflow, see the [Windows README](windows/README.md).
