@echo off
rem Build cain.exe with Microsoft Visual C++ (run from a "Developer Command Prompt for VS").
rem With MinGW/MSYS2 instead:  gcc -O2 -std=c99 -o cain.exe src\*.c -luser32 -lgdi32 -ladvapi32 -lshell32
cl /nologo /O2 /std:c11 /W3 /D_CRT_SECURE_NO_WARNINGS /Fe:cain.exe src\*.c user32.lib gdi32.lib advapi32.lib shell32.lib
del /q *.obj 2>nul
