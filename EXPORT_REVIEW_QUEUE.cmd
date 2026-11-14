@echo off
setlocal EnableExtensions
REM Explicit, read-only GitHub scan for GSV's operator review instrument.
REM No GitHub mutation. No agent scheduling. No merge.
if not defined LOCALAPPDATA (
    echo LOCALAPPDATA is unavailable. Set a safe explicit export path instead.
    exit /b 3
)
where gh >nul 2>&1
if errorlevel 1 (
    echo GitHub CLI missing. Install and authenticate gh first.
    exit /b 4
)
set "EXPORT=%LOCALAPPDATA%\GSV_Cockpit\review_queue.json"
echo Collecting bounded, read-only GitHub facts to "%EXPORT%"...
py -3 "%~dp0tools\workstation\collect_review_queue.py" --output "%EXPORT%" --limit 32 --details 16 %*
if errorlevel 1 (
    echo Export unavailable. Existing queue remains stale and non-authoritative.
    exit /b 2
)
echo DONE. Open HOLO DIVE / REVIEW OPS / RELOAD LOCAL SOURCE.
exit /b 0
