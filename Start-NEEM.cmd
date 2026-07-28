@echo off
setlocal
title NEEM Stack Setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0neem.ps1"
if errorlevel 1 (
  echo.
  echo NEEM stopped with an error. Review the message above.
  pause
)
endlocal
