@echo off
rem cain on Windows: runs cain.ps1 with the PowerShell that comes with Windows.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cain.ps1" %*
