[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipVisualStudio,
    [switch]$SkipZig,
    [switch]$SkipCMake
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-CommandPresent {
    param([Parameter(Mandatory = $true)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found on PATH: $Name"
    }
}

function Assert-AdminIfNeeded {
    param([Parameter(Mandatory = $true)][bool]$NeedsAdmin)
    if (-not $NeedsAdmin) {
        return
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "Run this script from an elevated PowerShell session (Administrator)."
    }
}

function Invoke-WingetInstall {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    $args = @(
        "install",
        "--id", $Id,
        "--exact",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--silent"
    )

    if (Test-WingetPackageInstalled -Id $Id) {
        Write-Host "==> $DisplayName already installed"
        return
    }

    if ($PSCmdlet.ShouldProcess($DisplayName, "Install via winget")) {
        Write-Host "==> Installing $DisplayName"
        & winget @args
        if ($LASTEXITCODE -ne 0) {
            if (Test-WingetPackageInstalled -Id $Id) {
                Write-Host "==> $DisplayName is already present; continuing."
                return
            }
            throw "winget install failed for $DisplayName (id: $Id, exit: $LASTEXITCODE)"
        }
    }
}

function Test-WingetPackageInstalled {
    param([Parameter(Mandatory = $true)][string]$Id)

    $output = & winget list --id $Id --exact --accept-source-agreements 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($output)) {
        return $false
    }

    return $output -match [regex]::Escape($Id)
}

function Normalize-PathEntry {
    param([Parameter(Mandatory = $true)][string]$PathValue)

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $null
    }

    try {
        return [System.IO.Path]::GetFullPath($PathValue).TrimEnd('\')
    } catch {
        return $PathValue.Trim().TrimEnd('\')
    }
}

function Add-UserPathEntry {
    param([Parameter(Mandatory = $true)][string]$DirectoryPath)

    if ([string]::IsNullOrWhiteSpace($DirectoryPath)) {
        return $false
    }

    if (-not (Test-Path $DirectoryPath)) {
        return $false
    }

    $entry = Normalize-PathEntry -PathValue $DirectoryPath
    if ([string]::IsNullOrWhiteSpace($entry)) {
        return $false
    }
    $userPathRaw = [Environment]::GetEnvironmentVariable("Path", "User")
    $userEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($userPathRaw)) {
        $userEntries = $userPathRaw -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    $existing = @{}
    foreach ($p in $userEntries) {
        $normalized = Normalize-PathEntry -PathValue $p
        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            $existing[$normalized.ToLowerInvariant()] = $true
        }
    }

    if ($existing.ContainsKey($entry.ToLowerInvariant())) {
        return $false
    }

    $updatedEntries = @($userEntries + $entry)
    $updatedUserPath = ($updatedEntries -join ';')
    [Environment]::SetEnvironmentVariable("Path", $updatedUserPath, "User")

    $processPathRaw = [Environment]::GetEnvironmentVariable("Path", "Process")
    $processEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($processPathRaw)) {
        $processEntries = $processPathRaw -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }
    $processSet = @{}
    foreach ($p in $processEntries) {
        $normalized = Normalize-PathEntry -PathValue $p
        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            $processSet[$normalized.ToLowerInvariant()] = $true
        }
    }
    if (-not $processSet.ContainsKey($entry.ToLowerInvariant())) {
        $env:Path = (($processEntries + $entry) -join ';')
    }

    return $true
}

function Resolve-ExecutableDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$ExecutableName,
        [string]$WingetPackageId
    )

    $commandName = [System.IO.Path]::GetFileNameWithoutExtension($ExecutableName)
    $cmd = Get-Command $commandName -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source)) {
        return Split-Path -Parent $cmd.Source
    }

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        return $null
    }

    $linksDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
    $linksExe = Join-Path $linksDir $ExecutableName
    if (Test-Path $linksExe) {
        return $linksDir
    }

    if (-not [string]::IsNullOrWhiteSpace($WingetPackageId)) {
        $packagesRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
        if (Test-Path $packagesRoot) {
            $idPrefix = $WingetPackageId + "_"
            $match = Get-ChildItem $packagesRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name.StartsWith($idPrefix, [System.StringComparison]::OrdinalIgnoreCase) } |
                Select-Object -First 1
            if ($match) {
                $exe = Get-ChildItem $match.FullName -Recurse -File -Filter $ExecutableName -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($exe) {
                    return Split-Path -Parent $exe.FullName
                }
            }
        }
    }

    $commonRoots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($root in $commonRoots) {
        $candidate = Join-Path $root ("CMake\bin\" + $ExecutableName)
        if (Test-Path $candidate) {
            return Split-Path -Parent $candidate
        }
    }

    return $null
}

