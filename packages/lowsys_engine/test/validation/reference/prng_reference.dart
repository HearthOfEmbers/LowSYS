// Independent xoshiro128** (Blackman & Vigna 2018, reference C:
//   result = rotl(s[1] * 5, 7) * 9; t = s[1] << 9; s[2] ^= s[0]; s[3] ^= s[1];
//   s[1] ^= s[2]; s[0] ^= s[3]; s[2] ^= t; s[3] = rotl(s[3], 11);)
// with the LowSYS stream seeding of PHYSICS.md §12.9 (FNV-1a-32 of the key,
// four LCG steps, 16 discarded outputs), the 53-bit uniform and Box–Muller.
// Written with 32-bit-safe arithmetic only (no products above 2^53), so the
// same code is exact on the web. No engine imports.
library;

import 'dart:math' as math;

const int _m = 0xFFFFFFFF;

int rotl32(int x, int k) => ((x << k) | (x >>> (32 - k))) & _m;

int fnv1a32(String key) {
  var h = 2166136261;
  for (final b in key.codeUnits.expand(_utf8)) {
    h ^= b;
    h = ((h << 24) + 403 * h) & _m; // = h * 16777619 mod 2^32
  }
  return h;
}

Iterable<int> _utf8(int cu) sync* {
  // keys are ASCII in practice; encode BMP code units as UTF-8 for safety
  if (cu < 0x80) {
    yield cu;
  } else if (cu < 0x800) {
    yield 0xC0 | (cu >> 6);
    yield 0x80 | (cu & 0x3F);
  } else {
    yield 0xE0 | (cu >> 12);
    yield 0x80 | ((cu >> 6) & 0x3F);
    yield 0x80 | (cu & 0x3F);
  }
}

class Xoshiro128ss {
  int s0, s1, s2, s3;
  double? _cachedNormal;

  Xoshiro128ss.raw(this.s0, this.s1, this.s2, this.s3);

  factory Xoshiro128ss.stream(int seed, String key) {
    var x = (seed ^ fnv1a32(key)) & _m;
    final s = List<int>.filled(4, 0);
    for (var i = 0; i < 4; i++) {
      x = (69069 * x + 1) & _m;
      s[i] = x;
    }
    final g = Xoshiro128ss.raw(s[0], s[1], s[2], s[3]);
    for (var i = 0; i < 16; i++) {
      g.next32();
    }
    return g;
  }

  int next32() {
    final result = (rotl32((s1 * 5) & _m, 7) * 9) & _m;
    final t = (s1 << 9) & _m;
    s2 ^= s0;
    s3 ^= s1;
    s1 ^= s2;
    s0 ^= s3;
    s2 ^= t;
    s3 = rotl32(s3, 11);
    return result;
  }

  double uniform() {
    final a = next32() >>> 5;
    final b = next32() >>> 6;
    return (a * 67108864 + b) / 9007199254740992;
  }

  double normal() {
    final c = _cachedNormal;
    if (c != null) {
      _cachedNormal = null;
      return c;
    }
    final u1 = 1 - uniform();
    final u2 = uniform();
    final r = math.sqrt(-2 * math.log(u1));
    _cachedNormal = r * math.sin(2 * math.pi * u2);
    return r * math.cos(2 * math.pi * u2);
  }
}
