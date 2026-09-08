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

clean:
	-$(RM) zpaq.o libzpaq.o zpaq zpaq.exe zpaq.1 archive.zpaq zpaq.new zpaq.new.exe

check: zpaq$(EXE)
	$(RUN)zpaq$(EXE) add archive.zpaq zpaq$(EXE)
	$(RUN)zpaq$(EXE) extract archive.zpaq zpaq$(EXE) -to zpaq.new$(EXE)
	$(CMP) zpaq$(EXE) zpaq.new$(EXE)
	$(RM) archive.zpaq zpaq.new$(EXE)

.PHONY: all install clean check