function Ensure-ExecutableOnUserPath {
    param(
        [Parameter(Mandatory = $true)][string]$ExecutableName,
        [string]$WingetPackageId,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    $dir = Resolve-ExecutableDirectory -ExecutableName $ExecutableName -WingetPackageId $WingetPackageId
    if (-not $dir) {
        Write-Warning "Could not resolve install directory for $DisplayName ($ExecutableName)."
        return
    }

    if ($WhatIfPreference) {
        Write-Host "==> WhatIf: would ensure $DisplayName directory on User PATH: $dir"
        return
    }

    if (Add-UserPathEntry -DirectoryPath $dir) {
        Write-Host "==> Added $DisplayName directory to User PATH: $dir"
    } else {
        Write-Host "==> $DisplayName directory already on User PATH: $dir"
    }
}

function Get-VswherePath {
    $base = ${env:ProgramFiles(x86)}
    if (-not $base) {
        throw "ProgramFiles(x86) is not set."
    }

    $path = Join-Path $base "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $path)) {
        throw "vswhere.exe not found at: $path"
    }
    return $path
}

function Get-VsSetupPath {
    $base = ${env:ProgramFiles(x86)}
    if (-not $base) {
        throw "ProgramFiles(x86) is not set."
    }

    $path = Join-Path $base "Microsoft Visual Studio\Installer\setup.exe"
    if (-not (Test-Path $path)) {
        throw "Visual Studio setup.exe not found at: $path"
    }
    return $path
}

function Get-VsInstallPath {
    param([Parameter(Mandatory = $true)][string]$VswherePath)
    $info = Get-VsInstanceInfo -VswherePath $VswherePath
    if ($null -eq $info) {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($info.installationPath)) {
        return $null
    }
    return $info.installationPath.Trim()
}

function Get-VsInstanceInfo {
    param(
        [Parameter(Mandatory = $true)][string]$VswherePath,
        [string]$InstallPath
    )

    $raw = & $VswherePath -all -products * -format json
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    $instances = $raw | ConvertFrom-Json
    if ($null -eq $instances) {
        return $null
    }

    if ($instances -isnot [System.Array]) {
        $instances = @($instances)
    }

    if ($InstallPath) {
        $match = $instances | Where-Object { $_.installationPath -eq $InstallPath } | Select-Object -First 1
        if ($match) {
            return $match
        }
    }

    return $instances | Select-Object -First 1
}

function Wait-ForVsSetupCompletion {
    param(
        [Parameter(Mandatory = $true)][string]$VswherePath,
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [int]$TimeoutSeconds = 3600
    )

    $start = Get-Date
    while ($true) {
        $elapsed = ((Get-Date) - $start).TotalSeconds
        if ($elapsed -gt $TimeoutSeconds) {
            throw "Timed out waiting for Visual Studio setup to finish."
        }

        $activeSetupProcesses = @(Get-Process -Name setup, vs_installer, winsdkinstaller, winsdksetup -ErrorAction SilentlyContinue)
        $instance = Get-VsInstanceInfo -VswherePath $VswherePath -InstallPath $InstallPath

        if ($null -eq $instance) {
            Start-Sleep -Seconds 5
            continue
        }

        $isComplete = [bool]$instance.isComplete
        $isLaunchable = [bool]$instance.isLaunchable

        if (($activeSetupProcesses.Count -eq 0) -and $isComplete -and $isLaunchable) {
            return
        }

        Start-Sleep -Seconds 5
    }
}

