@echo off
setlocal
title NEEM Stack Setup - Command Prompt

if /i "%~1"=="-Help" goto run_neem
if /i "%~1"=="-DryRun" goto run_neem
if /i "%~1"=="-Health" goto run_neem

fltmc >nul 2>&1
if errorlevel 1 (
  echo Requesting administrator access for NEEM...
  set "NEEM_LAUNCHER=%~f0"
  set "NEEM_ARGUMENTS=%*"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$q=[char]34; Start-Process -FilePath $env:ComSpec -Verb RunAs -ArgumentList @('/d','/k',($q+$q+$env:NEEM_LAUNCHER+$q+' '+$env:NEEM_ARGUMENTS+$q))"
  exit /b
)

:run_neem
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0neem.ps1" -NoElevate %*
if errorlevel 1 (
  echo.
  echo NEEM stopped with an error. Review the message above.
  pause
)
endlocal
