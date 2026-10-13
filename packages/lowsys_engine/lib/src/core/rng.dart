import 'dart:convert';
import 'dart:math' as math;

const int _m32 = 0xFFFFFFFF;

int _rotl(int x, int k) => ((x << k) | (x >>> (32 - k))) & _m32;

/// FNV-1a 32-bit hash of the UTF-8 bytes of [key] (PHYSICS.md 12.9).
int fnv1a32(String key) {
  var h = 2166136261;
  for (final b in utf8.encode(key)) {
    h ^= b;
    h = ((h << 24) + 403 * h) &
        _m32; // = h * 16777619 mod 2^32 without a 57-bit product
  }
  return h;
}

/// xoshiro128** with 32-bit-only arithmetic, so native and web agree (PHYSICS.md 12.9).
/// Every random process owns one stream, keyed by a string, so adding an instrument or a fault never
/// changes the numbers another process sees.
class Rng {
  int _s0, _s1, _s2, _s3;
  double? _spare;

  Rng._(this._s0, this._s1, this._s2, this._s3);

  /// Stream for an integer [seed] (0 <= seed < 2^32) and a string [key].
  factory Rng.stream(int seed, String key) {
    final h = fnv1a32(key);
    var x = (seed ^ h) & _m32;
    final s = List<int>.filled(4, 0);
    for (var i = 0; i < 4; i++) {
      x = (69069 * x + 1) & _m32;
      s[i] = x;
    }
    final r = Rng._(s[0], s[1], s[2], s[3]);
    for (var i = 0; i < 16; i++) {
      r.next32();
    }
    return r;
  }

  int next32() {
    final result = (_rotl((_s1 * 5) & _m32, 7) * 9) & _m32;
    final t = (_s1 << 9) & _m32;
    _s2 ^= _s0;
    _s3 ^= _s1;
    _s1 ^= _s2;
    _s0 ^= _s3;
    _s2 ^= t;
    _s3 = _rotl(_s3, 11);
    return result;
  }

  /// Uniform in [0, 1) with 53 random bits.
  double uniform() {
    final a = next32() >>> 5;
    final b = next32() >>> 6;
    return (a * 67108864 + b) / 9007199254740992;
  }

  /// Standard normal by Box-Muller with a cached second value.
  double normal() {
    final sp = _spare;
    if (sp != null) {
      _spare = null;
      return sp;
    }
    final u1 = 1 - uniform();
    final u2 = uniform();
    final r = math.sqrt(-2 * math.log(u1));
    _spare = r * math.sin(2 * math.pi * u2);
    return r * math.cos(2 * math.pi * u2);
  }

  Map<String, Object?> toJson() => {
        's': [_s0, _s1, _s2, _s3],
        'spare': _spare
      };

  void loadJson(Map<String, Object?> j) {
    final s =
        (j['s']! as List<Object?>).map((e) => (e! as num).toInt()).toList();
    _s0 = s[0];
    _s1 = s[1];
    _s2 = s[2];
    _s3 = s[3];
    _spare = (j['spare'] as num?)?.toDouble();
  }
}

/// Exact Ornstein-Uhlenbeck process (PHYSICS.md 10.5): statistics independent of the update interval.
class OuNoise {
  double value = 0;
  final double sigma, tau;
  OuNoise(this.sigma, this.tau);

  double _h = -1, _a = 0, _b = 0;

  double step(double h, Rng rng) {
    if (h != _h) {
      _h = h;
      _a = math.exp(-h / tau);
      _b = sigma * math.sqrt(1 - _a * _a);
    }
    value = _a * value + _b * rng.normal();
    return value;
  }
}
