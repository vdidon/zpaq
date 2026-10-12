# zpaq — performance fork

A fork of [zpaq 7.15](http://mattmahoney.net/dc/zpaq.html), Matt Mahoney's
journaling archiver for incremental, deduplicated backups of directory trees.
It starts from the [zpaq/zpaq](https://github.com/zpaq/zpaq) mirror of the last
upstream release (August 2016) and is versioned 7.16.

The work is mostly about speed: SIMD and prefetching in the compressors,
parallel scanning, reading and writing in the archiver. Two options were added
(`--exclude`, `-noads`).

**Compatibility.** The archive format is unchanged: archives written by this
fork are standard ZPAQ archives that zpaq 7.15 extracts, and the other way
round. The compression methods are unchanged too. The optimized code produces
the same compressed data, so the compression ratio is the same as 7.15.

## Usage

```sh
zpaq add backup.zpaq ~/projects --exclude=".venv|node_modules|*.pyc"
zpaq list backup.zpaq
zpaq extract backup.zpaq ~/projects -to restored -until 3
```

Run `zpaq` without arguments for a summary of the commands and options.
[`zpaq.pod`](zpaq.pod) is the full manual (`pod2man zpaq.pod > zpaq.1`).

## Changes from 7.15

### Compression (libzpaq)

- Context mixing (`-m3` to `-m5`): the JIT-compiled model prefetches the table
  rows of the next bit before updating, mixes and updates the MIX weights 4 at
  a time with SSE4.1 or 8 at a time with AVX2, and runs `update()` and the next
  `predict()` in one call.
- LZ77 (`-m1`, `-m2`): SSE2 filtering of hash buckets, prefetching of buckets
  and match candidates, word compares, and a bit writer that packs whole codes.
- SHA-1 with the x86 SHA extensions, AES with AES-NI (`-key`).
- Windows: model tables of 4 MiB or more are allocated in large pages when the
  user holds the "Lock pages in memory" privilege.

All instruction set extensions are detected at run time, with a fallback to
the original code.

### Archiver (zpaq)

- `add`: input files are read and fragmented in parallel, with 256 KB reads;
  the index blocks are compressed in the background.
- `extract`: output files are written in parallel and kept open across blocks.
- Windows scan: directories are read in parallel; alternate data streams are
  enumerated in parallel, and files unchanged since the last version keep
  their archived streams without being opened.
- `--exclude=P|P...` skips names at any depth, unlike `-not`, which is
  anchored at the start of the path. Excluded directories are not scanned.
- `-noads` (Windows) skips alternate data streams.
- Read errors on the archive are reported instead of being taken for its end.
- The Makefile builds on Windows with MinGW-w64, and `make check` round-trips
  data with long and far LZ77 matches.

## Performance

zpaq 7.15 against this fork, both built from source with the same compiler and
options (GCC 14.2, `-O3 -march=native`, static). The data is a MinGW-w64
toolchain: 625 MB in 3515 files, C headers and executables. Each `add` creates
a new archive with 16 threads, and each `extract` restores the whole tree.

| Method | Operation | 7.15    | Fork    | Speed-up |
|--------|-----------|--------:|--------:|---------:|
| `-m1`  | add       |   4.5 s |   1.6 s |    ×2.92 |
|        | extract   |   5.6 s |   1.1 s |    ×4.90 |
| `-m2`  | add       |  22.9 s |  16.8 s |    ×1.36 |
|        | extract   |   5.0 s |   1.3 s |    ×3.75 |
| `-m3`  | add       |  22.1 s |  18.8 s |    ×1.18 |
|        | extract   |  12.0 s |  11.4 s |    ×1.05 |
| `-m4`  | add       |  53.2 s |  42.6 s |    ×1.25 |
|        | extract   |  51.0 s |  44.9 s |    ×1.14 |
| `-m5`  | add       | 174.6 s | 110.9 s |    ×1.57 |
|        | extract   | 174.3 s | 115.2 s |    ×1.51 |

Both versions write archives of the same size for every method, each one
extracts the archives of the other, and the extracted trees are identical to
the originals. Adding the same tree again, unchanged, takes 0.06 s instead of
0.17 s.

Measured on a Ryzen 7 7840HS (8 cores, 16 threads) under Windows 11, warm cache,
the two versions taking turns. The times are the best of two rounds; from one
round to the other they varied by up to 20 %, so the small gains of `-m3` and
`-m4` are within the noise of a single run.

## Building

### Linux

```sh
make
make check
sudo make install
```

### Windows (MinGW-w64)

With GCC from [WinLibs](https://winlibs.com/) or MSYS2 and GNU make:

```sh
make
make check
```

The executable is linked statically and needs no DLL.

Visual Studio also works (`cl /O2 /EHsc zpaq.cpp libzpaq.cpp advapi32.lib`),
but its build is about 30 % slower than GCC or Clang on `-m1`.

### Options

- The Makefile compiles with `-march=native`, so the executable may not run on
  an older CPU. For a binary to distribute, build with `make CXXFLAGS=-O3`.
- For non-x86 processors, turn the JIT off: `make CPPFLAGS="-Dunix -DNOJIT"`
  (keep `-Dunix` on Unix: a `CPPFLAGS` given to make replaces the Makefile's).
- `-DNOSHANI` and `-DNOAESNI` leave out the SHA and AES-NI code.

[`readme.txt`](readme.txt) is the upstream readme and lists the other compiler
options.

### Tested platforms

Developed and benchmarked on Windows 11 x64. Linux x86-64 builds and passes
`make check` (Ubuntu 24.04, GCC 13), and so does Linux ARM64 with `-DNOJIT`
(Raspberry Pi 5, Debian 13, GCC 14). On ARM most of the speed-ups are absent:
the JIT, SIMD, SHA and AES-NI code is x86 only, and the fork is at most 25 %
faster than 7.15 there. macOS, BSD and 32-bit builds have not been tested.

## License

Public domain ([Unlicense](COPYING)), like upstream, except the code from
libdivsufsort embedded in `libzpaq.cpp` (© 2003–2008 Yuta Mori, MIT license).

zpaq was written by Matt Mahoney. Please report problems with this fork in its
GitHub issues, not to the upstream author.
