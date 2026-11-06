import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// Ekran süresi: hangi sitede ne kadar kalındığı, gün gün. Veriler yalnız bu cihazda,
// uygulamanın kendi klasöründe tutulur (isteğe bağlı: hesapla öbür cihazlara özet gider).
//
// Kayıt biçimi (screen_time.json):
//   days: { "2026-11-06": { "_": [24 saat], "youtube.com": [24 saat] } }   saniye
//   Son 14 günün saatlik ayrıntısı tutulur; daha eskiler tek sayıya iner. 90 günden eski silinir.

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDay(String k) {
  final p = k.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Siteyi "youtube.com" biçimine indirger (www., m. kalkar).
String siteOf(String host) {
  var h = host.toLowerCase();
  for (final p in ['www.', 'm.', 'mobile.']) {
    if (h.startsWith(p)) h = h.substring(p.length);
  }
  return h;
}

String fmtDuration(int seconds, {bool short = false}) {
  final m = (seconds / 60).round();
  if (m < 1) return seconds > 0 ? '1 dk\'dan az' : '0 dk';
  final h = m ~/ 60;
  final mm = m % 60;
  if (h == 0) return '$mm dk';
  if (mm == 0 || short) return '$h sa';
  return '$h sa $mm dk';
}

/// Site süre sınırı.
class SiteLimit {
  SiteLimit(this.minutes, {this.lock = false});
  int minutes;

  /// true: süre dolunca site o gün kilitlenir; false: yalnız uyarılır.
  bool lock;

  Map<String, dynamic> toJson() => {'m': minutes, 'l': lock};
  static SiteLimit fromJson(Map j) => SiteLimit((j['m'] as num?)?.toInt() ?? 30, lock: j['l'] == true);
}

class ScreenTime extends ChangeNotifier {
  static const total = '_';
  static const keepDays = 90;
  static const hourlyDays = 14;

  /// gün → site → saniye (24 saatlik liste ya da tek sayı)
  final Map<String, Map<String, Object>> _days = {};

  /// Öbür cihazlardan gelen günlük özetler: cihaz adı → gün → site → saniye
  final Map<String, Map<String, Map<String, int>>> remote = {};

  final Map<String, SiteLimit> limits = {};

  /// Bugün için verilen ek süre (dakika) ya da "bugün kilitleme" kararları: site → dakika
  final Map<String, int> _extra = {};
  String _extraDay = '';

  /// Günlük toplam hedef (dakika, 0 = yok)
  int dailyGoal = 0;
  bool weeklySummary = true;
  bool mergeDevices = false;
  bool enabled = true;

  File? _file;
  Timer? _saveTimer;
  bool _dirty = false;

  // ------------------------------------------------------------------ kayıt

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}screen_time.json');
      if (await _file!.exists()) {
        final j = jsonDecode(await _file!.readAsString()) as Map;
        final d = j['days'] as Map? ?? const {};
        for (final e in d.entries) {
          final m = <String, Object>{};
          for (final s in (e.value as Map).entries) {
            final v = s.value;
            if (v is List) {
              m[s.key.toString()] = [for (final x in v) (x as num).toInt()];
            } else if (v is num) {
              m[s.key.toString()] = v.toInt();
            }
          }
          _days[e.key.toString()] = m;
        }
        for (final e in (j['limits'] as Map? ?? const {}).entries) {
          if (e.value is Map) limits[e.key.toString()] = SiteLimit.fromJson(e.value as Map);
        }
        dailyGoal = (j['goal'] as num?)?.toInt() ?? 0;
        weeklySummary = j['weekly'] != false;
        mergeDevices = j['merge'] == true;
        enabled = j['on'] != false;
        _extraDay = j['extraDay']?.toString() ?? '';
        for (final e in (j['extra'] as Map? ?? const {}).entries) {
          _extra[e.key.toString()] = (e.value as num).toInt();
        }
        for (final e in (j['remote'] as Map? ?? const {}).entries) {
          remote[e.key.toString()] = _parseSummary(e.value);
        }
      }
    } catch (_) {}
    _compact();
    notifyListeners();
  }

  static Map<String, Map<String, int>> _parseSummary(Object? v) {
    final out = <String, Map<String, int>>{};
    if (v is! Map) return out;
    for (final d in v.entries) {
      if (d.value is! Map) continue;
      out[d.key.toString()] = {
        for (final s in (d.value as Map).entries)
          if (s.value is num) s.key.toString(): (s.value as num).toInt()
      };
    }
    return out;
  }

  void _saveSoon() {
    _dirty = true;
    _saveTimer ??= Timer(const Duration(seconds: 30), save);
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_dirty || _file == null) return;
    _dirty = false;
    try {
      await _file!.writeAsString(jsonEncode({
        'days': _days,
        'limits': {for (final e in limits.entries) e.key: e.value.toJson()},
        'goal': dailyGoal,
        'weekly': weeklySummary,
        'merge': mergeDevices,
        'on': enabled,
        'extraDay': _extraDay,
        'extra': _extra,
        'remote': remote,
      }));
    } catch (_) {}
  }

  void changed() {
    _saveSoon();
    notifyListeners();
  }

  /// Eski günleri siler, 14 günden eskilerin saatlik ayrıntısını tek sayıya indirir.
  void _compact() {
    final now = DateTime.now();
    final drop = dayKey(now.subtract(const Duration(days: keepDays)));
    final flat = dayKey(now.subtract(const Duration(days: hourlyDays)));
    _days.removeWhere((k, _) => k.compareTo(drop) < 0);
    for (final e in _days.entries) {
      if (e.key.compareTo(flat) >= 0) continue;
      for (final s in e.value.keys.toList()) {
        final v = e.value[s];
        if (v is List<int>) e.value[s] = v.fold<int>(0, (a, b) => a + b);
      }
    }
  }

  void clearAll() {
    _days.clear();
    remote.clear();
    _extra.clear();
    changed();
  }

  // ------------------------------------------------------------------ ölçüm

  /// [site] için [seconds] saniye ekler (toplam ayrıca, [countTotal] ile).
  void add(String? site, int seconds, {bool countTotal = true}) {
    if (!enabled || seconds <= 0) return;
    final now = DateTime.now();
    final day = _days.putIfAbsent(dayKey(now), () => {});
    void put(String key) {
      final v = day[key];
      final List<int> hours = v is List<int> ? v : List<int>.filled(24, 0);
      if (v is int) hours[now.hour] += v; // olmaz ama güvenli
      hours[now.hour] += seconds;
      day[key] = hours;
    }

    if (countTotal) put(total);
    if (site != null && site.isNotEmpty) put(site);
    _saveSoon();
    notifyListeners();
  }

  // ------------------------------------------------------------------ okuma

  static int _sum(Object? v) => v is List<int> ? v.fold<int>(0, (a, b) => a + b) : (v is int ? v : 0);

  /// Bir günün site → saniye listesi (toplam hariç). [all]: öbür cihazlar da eklenir.
  Map<String, int> sitesOn(DateTime d, {bool all = false}) {
    final k = dayKey(d);
    final out = <String, int>{};
    for (final e in (_days[k] ?? const {}).entries) {
      if (e.key == total) continue;
      out[e.key] = _sum(e.value);
    }
    if (all) {
      for (final dev in remote.values) {
        for (final e in (dev[k] ?? const {}).entries) {
          if (e.key == total) continue;
          out[e.key] = (out[e.key] ?? 0) + e.value;
        }
      }
    }
    return out;
  }

  int totalOn(DateTime d, {bool all = false}) {
    final k = dayKey(d);
    var t = _sum(_days[k]?[total]);
    if (all) {
      for (final dev in remote.values) {
        t += dev[k]?[total] ?? 0;
      }
    }
    return t;
  }

  int siteOn(String site, DateTime d, {bool all = false}) => sitesOn(d, all: all)[site] ?? 0;

  /// Bir günün 24 saatlik dağılımı (yalnız bu cihaz; [site] null ise toplam).
  List<int> hoursOn(DateTime d, {String? site}) {
    final v = _days[dayKey(d)]?[site ?? total];
    return v is List<int> ? List<int>.of(v) : List<int>.filled(24, 0);
  }

  /// Son 7 gün (eskiden yeniye) toplamları.
  List<int> week({bool all = false, String? site}) {
    final now = DateTime.now();
    return [
      for (var i = 6; i >= 0; i--)
        site == null
            ? totalOn(now.subtract(Duration(days: i)), all: all)
            : siteOn(site, now.subtract(Duration(days: i)), all: all)
    ];
  }

  /// Son 7 günde site → saniye, çoktan aza.
  List<MapEntry<String, int>> topSites({int days = 7, bool all = false}) {
    final now = DateTime.now();
    final m = <String, int>{};
    for (var i = 0; i < days; i++) {
      for (final e in sitesOn(now.subtract(Duration(days: i)), all: all).entries) {
        m[e.key] = (m[e.key] ?? 0) + e.value;
      }
    }
    final l = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return l;
  }

  // ------------------------------------------------------------------ sınırlar

  void _rollExtra() {
    final today = dayKey(DateTime.now());
    if (_extraDay != today) {
      _extraDay = today;
      _extra.clear();
    }
  }

  /// Bugün bu site için kullanılabilir süre (saniye); sınır yoksa null.
  int? allowedToday(String site) {
    final l = limits[site];
    if (l == null) return null;
    _rollExtra();
    return (l.minutes + (_extra[site] ?? 0)) * 60;
  }

  bool overLimit(String site) {
    final a = allowedToday(site);
    return a != null && siteOn(site, DateTime.now()) >= a;
  }

  bool lockedNow(String site) => (limits[site]?.lock ?? false) && overLimit(site);

  void giveExtra(String site, int minutes) {
    _rollExtra();
    _extra[site] = (_extra[site] ?? 0) + minutes;
    changed();
  }

  // ------------------------------------------------------------------ cihazlar arası

  /// Öbür cihazlara gidecek son 30 günün özeti (site başına en çok 40 site).
  Map<String, Map<String, int>> summaryForSync() {
    final now = DateTime.now();
    final out = <String, Map<String, int>>{};
    for (var i = 0; i < 30; i++) {
      final d = now.subtract(Duration(days: i));
      final s = sitesOn(d);
      final t = totalOn(d);
      if (t == 0 && s.isEmpty) continue;
      final top = s.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      out[dayKey(d)] = {total: t, for (final e in top.take(40)) e.key: e.value};
    }
    return out;
  }

  void setRemote(String device, Object? data) {
    remote[device] = _parseSummary(data);
    changed();
  }
}
