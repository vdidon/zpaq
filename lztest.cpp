// lztest.cpp - Write test data for the LZ77 encoder of libzpaq.
//
// Usage: lztest outfile
//
// The output is 24 MB: 12 MB of pseudo-random bytes, then copies of
// 40000 bytes taken 9 to 11 MB back, each followed by 1 to 8 random
// bytes. The copies give the level 1 LZ77 encoder matches that are both
// long and far, whose variable length codes reach the longest sizes,
// and the short literal runs between them leave every number of bits
// pending in the code writer. A bug in the packing of such codes corrupts
// the output only for a few of these matches, so the data makes many.
// The output is the same on every platform: the generator is a fixed
// xorshift64 sequence.
//
// This file is in the public domain.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned long long U64;

static U64 state=0x9e3779b97f4a7c15ULL;

static unsigned rnd() {
  state^=state<<13;
  state^=state>>7;
  state^=state<<17;
  return unsigned(state>>32);
}

int main(int argc, char** argv) {
  if (argc!=2) {
    fprintf(stderr, "Usage: lztest outfile\n");
    return 1;
  }
  const unsigned BASE=12u<<20, TOTAL=24u<<20, COPY=40000;
  unsigned char* buf=(unsigned char*)malloc(TOTAL+COPY+8);
  if (!buf) {
    fprintf(stderr, "lztest: out of memory\n");
    return 1;
  }
  unsigned n=0;
  while (n<BASE) buf[n++]=rnd();
  while (n<TOTAL) {
    const unsigned off=(9u<<20)+rnd()%(2u<<20);
    memcpy(buf+n, buf+n-off, COPY);
    n+=COPY;
    const unsigned lit=1+rnd()%8;
    for (unsigned i=0; i<lit; ++i) buf[n++]=rnd();
  }
  FILE* f=fopen(argv[1], "wb");
  if (!f || fwrite(buf, 1, n, f)!=n || fclose(f)) {
    fprintf(stderr, "lztest: cannot write %s\n", argv[1]);
    return 1;
  }
  free(buf);
  return 0;
}