function Install-OrUpdateVisualStudioComponents {
    param(
        [Parameter(Mandatory = $true)][string]$VswherePath,
        [Parameter(Mandatory = $true)][string]$VsSetupPath,
        [Parameter(Mandatory = $true)][string]$VsConfigPath
    )

    $installPath = Get-VsInstallPath -VswherePath $VswherePath
    if (-not $installPath) {
        $override = "--quiet --norestart --config `"$VsConfigPath`""
        $args = @(
            "install",
            "--id", "Microsoft.VisualStudio.2022.BuildTools",
            "--exact",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--override", $override
        )

        if ($PSCmdlet.ShouldProcess("Visual Studio Build Tools 2022", "Install with ghostty-windows.vsconfig")) {
            Write-Host "==> Installing Visual Studio Build Tools 2022"
            & winget @args
            if ($LASTEXITCODE -ne 0) {
                throw "winget install failed for Visual Studio Build Tools (exit: $LASTEXITCODE)"
            }
        }

        $installPath = Get-VsInstallPath -VswherePath $VswherePath
        if (-not $installPath) {
            throw "Visual Studio Build Tools installation was not detected after install."
        }
    }

    if ($PSCmdlet.ShouldProcess($installPath, "Apply Visual Studio components from $VsConfigPath")) {
        Write-Host "==> Applying Visual Studio component baseline"
        & $VsSetupPath modify --installPath $installPath --config $VsConfigPath --quiet --norestart
        if ($LASTEXITCODE -ne 0) {
            throw "Visual Studio setup modify failed (exit: $LASTEXITCODE)"
        }
    }

    return $installPath
}

function Test-VsComponentInstalled {
    param(
        [Parameter(Mandatory = $true)][string]$VswherePath,
        [Parameter(Mandatory = $true)][string]$ComponentId
    )
    $path = & $VswherePath -latest -products * -requires $ComponentId -property installationPath
    return -not [string]::IsNullOrWhiteSpace($path)
}

Assert-CommandPresent -Name "winget"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vsConfigPath = Join-Path $scriptDir "ghostty-windows.vsconfig"
if (-not (Test-Path $vsConfigPath)) {
    throw "Missing config file: $vsConfigPath"
}

$needsAdmin = (-not $SkipVisualStudio.IsPresent) -and (-not $WhatIfPreference)
Assert-AdminIfNeeded -NeedsAdmin $needsAdmin

if (-not $SkipZig) {
    Invoke-WingetInstall -Id "zig.zig" -DisplayName "Zig 0.15.2"
    Ensure-ExecutableOnUserPath -ExecutableName "zig.exe" -WingetPackageId "zig.zig" -DisplayName "Zig"
}

if (-not $SkipCMake) {
    Invoke-WingetInstall -Id "Kitware.CMake" -DisplayName "CMake"
    Ensure-ExecutableOnUserPath -ExecutableName "cmake.exe" -WingetPackageId "Kitware.CMake" -DisplayName "CMake"
}

if (-not $SkipVisualStudio) {
    $vswherePath = Get-VswherePath
    $vsSetupPath = Get-VsSetupPath
    $installPath = Install-OrUpdateVisualStudioComponents -VswherePath $vswherePath -VsSetupPath $vsSetupPath -VsConfigPath $vsConfigPath

    if (-not $WhatIfPreference) {
        Write-Host "==> Waiting for Visual Studio installer activity to complete"
        Wait-ForVsSetupCompletion -VswherePath $vswherePath -InstallPath $installPath

        $requiredComponents = @(
            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "Microsoft.VisualStudio.Component.Windows11SDK.22621",
            "Microsoft.VisualStudio.Component.VC.CMake.Project"
        )

        $missing = @()
        foreach ($component in $requiredComponents) {
            if (-not (Test-VsComponentInstalled -VswherePath $vswherePath -ComponentId $component)) {
                $missing += $component
            }
        }

        if (-not (Test-VsComponentInstalled -VswherePath $vswherePath -ComponentId "Microsoft.Component.MSBuild")) {
            $missing += "Microsoft.Component.MSBuild"
        }

        if (-not (Test-VsComponentInstalled -VswherePath $vswherePath -ComponentId "Microsoft.VisualStudio.Component.NuGet")) {
            $missing += "Microsoft.VisualStudio.Component.NuGet"
        }

        if ($missing.Count -gt 0) {
            throw "Visual Studio components missing after bootstrap: $($missing -join ', ')"
        }
    } else {
        Write-Host "==> WhatIf mode: skipping Visual Studio component validation"
    }
}

Write-Host "==> Bootstrap complete"
Write-Host "Next: open a new terminal so PATH updates (zig/cmake) are visible."
