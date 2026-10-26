@echo off
setlocal
set "clipjump_runtime=%~dp0runtime\x64\AutoHotkey.exe"
if not exist "%clipjump_runtime%" set "clipjump_runtime=%~dp0runtime\x86\AutoHotkey.exe"
if not exist "%clipjump_runtime%" (
  echo Build the portable package first: powershell -File scripts\Build.ps1
  pause
  exit /b 1
)
start "" "%clipjump_runtime%" "%~dp0Clipjump.ahk"
