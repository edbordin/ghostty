@echo off
setlocal

pushd "%~dp0"
set "GHOSTTY_LOG=stderr"
set "GHOSTTY_ENABLE_SURFACE=1"
if not defined GHOSTTY_TRACE_HOST set "GHOSTTY_TRACE_HOST=1"
if not defined GHOSTTY_TRACE_EMBEDDED_EVENTS set "GHOSTTY_TRACE_EMBEDDED_EVENTS=1"
set "LOG_FILE=%~dp0GhosttyHostV2.log"

echo Launching GhosttyHostV2 with GHOSTTY_LOG=%GHOSTTY_LOG%
echo GHOSTTY_TRACE_HOST=%GHOSTTY_TRACE_HOST%
echo GHOSTTY_TRACE_EMBEDDED_EVENTS=%GHOSTTY_TRACE_EMBEDDED_EVENTS%
echo GHOSTTY_ENABLE_SURFACE=%GHOSTTY_ENABLE_SURFACE%
echo Log file: %LOG_FILE%
echo.

echo ==================================================>>"%LOG_FILE%"
echo Launch %DATE% %TIME%>>"%LOG_FILE%"
echo GHOSTTY_LOG=%GHOSTTY_LOG%>>"%LOG_FILE%"
echo GHOSTTY_TRACE_HOST=%GHOSTTY_TRACE_HOST%>>"%LOG_FILE%"
echo GHOSTTY_TRACE_EMBEDDED_EVENTS=%GHOSTTY_TRACE_EMBEDDED_EVENTS%>>"%LOG_FILE%"

"%~dp0GhosttyHostV2.exe" 1>>"%LOG_FILE%" 2>&1
set "exit_code=%ERRORLEVEL%"

echo.
echo GhosttyHostV2 exited with code %exit_code%.
echo.
echo Last 60 log lines:
powershell -NoProfile -Command "Get-Content -LiteralPath '%LOG_FILE%' -Tail 60"
popd
pause
exit /b %exit_code%
