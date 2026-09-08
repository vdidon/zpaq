# Builds zpaq with GNU make on Linux, BSD, Mac OS/X or Windows (MinGW-w64).
# On Windows the code uses the Win32 API and threads instead of the POSIX
# ones, so -Dunix and -pthread are left out and the binary is linked
# statically so that it runs without the compiler's DLLs.

CXX=g++
# CPPFLAGS+=-DNOJIT
CXXFLAGS=-O3 -march=native -mtune=native
PREFIX=/usr/local
BINDIR=$(PREFIX)/bin
MANDIR=$(PREFIX)/share/man

ifeq ($(OS),Windows_NT)
SHELL=cmd.exe
EXE=.exe
LDLIBS=
LDFLAGS+=-static
ALL=zpaq$(EXE)
RM=del /q /f
CMP=fc /b >nul
# ./ so that check runs the binary just built, not one in PATH: with an
# empty prefix, make launches the program found in PATH first.
RUN=./
else
CPPFLAGS+=-Dunix
EXE=
LDLIBS=-pthread
ALL=zpaq zpaq.1
RUN=./
RM=rm -f
CMP=cmp
endif

all: $(ALL)

libzpaq.o: libzpaq.cpp libzpaq.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -o $@ -c libzpaq.cpp

zpaq.o: zpaq.cpp libzpaq.h
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -o $@ -c zpaq.cpp $(LDLIBS)

zpaq$(EXE): zpaq.o libzpaq.o
	$(CXX) $(LDFLAGS) -o $@ zpaq.o libzpaq.o $(LDLIBS)

zpaq.1: zpaq.pod
	pod2man $< >$@

install: zpaq zpaq.1
	install -m 0755 -d $(DESTDIR)$(BINDIR)
	install -m 0755 zpaq $(DESTDIR)$(BINDIR)
	install -m 0755 -d $(DESTDIR)$(MANDIR)/man1
	install -m 0644 zpaq.1 $(DESTDIR)$(MANDIR)/man1

lztest$(EXE): lztest.cpp
	$(CXX) $(CXXFLAGS) -o $@ lztest.cpp

clean:
	-$(RM) zpaq.o libzpaq.o zpaq zpaq.exe zpaq.1 archive.zpaq zpaq.new zpaq.new.exe lztest lztest.exe lztest.bin lztest.zpaq lztest.new

# Round trip of the program itself, then of data with long and far
# matches through two configurations of the level 1 LZ77 encoder: the
# one of -m4 on barely compressible data (64 MB blocks) and the one of
# -m1 on redundant data (16 MB blocks). Its bit packing once broke only
# on such matches, once in eight, and only a few blocks of an archive.
check: zpaq$(EXE) lztest$(EXE)
	$(RUN)zpaq$(EXE) add archive.zpaq zpaq$(EXE)
	$(RUN)zpaq$(EXE) extract archive.zpaq zpaq$(EXE) -to zpaq.new$(EXE)
	$(CMP) zpaq$(EXE) zpaq.new$(EXE)
	$(RM) archive.zpaq zpaq.new$(EXE)
	$(RUN)lztest$(EXE) lztest.bin
	$(RUN)zpaq$(EXE) add lztest.zpaq lztest.bin -method x6,1,4,0,3,25 -threads 1
	$(RUN)zpaq$(EXE) extract lztest.zpaq lztest.bin -to lztest.new
	$(CMP) lztest.bin lztest.new
	$(RM) lztest.zpaq lztest.new
	$(RUN)zpaq$(EXE) add lztest.zpaq lztest.bin -method x4,1,5,0,3,24 -threads 1
	$(RUN)zpaq$(EXE) extract lztest.zpaq lztest.bin -to lztest.new
	$(CMP) lztest.bin lztest.new
	$(RM) lztest.zpaq lztest.new lztest.bin

.PHONY: all install clean check
