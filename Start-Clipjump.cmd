@echo off
setlocal
if exist "%~dp0Clipjump.exe" (
  start "" "%~dp0Clipjump.exe"
  exit /b 0
)
set "clipjump_runtime=%~dp0runtime-v2\x64\AutoHotkey.exe"
if not exist "%clipjump_runtime%" set "clipjump_runtime=%~dp0runtime-v2\x86\AutoHotkey.exe"
if not exist "%clipjump_runtime%" (
  echo Build the portable package first: powershell -File scripts\Build.ps1
  pause
  exit /b 1
)
start "" "%clipjump_runtime%" "%~dp0Clipjump.ahk"
