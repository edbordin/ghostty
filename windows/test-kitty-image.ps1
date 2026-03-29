# Kitty Image Protocol Test Script
# Usage: .\test-kitty-image.ps1 [image_path]
#   If no image_path provided, outputs a small 1x1 red pixel test image

$ESC = [char]0x1B
$BEL = [char]0x07

param(
    [string]$ImagePath
)

if ([string]::IsNullOrEmpty($ImagePath)) {
    # No image provided, use a 1x1 red PNG in base64
    $PngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

    Write-Host "[INFO] Using built-in 1x1 red test image" -ForegroundColor Cyan
    Write-Host ""

    # Output the Kitty image protocol escape sequence
    Write-Host "$ESC]1337;File=name=test.png;width=1;height=1;inline=1:$PngBase64$ESC\" -NoNewline

    Write-Host ""
    Write-Host "[INFO] Sent 1x1 red pixel test image via Kitty graphics protocol" -ForegroundColor Green
    exit
}

# Check if file exists
if (-not (Test-Path $ImagePath)) {
    Write-Host "[ERROR] File not found: $ImagePath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage: .\test-kitty-image.ps1 [image_path]"
    Write-Host ""
    Write-Host "  If no image_path provided, outputs a small 1x1 red pixel test image."
    exit 1
}

# Convert image to base64
try {
    $FileBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $ImagePath))
    $Base64Data = [System.Convert]::ToBase64String($FileBytes)
    $FileName = (Split-Path $ImagePath -Leaf)

    Write-Host "[INFO] Sending image: $FileName ($($FileBytes.Length) bytes, $($Base64Data.Length) chars base64)" -ForegroundColor Cyan
    Write-Host ""

    # Calculate number of chunks needed (Kitty protocol max chunk size is 4096)
    $ChunkSize = 4096
    $Offset = 0
    $Iteration = 0
    $TotalLen = $Base64Data.Length

    while ($Offset -lt $TotalLen) {
        $ChunkEnd = [Math]::Min(($Offset + $ChunkSize), $TotalLen)
        $Chunk = $Base64Data.Substring($Offset, ($ChunkEnd - $Offset))
        $Iteration++

        if ($Iteration -eq 1) {
            # First chunk with header
            $Header = "name=$FileName"
            if ($FileName -match '\.(png|PNG)$') { $Header += ";type=image/png" }
            Write-Host "$ESC]1337;File=$Header;inline=1:$Chunk$ESC\" -NoNewline
        } else {
            # Subsequent chunks
            Write-Host "$ESC]1337;File=inline=1;size=1:$Chunk$ESC\" -NoNewline
        }

        $Offset = $ChunkEnd
    }

    Write-Host ""
    Write-Host "[INFO] Sent $Iteration chunks" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to process image: $_" -ForegroundColor Red
    exit 1
}
