import 'dart:typed_data';

/// Rolling trend store: 5-s bins for 2 h (1440 bins), each series with mean, min, max and the worst quality
/// seen in the bin (ENGINE_API.md 5.4). The trend painter draws min-max envelopes so spikes survive
/// decimation; cross-checks read the bin means.
class TrendBuffer {
  static const double binSeconds = 5.0;
  static const int capacity = 1440;

  final Map<String, int> _index = {};
  final List<String> names = [];
  final List<Float64List> _mean = [];
  final List<Float64List> _min = [];
  final List<Float64List> _max = [];
  final List<Uint8List> _qual = [];
  final List<double> _sum = [];
  final List<double> _cmin = [];
  final List<double> _cmax = [];
  final List<int> _n = [];
  final List<int> _cq = [];

  /// Number of closed bins (up to [capacity]) and the absolute index of the next bin to be written.
  int count = 0;
  int _nextBin = 0;
  int _curBin = 0;

  int register(String name) {
    final existing = _index[name];
    if (existing != null) return existing;
    final i = names.length;
    _index[name] = i;
    names.add(name);
    _mean.add(Float64List(capacity));
    _min.add(Float64List(capacity));
    _max.add(Float64List(capacity));
    _qual.add(Uint8List(capacity));
    _sum.add(0);
    _cmin.add(double.infinity);
    _cmax.add(double.negativeInfinity);
    _n.add(0);
    _cq.add(0);
    return i;
  }

  int? indexOf(String name) => _index[name];
  bool has(String name) => _index.containsKey(name);

  /// Adds one update of series [i] to the current bin. [quality] is the Quality enum index.
  void push(int i, double v, [int quality = 0]) {
    if (v.isNaN) return;
    _sum[i] += v;
    _n[i]++;
    if (v < _cmin[i]) _cmin[i] = v;
    if (v > _cmax[i]) _cmax[i] = v;
    if (quality > _cq[i]) _cq[i] = quality;
  }

  /// Closes every bin that ended at or before time [t].
  void advance(double t) {
    final target = (t / binSeconds + 1e-9).floor();
    while (_curBin < target) {
      _close();
      _curBin++;
    }
  }

  void _close() {
    final slot = _nextBin % capacity;
    for (var i = 0; i < names.length; i++) {
      final n = _n[i];
      if (n > 0) {
        _mean[i][slot] = _sum[i] / n;
        _min[i][slot] = _cmin[i];
        _max[i][slot] = _cmax[i];
      } else {
        // no samples (series not updated): carry the previous mean
        final prev = (slot - 1 + capacity) % capacity;
        final m = count > 0 ? _mean[i][prev] : 0.0;
        _mean[i][slot] = m;
        _min[i][slot] = m;
        _max[i][slot] = m;
      }
      _qual[i][slot] = _cq[i];
      _sum[i] = 0;
      _n[i] = 0;
      _cmin[i] = double.infinity;
      _cmax[i] = double.negativeInfinity;
      _cq[i] = 0;
    }
    _nextBin++;
    if (count < capacity) count++;
  }

  /// Bin [k] counted from the oldest stored bin (0) to the newest (count - 1).
  int _slot(int k) => ((_nextBin - count + k) % capacity + capacity) % capacity;

  double mean(int i, int k) => _mean[i][_slot(k)];
  double minAt(int i, int k) => _min[i][_slot(k)];
  double maxAt(int i, int k) => _max[i][_slot(k)];
  int qualityAt(int i, int k) => _qual[i][_slot(k)];

  /// Mean of the bin means over bins [from, to) counted from the newest backwards: 0 is the newest bin.
  double windowMean(int i, int newestOffset, int bins) {
    if (count < newestOffset + bins) return double.nan;
    var s = 0.0;
    for (var b = 0; b < bins; b++) {
      s += mean(i, count - 1 - newestOffset - b);
    }
    return s / bins;
  }

  /// Sum of bin means x 5 s over the newest [bins] bins.
  double integral(int i, int bins) {
    if (count < bins) return double.nan;
    var s = 0.0;
    for (var b = 0; b < bins; b++) {
      s += mean(i, count - 1 - b);
    }
    return s * binSeconds;
  }

  /// Time (s) at the end of the newest closed bin.
  double get newestEnd => _nextBin * binSeconds;

