[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Debug", "ReleaseFast")]
    [string]$Optimize = "Debug",

    [string]$ZigExe = "zig"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$windowsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ghosttyRoot = (Resolve-Path (Join-Path $windowsDir "..")).Path

if ($ZigExe -eq "zig") {
    $wingetZig = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\zig.exe"
    if (Test-Path $wingetZig) {
        $ZigExe = $wingetZig
    }
}

Write-Host "==> Rebuilding ghostty library artifacts (optimize=$Optimize)"
Push-Location $ghosttyRoot
try {
    & $ZigExe build "-Doptimize=$Optimize" -Demit-docs=false -Demit-exe=false -Demit-termcap=false -Demit-terminfo=false
    if ($LASTEXITCODE -ne 0) {
        throw "zig build failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Write-Host "==> Syncing host artifacts"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $windowsDir "sync-ghostty-artifacts.ps1") -GhosttyRoot "$ghosttyRoot"
if ($LASTEXITCODE -ne 0) {
    throw "sync-ghostty-artifacts.ps1 failed with exit code $LASTEXITCODE"
}

Write-Host "==> ghostty library rebuild complete"
