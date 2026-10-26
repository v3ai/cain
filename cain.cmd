@echo off
rem Windows launcher: cain.cmd
where py >nul 2>nul
if %errorlevel%==0 (py -3 "%~dp0cain.py" %*) else (python "%~dp0cain.py" %*)
