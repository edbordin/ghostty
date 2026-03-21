[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$GhosttyRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ToolPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    if ($env:VCToolsInstallDir) {
        $hostX64 = Join-Path $env:VCToolsInstallDir "bin\Hostx64\x64\$Name"
        if (Test-Path $hostX64) {
            return $hostX64
        }

        $hostX86 = Join-Path $env:VCToolsInstallDir "bin\Hostx86\x64\$Name"
        if (Test-Path $hostX86) {
            return $hostX86
        }
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $installPath = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
        if ($installPath) {
            $msvcRoot = Join-Path $installPath "VC\Tools\MSVC"
            if (Test-Path $msvcRoot) {
                $toolchain = Get-ChildItem -Path $msvcRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
                if ($toolchain) {
                    $hostX64 = Join-Path $toolchain.FullName "bin\Hostx64\x64\$Name"
                    if (Test-Path $hostX64) {
                        return $hostX64
                    }

                    $hostX86 = Join-Path $toolchain.FullName "bin\Hostx86\x64\$Name"
                    if (Test-Path $hostX86) {
                        return $hostX86
                    }
                }
            }
        }
    }

    throw "Could not locate required tool: $Name"
}

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
$destDef = Join-Path $outDir "ghostty-msvc.def"
$destMsvcLib = Join-Path $outDir "ghostty-msvc.lib"

Copy-Item -Path $sourceLib -Destination $destLib -Force
Copy-Item -Path $sourceDll -Destination $destDll -Force

$dumpbinExe = Resolve-ToolPath -Name "dumpbin.exe"
$libExe = Resolve-ToolPath -Name "lib.exe"

$exports = & $dumpbinExe /exports $destDll |
    ForEach-Object {
        if ($_ -match '^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]+\s+(.+)$') {
            $Matches[1].Trim()
        }
    } |
    Where-Object {
        $_ -and
        $_ -ne "_DllMainCRTStartup" -and
        $_ -ne "DllMainCRTStartup"
    } |
    Sort-Object -Unique

if (-not $exports -or $exports.Count -eq 0) {
    throw "No exports were discovered in $destDll"
}

$defLines = @("LIBRARY ghostty.dll", "EXPORTS")
$defLines += $exports | ForEach-Object { "    $_" }
Set-Content -Path $destDef -Value $defLines -Encoding Ascii

& $libExe /nologo /machine:x64 "/def:$destDef" "/out:$destMsvcLib" | Out-Null

if (-not (Test-Path $destMsvcLib)) {
    throw "Failed to generate MSVC-safe import library: $destMsvcLib"
}

Write-Host "Synced Ghostty artifacts:"
Write-Host "  $destLib (raw)"
Write-Host "  $destDll"
Write-Host "  $destDef"
Write-Host "  $destMsvcLib"
