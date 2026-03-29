[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GhosttyRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$GhosttyRoot = (Resolve-Path $GhosttyRoot).Path

$cacheDir = Join-Path $GhosttyRoot ".zig-cache"
$outDir = Join-Path $GhosttyRoot "zig-out\\lib"

if (-not (Test-Path $cacheDir)) {
    throw "Missing Zig cache directory: $cacheDir"
}

if (-not (Test-Path $outDir)) {
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
}

$candidate = Get-ChildItem -Path $cacheDir -Recurse -File -Filter "ghostty.lib" |
    Sort-Object LastWriteTime -Descending |
    Where-Object { Test-Path (Join-Path $_.DirectoryName "ghostty.dll") } |
    Select-Object -First 1

if (-not $candidate) {
    throw "Could not find matching ghostty.lib + ghostty.dll in $cacheDir"
}

$sourceLib = $candidate.FullName
$sourceDll = Join-Path $candidate.DirectoryName "ghostty.dll"

$destLib = Join-Path $outDir "ghostty.lib"
$destDll = Join-Path $outDir "ghostty.dll"
$destGlslangDll = Join-Path $outDir "glslang.dll"
$destSpirvCrossDll = Join-Path $outDir "spirv_cross.dll"

$glslangCandidate = Get-ChildItem -Path $cacheDir -Recurse -File -Filter "glslang.dll" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
$spirvCrossCandidate = Get-ChildItem -Path $cacheDir -Recurse -File -Filter "spirv_cross.dll" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

Copy-Item -Path $sourceLib -Destination $destLib -Force
Copy-Item -Path $sourceDll -Destination $destDll -Force
if ($glslangCandidate) {
    Copy-Item -Path $glslangCandidate.FullName -Destination $destGlslangDll -Force
} else {
    Write-Warning "No glslang.dll found in $cacheDir; dynamic glslang runtime copy skipped."
}
if ($spirvCrossCandidate) {
    Copy-Item -Path $spirvCrossCandidate.FullName -Destination $destSpirvCrossDll -Force
} else {
    Write-Warning "No spirv_cross.dll found in $cacheDir; dynamic spirv-cross runtime copy skipped."
}

# Keep host output trees in sync when they already exist so running the host
# does not accidentally pick up a stale ghostty.dll.
$runtimeOutputDirs = @(
    (Join-Path $GhosttyRoot "windows\bin\Debug\x64"),
    (Join-Path $GhosttyRoot "windows\bin\Release\x64"),
    (Join-Path $GhosttyRoot "windows\GhosttyHost\bin\Debug\x64"),
    (Join-Path $GhosttyRoot "windows\GhosttyHost\bin\Release\x64"),
    (Join-Path $GhosttyRoot "windows\GhosttyHostV2\bin\Debug\x64"),
    (Join-Path $GhosttyRoot "windows\GhosttyHostV2\bin\Release\x64")
)

foreach ($dir in $runtimeOutputDirs) {
    if (-not (Test-Path $dir)) {
        continue
    }

    Copy-Item -Path $destDll -Destination (Join-Path $dir "ghostty.dll") -Force
    Copy-Item -Path $destLib -Destination (Join-Path $dir "ghostty.lib") -Force
    if (Test-Path $destGlslangDll) {
        Copy-Item -Path $destGlslangDll -Destination (Join-Path $dir "glslang.dll") -Force
    }
    if (Test-Path $destSpirvCrossDll) {
        Copy-Item -Path $destSpirvCrossDll -Destination (Join-Path $dir "spirv_cross.dll") -Force
    }
}

Write-Host "Synced Ghostty artifacts:"
Write-Host "  $destLib"
Write-Host "  $destDll"
if (Test-Path $destGlslangDll) {
    Write-Host "  $destGlslangDll"
}
if (Test-Path $destSpirvCrossDll) {
    Write-Host "  $destSpirvCrossDll"
}
