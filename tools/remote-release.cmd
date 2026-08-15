@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0remote-release.ps1" %*
exit /b %ERRORLEVEL%
