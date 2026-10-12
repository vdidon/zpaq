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

- x86
  - Context mixing (`-m3` to `-m5`): the JIT-compiled model prefetches the
    table rows of the next bit before updating, mixes and updates the MIX
    weights 4 at a time with SSE4.1 or 8 at a time with AVX2, and runs
    `update()` and the next `predict()` in one call.
  - LZ77 (`-m1`, `-m2`): SSE2 filtering of hash buckets, prefetching of
    buckets and match candidates, word compares, and a bit writer that packs
    whole codes.
  - SHA-1 with the x86 SHA extensions, AES with AES-NI (`-key`).
  - Windows: model tables of 4 MiB or more are allocated in large pages when
    the user holds the "Lock pages in memory" privilege.
- 64-bit ARM
  - Linux: a JIT compiles ZPAQL and the context model to AArch64 code, as the
    x86 JIT does, with the MIX weights mixed and updated 4 at a time with
    NEON.
  - LZ77 (`-m1`, `-m2`): NEON filtering of hash buckets.
  - SHA-1 and AES (`-key`) with the ARMv8 Crypto Extension.
- All processors
  - Without a JIT (other processors, or `-DNOJIT`), the ZPAQL interpreter
    keeps the machine registers in locals and dispatches through a table of
    labels, which makes it about twice as fast.
  - The JIT translated a run of identical swap instructions (ZPAQL `x<>a`) as
    a single swap. It now follows the specification, like the interpreter.
    The built-in methods never write such runs, only hand-written
    configurations can.

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

### x86

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

### Raspberry Pi 5

The same data on a Raspberry Pi 5 (Cortex-A76, 4 cores, 8 GB, Debian 13,
GCC 14.2, `-O3 -march=native`), 4 threads. Here the fork before the ARM work
(7.16 as of commit `2a4e87b`, already up to 25 % faster than 7.15 on ARM) is
compared with the current one, which adds the AArch64 JIT, NEON and the ARMv8
Crypto Extension.

| Method | Operation | `2a4e87b` | Fork    | Speed-up |
|--------|-----------|----------:|--------:|---------:|
| `-m1`  | add       |    9.3 s  |   9.2 s |    ×1.00 |
|        | extract   |   18.2 s  |   1.9 s |    ×9.53 |
| `-m2`  | add       |   70.6 s  |  70.3 s |    ×1.00 |
|        | extract   |   19.6 s  |   2.2 s |    ×9.08 |
| `-m3`  | add       |   95.4 s  |  85.5 s |    ×1.11 |
|        | extract   |   72.0 s  |  44.5 s |    ×1.62 |
| `-m4`  | add       |  239.4 s  | 176.4 s |    ×1.36 |
|        | extract   |  246.3 s  | 181.1 s |    ×1.36 |
| `-m5`  | add       |  846.1 s  | 553.7 s |    ×1.53 |
|        | extract   |  839.5 s  | 553.3 s |    ×1.52 |

Best of two rounds, the two versions taking turns; the rounds agreed within
1.5 %. The archives have the same size and each version extracts the archives
of the other. The Pi was overclocked to 3.0 GHz, with a fan, and ran at that
frequency the whole time, at 70 °C at most. Compressing with `-m1` and `-m2` is
bound by memory, where the ARM code brings nothing.

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
- The JIT is built for x86 and for 64-bit ARM Linux, and left out
  automatically elsewhere. `make CPPFLAGS="-Dunix -DNOJIT"` leaves it out
  everywhere (keep `-Dunix` on Unix: a `CPPFLAGS` given to make replaces the
  Makefile's).
- `-DNOSHANI` and `-DNOAESNI` leave out the SHA and AES code (x86 and ARM).

[`readme.txt`](readme.txt) is the upstream readme and lists the other compiler
options.

### Tested platforms

Developed and benchmarked on Windows 11 x64. Linux x86-64 builds and passes
`make check` (Ubuntu 24.04, GCC 13). Linux ARM64 builds with the JIT and
passes `make check` with GCC 14 and Clang 19 (Raspberry Pi 5, Debian 13); its
JIT gives the same compressed data as the interpreter on 1400 random ZPAQL
configurations. macOS, BSD, Windows on ARM and 32-bit builds have not been
tested.

## License

Public domain ([Unlicense](COPYING)), like upstream, except the code from
libdivsufsort embedded in `libzpaq.cpp` (© 2003–2008 Yuta Mori, MIT license).

zpaq was written by Matt Mahoney. Please report problems with this fork in its
GitHub issues, not to the upstream author.
