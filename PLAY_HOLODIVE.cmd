@echo off
setlocal EnableExtensions
REM One-click source-only HOLO DIVE from an owned Godot repo checkout.
REM It runs Godot; Studio owns any mission execution or approval.
set "ROOT=%~dp0"
set "GODOT_BIN="
if exist "C:\dev\tools\godot\4.7.2\Godot_v4.7.2-stable_win64.exe" set "GODOT_BIN=C:\dev\tools\godot\4.7.2\Godot_v4.7.2-stable_win64.exe"
if not defined GODOT_BIN for %%G in (godot.exe godot4.exe Godot_v4.7.2-stable_win64.exe) do (
    if not defined GODOT_BIN for %%P in ("%%~$PATH:G") do if exist "%%~P" set "GODOT_BIN=%%~P"
)
if not defined GODOT_BIN (
    echo Godot 4.7.2 not found. Install the project-pinned Godot 4.7 runtime or add it to PATH.
    pause
    exit /b 3
)
echo Starting HOLO DIVE from "%ROOT%"
echo Only source-backed Studio observations and explicit owner-gated missions are supported.
"%GODOT_BIN%" --audio-driver Dummy --path "%ROOT%" --scene res://scenes/ColonyWorkstation.tscn
exit /b %ERRORLEVEL%
