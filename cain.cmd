@echo off
rem cain on Windows: runs cain.ps1 with the PowerShell that comes with Windows.
rem PSModulePath is cleared because, when this is started from PowerShell 7, it points
rem at PowerShell 7's modules, which Windows PowerShell can't load.
setlocal
set PSModulePath=
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0cain.ps1" %*
