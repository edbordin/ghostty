[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GhosttyRoot,

    [Parameter(Mandatory = $true)]
    [string]$ZigExe,

    [Parameter(Mandatory = $true)]
    [string]$Optimize,

    [switch]$ForceRebuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$GhosttyRoot = (Resolve-Path $GhosttyRoot).Path
$dllPath = Join-Path $GhosttyRoot "zig-out\lib\ghostty.dll"
$rawImportLibPath = Join-Path $GhosttyRoot "zig-out\lib\ghostty.lib"
$glslangDllPath = Join-Path $GhosttyRoot "zig-out\lib\glslang.dll"
$spirvCrossDllPath = Join-Path $GhosttyRoot "zig-out\lib\spirv_cross.dll"
$optimizeStampPath = Join-Path $GhosttyRoot "zig-out\lib\ghostty-optimize.txt"
$headerPath = Join-Path $GhosttyRoot "zig-out\include\ghostty.h"

function Get-LatestWriteTimeUtc {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    $latest = [datetime]::MinValue
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            continue
        }

        $item = Get-Item -LiteralPath $path
        if ($item.PSIsContainer) {
            $childLatest = Get-ChildItem -LiteralPath $path -Recurse -File |
                Sort-Object LastWriteTimeUtc -Descending |
                Select-Object -First 1
            if ($childLatest -and $childLatest.LastWriteTimeUtc -gt $latest) {
                $latest = $childLatest.LastWriteTimeUtc
            }
        }
        elseif ($item.LastWriteTimeUtc -gt $latest) {
            $latest = $item.LastWriteTimeUtc
        }
    }

    return $latest
}

$inputs = @(
    (Join-Path $GhosttyRoot "build.zig"),
    (Join-Path $GhosttyRoot "build.zig.zon"),
    (Join-Path $GhosttyRoot "src"),
    (Join-Path $GhosttyRoot "include")
)

$outputs = @($dllPath, $rawImportLibPath, $glslangDllPath, $spirvCrossDllPath, $headerPath)
$outputsReady = $true
foreach ($output in $outputs) {
    if (-not (Test-Path $output)) {
        $outputsReady = $false
        break
    }
}

$shouldBuild = $ForceRebuild -or -not $outputsReady

if (-not $shouldBuild) {
    if (-not (Test-Path $optimizeStampPath)) {
        $shouldBuild = $true
    }
    else {
        $lastOptimize = (Get-Content -LiteralPath $optimizeStampPath -Raw).Trim()
        if ($lastOptimize -ne $Optimize) {
            $shouldBuild = $true
        }
    }
}

if (-not $shouldBuild) {
    $latestInput = Get-LatestWriteTimeUtc -Paths $inputs
    $latestOutput = Get-LatestWriteTimeUtc -Paths $outputs
    if ($latestInput -gt $latestOutput) {
        $shouldBuild = $true
    }
}

if ($shouldBuild) {
    Write-Host "Building ghostty artifacts with Zig ($Optimize)..."
    & $ZigExe build "-Doptimize=$Optimize" -Demit-docs=false -Demit-exe=false -Demit-termcap=false -Demit-terminfo=false
    if ($LASTEXITCODE -ne 0) {
        throw "zig build failed with exit code $LASTEXITCODE"
    }
    Set-Content -LiteralPath $optimizeStampPath -Value $Optimize -Encoding Ascii
}
else {
    Write-Host "Ghostty artifacts are up to date; skipping zig build."
}

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $GhosttyRoot "windows\sync-ghostty-artifacts.ps1") -GhosttyRoot "$GhosttyRoot"
if ($LASTEXITCODE -ne 0) {
    throw "sync-ghostty-artifacts.ps1 failed with exit code $LASTEXITCODE"
}
