@echo off
echo ========================================
echo   Stock Monitor - Quick Start
echo ========================================
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0start.ps1"
if %ERRORLEVEL% neq 0 (
    echo.
    echo [ERROR] Startup failed. Check the error messages above.
    pause
)