  /// Closed bins of the named series newer than the absolute bin index in [synced] (0 for a series not yet mirrored),
  /// for a background runner to send to a mirror buffer ([ingest]). Plain lists, safe to send between isolates.
  Map<String, Object?> exportSince(Map<String, int> synced) {
    final out = <String, Object?>{};
    for (final e in synced.entries) {
      final i = _index[e.key];
      if (i == null) continue;
      final from = e.value < _nextBin - count ? _nextBin - count : e.value;
      if (from >= _nextBin) continue;
      out[e.key] = [
        from,
        [for (var b = from; b < _nextBin; b++) _mean[i][b % capacity]],
        [for (var b = from; b < _nextBin; b++) _min[i][b % capacity]],
        [for (var b = from; b < _nextBin; b++) _max[i][b % capacity]],
        [for (var b = from; b < _nextBin; b++) _qual[i][b % capacity]],
      ];
    }
    return {"count": count, "nextBin": _nextBin, "curBin": _curBin, "series": out};
  }

  /// Applies an [exportSince] payload to this mirror buffer; returns the new synced bin (the sender's next bin).
  int ingest(Map<String, Object?> p) {
    final next = p["nextBin"]! as int;
    final series = p["series"]! as Map<Object?, Object?>;
    for (final e in series.entries) {
      final i = register(e.key! as String);
      final l = e.value! as List<Object?>;
      final from = l[0]! as int;
      final mean = l[1]! as List<Object?>, mn = l[2]! as List<Object?>, mx = l[3]! as List<Object?>, q = l[4]! as List<Object?>;
      for (var k = 0; k < mean.length; k++) {
        final slot = (from + k) % capacity;
        _mean[i][slot] = mean[k]! as double;
        _min[i][slot] = mn[k]! as double;
        _max[i][slot] = mx[k]! as double;
        _qual[i][slot] = q[k]! as int;
      }
    }
    count = p["count"]! as int;
    _nextBin = next;
    _curBin = p["curBin"]! as int;
    return next;
  }

  /// Forgets every stored bin (after a warm start or a re-initialisation).
  void reset() {
    count = 0;
    _nextBin = 0;
    _curBin = 0;
    for (var i = 0; i < names.length; i++) {
      _sum[i] = 0;
      _n[i] = 0;
      _cmin[i] = double.infinity;
      _cmax[i] = double.negativeInfinity;
      _cq[i] = 0;
    }
  }

  List<double> _chron(Float64List a) =>
      [for (var k = 0; k < count; k++) a[_slot(k)]];

  /// Only the stored bins are saved, oldest first.
  Map<String, Object?> toJson() => {
        'names': names,
        'count': count,
        'nextBin': _nextBin,
        'curBin': _curBin,
        'mean': [for (final a in _mean) _chron(a)],
        'min': [for (final a in _min) _chron(a)],
        'max': [for (final a in _max) _chron(a)],
        'qual': [
          for (final a in _qual) [for (var k = 0; k < count; k++) a[_slot(k)]]
        ],
        'sum': _sum,
        'cmin': [for (final v in _cmin) v.isFinite ? v : null],
        'cmax': [for (final v in _cmax) v.isFinite ? v : null],
        'n': _n,
        'cq': _cq,
      };

  void loadJson(Map<String, Object?> j) {
    count = (j['count']! as num).toInt();
    _nextBin = (j['nextBin']! as num).toInt();
    _curBin = (j['curBin']! as num).toInt();
    void fill(List<Float64List> dst, Object? src) {
      final l = src! as List<Object?>;
      for (var i = 0; i < dst.length && i < l.length; i++) {
        final arr = l[i]! as List<Object?>;
        for (var k = 0; k < arr.length; k++) {
          dst[i][_slot(k)] = (arr[k]! as num).toDouble();
        }
      }
    }

    fill(_mean, j['mean']);
    fill(_min, j['min']);
    fill(_max, j['max']);
    final q = j['qual']! as List<Object?>;
    for (var i = 0; i < _qual.length && i < q.length; i++) {
      final arr = q[i]! as List<Object?>;
      for (var k = 0; k < arr.length; k++) {
        _qual[i][_slot(k)] = (arr[k]! as num).toInt();
      }
    }
    final sm = j['sum']! as List<Object?>,
        cmin = j['cmin']! as List<Object?>,
        cmax = j['cmax']! as List<Object?>;
    final n = j['n']! as List<Object?>, cq = j['cq']! as List<Object?>;
    for (var i = 0; i < names.length && i < sm.length; i++) {
      _sum[i] = (sm[i]! as num).toDouble();
      _cmin[i] = (cmin[i] as num?)?.toDouble() ?? double.infinity;
      _cmax[i] = (cmax[i] as num?)?.toDouble() ?? double.negativeInfinity;
      _n[i] = (n[i]! as num).toInt();
      _cq[i] = (cq[i]! as num).toInt();
    }
  }
}
