@echo off
:: incognis.bat - launcher
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0incognis.ps1" %*
exit /b %ERRORLEVEL%
