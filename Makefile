# Linux / macOS:      make            -> ./cain
# Windows (MinGW):    make windows    -> ./cain.exe   (cross-compile from Linux, or MSYS2)
# Windows (MSVC):     build.bat
CC      ?= cc
CFLAGS  ?= -O2 -Wall -Wextra -std=c99 -D_DEFAULT_SOURCE -D_DARWIN_C_SOURCE
LDLIBS  ?= -lm
SRC     := $(wildcard src/*.c)
MINGW   ?= x86_64-w64-mingw32-gcc

cain: $(SRC) src/cain.h
	$(CC) $(CFLAGS) -o $@ $(SRC) $(LDLIBS)

windows: cain.exe
cain.exe: $(SRC) src/cain.h
	$(MINGW) -O2 -Wall -Wextra -std=c99 -static -o $@ $(SRC) -luser32 -lgdi32 -ladvapi32 -lshell32

test: cain
	sh tests/run.sh

clean:
	rm -f cain cain.exe

.PHONY: windows test clean
