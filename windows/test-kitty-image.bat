@echo off
setlocal EnableDelayedExpansion

:: Kitty Image Protocol Test Script
:: Usage: test-kitty-image.bat [image_path]
::   If no image_path provided, outputs a small 1x1 red pixel test image

set "ESC="
set "BEL="

:: Parse arguments
set "IMAGE_FILE=%~1"

if "%IMAGE_FILE%"=="" (
    :: No image provided, use a 1x1 red PNG in base64
    :: This is a minimal valid PNG file (1x1 red pixel)
    set "PNG_BASE64=iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="

    echo [INFO] Using built-in 1x1 red test image
    echo.

    :: Output the Kitty image protocol escape sequence
    :: Format: ESC ] 1337 ; File = name=...;width=...;height=...;base64_data
    echo %ESC%]1337;File=name=test.png;width=1;height=1;inline=1:!PNG_BASE64!%ESC%\

    echo.
    echo [INFO] Sent 1x1 red pixel test image via Kitty graphics protocol
    goto :end
)

:: Check if file exists
if not exist "%IMAGE_FILE%" (
    echo [ERROR] File not found: %IMAGE_FILE%
    echo.
    echo Usage: %~nx0 [image_path]
    echo.
    echo   If no image_path provided, outputs a small 1x1 red pixel test image.
    goto :end
)

:: Get file size and extension
for %%A in ("%IMAGE_FILE%") do (
    set "FILE_SIZE=%%~zA"
    set "FILE_EXT=%%~xA"
)

:: Convert file to base64 using PowerShell
set "PS_CMD=powershell.exe -NoProfile -ExecutionPolicy Bypass -Command"
set "BASE64_DATA="

:: Try to get base64 using PowerShell
for /f "usebackq delims=" %%a in (`%PS_CMD% "[Convert]::ToBase64String([IO.File]::ReadAllBytes('%IMAGE_FILE%'))" 2^>nul`) do (
    set "BASE64_DATA=%%a"
)

if "%BASE64_DATA%"=="" (
    echo [ERROR] Failed to encode image to base64
    goto :end
)

:: Get filename
for %%F in ("%IMAGE_FILE%") do set "FILENAME=%%~nxF"

:: Output the Kitty image protocol escape sequence
:: We'll limit to 4096 chunks if needed (Kitty protocol requirement)
set "CHUNK_SIZE=4096"
set "TOTAL_LEN=0"

:: Calculate length of base64 data
set "DATA_LEN=0"
set "TEMP=%BASE64_DATA%"
:calc_len
if defined TEMP (
    set "TEMP=%TEMP:~1%"
    set /a DATA_LEN+=1
    goto :calc_len
)

echo [INFO] Sending image: %FILENAME% (%DATA_LEN% bytes base64)
echo.

:: Send in chunks if needed (Kitty protocol requires chunking for large data)
set "OFFSET=0"
set "ITER=0"

:chunk_loop
if %OFFSET% geq %DATA_LEN% goto :chunk_done

:: Calculate chunk end position
set /a "CHUNK_END=%OFFSET%+%CHUNK_SIZE"
if %CHUNK_END% gtr %DATA_LEN% set "CHUNK_END=%DATA_LEN%"

:: Extract chunk
call set "CHUNK=%%BASE64_DATA:~%OFFSET%,%CHUNK_SIZE%"

:: Output chunk
set /a "ITER+=1"
if %ITER% equ 1 (
    :: First chunk - send the header
    echo %ESC%]1337;File=name=%FILENAME%;inline=1:!CHUNK!%ESC%\
) else (
    :: Subsequent chunks - just the data
    echo %ESC%]1337;File=inline=1;size=1;!CHUNK!%ESC%\
)

set /a "OFFSET=%OFFSET%+%CHUNK_SIZE%"
goto :chunk_loop

:chunk_done
echo.

:end
endlocal
