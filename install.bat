@echo off
chcp 65001 >nul
title FACEIT Extensions Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
if %ERRORLEVEL% NEQ 0 (
    echo.
    pause
)
