import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'oa_theme.dart';

import 'i18n.dart';
// Başlangıç sayfasındaki saat, tarih ve hava durumu.
// Hava verisi: Open-Meteo (ücretsiz, anahtar gerektirmez). Şehir cihazda saklanır.

final _days = [tx('Pazartesi', 'Monday'), tx('Salı', 'Tuesday'), tx('Çarşamba', 'Wednesday'), tx('Perşembe', 'Thursday'), tx('Cuma', 'Friday'), tx('Cumartesi', 'Saturday'), tx('Pazar', 'Sunday')];
final _daysShort = [tx('Pzt', 'Mon'), tx('Sal', 'Tue'), tx('Çar', 'Wed'), tx('Per', 'Thu'), tx('Cum', 'Fri'), tx('Cmt', 'Sat'), tx('Paz', 'Sun')];
final _months = [tx('Ocak', 'January'), tx('Şubat', 'February'), tx('Mart', 'March'), tx('Nisan', 'April'), tx('Mayıs', 'May'), tx('Haziran', 'June'), tx('Temmuz', 'July'), tx('Ağustos', 'August'), tx('Eylül', 'September'), tx('Ekim', 'October'), tx('Kasım', 'November'), tx('Aralık', 'December')];

String trDate(DateTime d) => tx('${d.day} ${_months[d.month - 1]}, ${_days[d.weekday - 1]}', '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}');
String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class City {
  const City(this.name, this.lat, this.lon, {this.region = ''});
  final String name;
  final double lat;
  final double lon;
  final String region;

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lon': lon, 'region': region};
  static City? fromJson(Map j) {
    final lat = (j['lat'] as num?)?.toDouble();
    final lon = (j['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return City(j['name']?.toString() ?? '', lat, lon, region: j['region']?.toString() ?? '');
  }
}

class HourWx {
  const HourWx(this.time, this.temp, this.code, this.isDay);
  final DateTime time;
  final double temp;
  final int code;
  final bool isDay;
}

class DayWx {
  const DayWx(this.date, this.max, this.min, this.code, this.rain);
  final DateTime date;
  final double max;
  final double min;
  final int code;
  final int rain; // yağış olasılığı %
}

/// WMO hava kodu → açıklama ve simge.
String wxText(int c) => switch (c) {
      0 => tx('Açık', 'Clear'),
      1 => tx('Çoğunlukla açık', 'Mostly clear'),
      2 => tx('Parçalı bulutlu', 'Partly cloudy'),
      3 => tx('Bulutlu', 'Cloudy'),
      45 || 48 => tx('Sisli', 'Foggy'),
      51 || 53 || 55 => tx('Çiseleme', 'Drizzle'),
      56 || 57 => tx('Dondurucu çiseleme', 'Freezing drizzle'),
      61 => tx('Hafif yağmurlu', 'Light rain'),
      63 => tx('Yağmurlu', 'Rain'),
      65 => tx('Şiddetli yağmur', 'Heavy rain'),
      66 || 67 => tx('Dondurucu yağmur', 'Freezing rain'),
      71 => tx('Hafif kar', 'Light snow'),
      73 => tx('Karlı', 'Snow'),
      75 => tx('Yoğun kar', 'Heavy snow'),
      77 => tx('Kar taneleri', 'Snow grains'),
      80 || 81 => tx('Sağanak', 'Showers'),
      82 => tx('Şiddetli sağanak', 'Heavy showers'),
      85 || 86 => tx('Kar sağanağı', 'Snow showers'),
      95 => tx('Gök gürültülü', 'Thunderstorm'),
      96 || 99 => tx('Dolu ve fırtına', 'Hail and thunderstorm'),
      _ => '—',
    };

class WxIcon extends StatelessWidget {
  const WxIcon(this.code, {super.key, this.isDay = true, this.size = 24});
  final int code;
  final bool isDay;
  final double size;

  @override
  Widget build(BuildContext context) {
    const sun = Color(0xFFF7BF6E);
    const rain = Color(0xFF6EA8FE);
    final cloud = OAColors.text2;
    final (IconData icon, Color color) = switch (code) {
      0 || 1 => isDay ? (Icons.wb_sunny_rounded, sun) : (Icons.nightlight_round, sun),
      2 => isDay ? (Icons.wb_cloudy_rounded, cloud) : (Icons.nights_stay_rounded, cloud),
      3 => (Icons.cloud_rounded, cloud),
      45 || 48 => (Icons.foggy, cloud),
      >= 51 && <= 67 => (Icons.water_drop_rounded, rain),
      >= 71 && <= 77 => (Icons.ac_unit_rounded, Colors.white),
      >= 80 && <= 82 => (Icons.umbrella_rounded, rain),
      85 || 86 => (Icons.ac_unit_rounded, Colors.white),
      >= 95 => (Icons.thunderstorm_rounded, sun),
      _ => (Icons.cloud_outlined, cloud),
    };
    // Parçalı bulutluda güneş + bulut
    if (code == 2 && isDay) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(children: [
          Positioned(left: 0, top: 0, child: Icon(Icons.wb_sunny_rounded, size: size * 0.7, color: sun)),
          Positioned(right: 0, bottom: 0, child: Icon(Icons.cloud_rounded, size: size * 0.78, color: cloud)),
        ]),
      );
    }
    return Icon(icon, size: size, color: color);
  }
}

class WeatherService extends ChangeNotifier {
  SharedPreferences? _prefs;
  City? city;
  double? temp;
  int code = 0;
  bool isDay = true;
  List<HourWx> hours = [];
  List<DayWx> days = [];
  DateTime? updated;
  bool loading = false;
  String? error;
  Timer? _timer;

  bool get hasData => temp != null;

  static const _widget = MethodChannel('oa/widget');

  /// Android ana ekran widget'ını (saat ve hava) günceller.
  Future<void> _pushWidget() async {
    if (!Platform.isAndroid) return;
    final c = city;
    final m = <String, dynamic>{
      'city': c?.name,
      'lat': c?.lat.toStringAsFixed(4),
      'lon': c?.lon.toStringAsFixed(4),
      'temp': temp == null ? null : '${temp!.round()}°',
      'code': code,
      'day': isDay,
      'desc': temp == null ? null : wxText(code),
    };
    final cells = <(String, int, bool, String)>[
      for (final h in hours.skip(1).where((h) => h.time.hour % 3 == 0).take(2))
        (hhmm(h.time), h.code, h.isDay, '${h.temp.round()}°'),
      for (final d in days.skip(1).take(2))
        (_daysShort[d.date.weekday - 1], d.code, true, '${d.max.round()}°/${d.min.round()}'),
    ];
    for (var i = 0; i < 4; i++) {
      final has = i < cells.length;
      m['f${i}_l'] = has ? cells[i].$1 : null;
      m['f${i}_c'] = has ? cells[i].$2 : null;
      m['f${i}_d'] = has ? cells[i].$3 : null;
      m['f${i}_t'] = has ? cells[i].$4 : null;
    }
    try {
      await _widget.invokeMethod('hava', m);
    } catch (_) {}
  }

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    try {
      final c = prefs.getString('weather_city');
      if (c != null) city = City.fromJson(jsonDecode(c) as Map);
      final cache = prefs.getString('weather_cache');
      if (cache != null) _parse(jsonDecode(cache) as Map);
    } catch (_) {}
    notifyListeners();
    _pushWidget();
    refresh();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> setCity(City c) async {
    city = c;
    temp = null;
    hours = [];
    days = [];
    _prefs?.setString('weather_city', jsonEncode(c.toJson()));
    _prefs?.remove('weather_cache');
    notifyListeners();
    _pushWidget();
    await refresh(force: true);
  }

  Future<void> refresh({bool force = false}) async {
    final c = city;
    if (c == null || loading) return;
    if (!force && updated != null && DateTime.now().difference(updated!) < const Duration(minutes: 25)) return;
    loading = true;
    notifyListeners();
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': c.lat.toStringAsFixed(4),
        'longitude': c.lon.toStringAsFixed(4),
        'current': 'temperature_2m,weather_code,is_day',
        'hourly': 'temperature_2m,weather_code,is_day',
        'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max',
        'timezone': 'auto',
        'forecast_days': '8',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      _parse(j);
      updated = DateTime.now();
      error = null;
      _prefs?.setString('weather_cache', jsonEncode(j));
      _pushWidget();
    } catch (e) {
      error = tx('Hava durumu alınamadı', "Couldn't get the weather");
    }
    loading = false;
    notifyListeners();
  }

  void _parse(Map j) {
    final cur = j['current'] as Map?;
    if (cur != null) {
      temp = (cur['temperature_2m'] as num?)?.toDouble();
      code = (cur['weather_code'] as num?)?.toInt() ?? 0;
      isDay = cur['is_day'] == 1;
    }
    final h = j['hourly'] as Map?;
    if (h != null) {
      final times = (h['time'] as List).map((e) => DateTime.parse(e.toString())).toList();
      final t = h['temperature_2m'] as List;
      final c = h['weather_code'] as List;
      final d = h['is_day'] as List?;
      final now = DateTime.now().subtract(const Duration(minutes: 59));
      hours = [
        for (var i = 0; i < times.length; i++)
          if (times[i].isAfter(now) && t[i] != null)
            HourWx(times[i], (t[i] as num).toDouble(), (c[i] as num?)?.toInt() ?? 0, d == null || d[i] == 1),
      ].take(24).toList();
    }
    final dl = j['daily'] as Map?;
    if (dl != null) {
      final times = (dl['time'] as List).map((e) => DateTime.parse(e.toString())).toList();
      final mx = dl['temperature_2m_max'] as List;
      final mn = dl['temperature_2m_min'] as List;
      final c = dl['weather_code'] as List;
      final p = dl['precipitation_probability_max'] as List?;
      days = [
        for (var i = 0; i < times.length; i++)
          if (mx[i] != null && mn[i] != null)
            DayWx(times[i], (mx[i] as num).toDouble(), (mn[i] as num).toDouble(), (c[i] as num?)?.toInt() ?? 0,
                (p?[i] as num?)?.toInt() ?? 0),
      ];
    }
    final upd = cur?['time'];
    if (upd != null) updated ??= DateTime.tryParse(upd.toString());
  }

  static Future<List<City>> searchCities(String q) async {
    if (q.trim().length < 2) return [];
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search',
        {'name': q.trim(), 'count': '10', 'language': L.code, 'format': 'json'});
    final r = await http.get(uri).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return [];
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    return [
      for (final m in (j['results'] as List? ?? const []).whereType<Map>())
        City(
          m['name']?.toString() ?? '',
          (m['latitude'] as num).toDouble(),
          (m['longitude'] as num).toDouble(),
          region: [m['admin1'], m['country']].where((e) => e != null && e.toString().isNotEmpty).join(', '),
        ),
    ];
  }
}

/// Dakikada bir yenilenen saat.
class _Ticker extends StatefulWidget {
  const _Ticker({required this.builder});
  final Widget Function(BuildContext, DateTime) builder;
  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  Timer? _t;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    final n = DateTime.now();
    _t = Timer(Duration(seconds: 60 - n.second, milliseconds: -n.millisecond + 20), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _schedule();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}

String _deg(double v) => '${v.round()}°';

/// Bilgisayar: sağ üst köşede büyük saat, tarih ve hava (taslaktaki A).
class ClockWeatherCorner extends StatelessWidget {
  const ClockWeatherCorner({super.key, required this.wx});
  final WeatherService wx;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wx,
      builder: (context, _) => _Ticker(
        builder: (context, now) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(hhmm(now), style: oaDisplay(58).copyWith(height: 1, letterSpacing: -2.2)),
            const SizedBox(height: 4),
            Text(trDate(now), style: TextStyle(color: OAColors.text2, fontSize: 15)),
            const SizedBox(height: 10),
            _WxButton(wx: wx, big: true),
          ],
        ),
      ),
    );
  }
}

class _WxButton extends StatelessWidget {
  const _WxButton({required this.wx, this.big = false});
  final WeatherService wx;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (wx.city == null) {
      child = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wb_cloudy_outlined, size: 20, color: OAColors.text2),
        const SizedBox(width: 8),
        Text(tx('Hava durumu için şehir seç', 'Choose a city for the weather'), style: TextStyle(color: OAColors.text2, fontSize: 14)),
      ]);
    } else if (!wx.hasData) {
      child = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wb_cloudy_outlined, size: 20, color: OAColors.muted),
        const SizedBox(width: 8),
        Text(wx.loading ? tx('${wx.city!.name} · yükleniyor…', '${wx.city!.name} · loading…') : (wx.error ?? wx.city!.name),
            style: TextStyle(color: OAColors.muted, fontSize: 14)),
      ]);
    } else {
      child = Row(mainAxisSize: MainAxisSize.min, children: [
        WxIcon(wx.code, isDay: wx.isDay, size: big ? 30 : 24),
        const SizedBox(width: 8),
        Text(_deg(wx.temp!), style: oaDisplay(big ? 26 : 22)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(wxText(wx.code), style: TextStyle(color: OAColors.text2, fontSize: 13)),
          Text(wx.city!.name, style: TextStyle(color: OAColors.muted, fontSize: 12.5)),
        ]),
      ]);
    }
    return Material(
      color: OAColors.surface.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showWeatherDetails(context, wx),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: child),
      ),
    );
  }
}

/// Telefon: arama kutusunun altında saat + hava kartı (taslaktaki C).
class ClockWeatherCard extends StatelessWidget {
  const ClockWeatherCard({super.key, required this.wx});
  final WeatherService wx;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: wx,
      builder: (context, _) => _Ticker(
        builder: (context, now) {
          final next = <(String, int, bool, String)>[
            for (final h in wx.hours.skip(1).where((h) => h.time.hour % 3 == 0).take(3))
              (hhmm(h.time), h.code, h.isDay, _deg(h.temp)),
            for (final d in wx.days.skip(1).take(2))
              (_daysShort[d.date.weekday - 1], d.code, true, '${d.max.round()}°/${d.min.round()}'),
          ];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => showWeatherDetails(context, wx),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: OAColors.border2),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      OAColors.amber.withValues(alpha: 0.16),
                      OAColors.surface.withValues(alpha: 0.85),
                      const Color(0xFF6EA8FE).withValues(alpha: 0.10),
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(hhmm(now), style: oaDisplay(46).copyWith(height: 1, letterSpacing: -1.6)),
                            const SizedBox(height: 4),
                            Text(trDate(now), style: TextStyle(color: OAColors.text2, fontSize: 14)),
                          ]),
                        ),
                        if (wx.hasData)
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              WxIcon(wx.code, isDay: wx.isDay, size: 32),
                              const SizedBox(width: 6),
                              Text(_deg(wx.temp!), style: oaDisplay(34)),
                            ]),
                            const SizedBox(height: 2),
                            Text('${wx.city!.name} · ${wxText(wx.code)}',
                                style: TextStyle(color: OAColors.muted, fontSize: 12.5)),
                          ])
                        else
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              wx.city == null
                                  ? tx('Hava durumu için\nşehir seç ›', 'Choose a city\nfor the weather ›')
                                  : (wx.loading ? tx('Yükleniyor…', 'Loading…') : (wx.error ?? '')),
                              textAlign: TextAlign.right,
                              style: TextStyle(color: OAColors.text2, fontSize: 13.5),
                            ),
                          ),
                      ],
                    ),
                    if (next.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Divider(height: 1, color: OAColors.text.withValues(alpha: 0.08)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (final n in next)
                            Expanded(
                              child: Column(children: [
                                Text(n.$1, style: TextStyle(color: OAColors.muted, fontSize: 12)),
                                const SizedBox(height: 4),
                                WxIcon(n.$2, isDay: n.$3, size: 22),
                                const SizedBox(height: 4),
                                Text(n.$4,
                                    style: TextStyle(
                                        color: OAColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Saatlik ve 7 günlük tahmin; şehir değiştirme.
Future<void> showWeatherDetails(BuildContext context, WeatherService wx) async {
  if (wx.city == null) {
    await pickCity(context, wx);
    return;
  }
  wx.refresh();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => ListenableBuilder(
      listenable: wx,
      builder: (ctx, _) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          children: [
            Row(children: [
              Expanded(child: Text(wx.city!.name, style: oaDisplay(26))),
              TextButton.icon(
                icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
                label: Text(tx('Şehri değiştir', 'Change city')),
                onPressed: () => pickCity(ctx, wx),
              ),
            ]),
            if (wx.city!.region.isNotEmpty)
              Text(wx.city!.region, style: TextStyle(color: OAColors.muted, fontSize: 13)),
            const SizedBox(height: 14),
            if (wx.hasData)
              Row(children: [
                WxIcon(wx.code, isDay: wx.isDay, size: 48),
                const SizedBox(width: 12),
                Text(_deg(wx.temp!), style: oaDisplay(48)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(wxText(wx.code), style: TextStyle(color: OAColors.text, fontSize: 16)),
                    if (wx.days.isNotEmpty)
                      Text(tx('En yüksek ${_deg(wx.days.first.max)} · en düşük ${_deg(wx.days.first.min)}', 'High ${_deg(wx.days.first.max)} · low ${_deg(wx.days.first.min)}'),
                          style: TextStyle(color: OAColors.muted, fontSize: 13)),
                  ]),
                ),
              ])
            else
              Text(wx.loading ? tx('Yükleniyor…', 'Loading…') : (wx.error ?? ''), style: TextStyle(color: OAColors.muted)),
            const SizedBox(height: 20),
            if (wx.hours.isNotEmpty) ...[
              Text(tx('Saatlik', 'Hourly'), style: oaDisplay(18)),
              const SizedBox(height: 10),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: wx.hours.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final h = wx.hours[i];
                    return Container(
                      width: 62,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: OAColors.surface2,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(i == 0 ? tx('Şimdi', 'Now') : hhmm(h.time), style: TextStyle(color: OAColors.muted, fontSize: 12)),
                        WxIcon(h.code, isDay: h.isDay, size: 24),
                        Text(_deg(h.temp), style: TextStyle(color: OAColors.text, fontWeight: FontWeight.w600)),
                      ]),
                    );
                  },
                ),
              ),
              const SizedBox(height: 22),
            ],
            if (wx.days.isNotEmpty) ...[
              Text(tx('7 gün', '7 days'), style: oaDisplay(18)),
              const SizedBox(height: 6),
              for (final d in wx.days.take(7))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        d.date.day == DateTime.now().day ? tx('Bugün', 'Today') : _days[d.date.weekday - 1],
                        style: TextStyle(color: OAColors.text, fontSize: 15),
                      ),
                    ),
                    WxIcon(d.code, size: 24),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 48,
                      child: d.rain >= 20
                          ? Text('%${d.rain}', style: const TextStyle(color: Color(0xFF6EA8FE), fontSize: 13))
                          : null,
                    ),
                    const Spacer(),
                    Text(_deg(d.min), style: TextStyle(color: OAColors.muted, fontSize: 15)),
                    const SizedBox(width: 14),
                    Text(_deg(d.max), style: TextStyle(color: OAColors.text, fontSize: 15, fontWeight: FontWeight.w600)),
                  ]),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              tx('Veri: Open-Meteo${wx.updated != null ? ' · ${hhmm(wx.updated!)} güncellendi' : ''}', "Data: Open-Meteo${wx.updated != null ? ' · updated ${hhmm(wx.updated!)}' : ''}"),
              style: TextStyle(color: OAColors.faint, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Şehir arama ve seçme.
Future<void> pickCity(BuildContext context, WeatherService wx) async {
  final picked = await showDialog<City>(context: context, builder: (_) => const _CityDialog());
  if (picked != null) await wx.setCity(picked);
}

class _CityDialog extends StatefulWidget {
  const _CityDialog();
  @override
  State<_CityDialog> createState() => _CityDialogState();
}

class _CityDialogState extends State<_CityDialog> {
  static const _popular = [
    City('İstanbul', 41.0138, 28.9497, region: 'Türkiye'),
    City('Ankara', 39.9199, 32.8543, region: 'Türkiye'),
    City('İzmir', 38.4127, 27.1384, region: 'Türkiye'),
    City('Bursa', 40.1956, 29.0601, region: 'Türkiye'),
    City('Antalya', 36.9081, 30.6956, region: 'Türkiye'),
    City('Adana', 37.0017, 35.3289, region: 'Türkiye'),
  ];
  List<City> _results = _popular;
  Timer? _debounce;
  bool _loading = false;
  int _req = 0;

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (q.trim().length < 2) {
        setState(() => _results = _popular);
        return;
      }
      final id = ++_req;
      setState(() => _loading = true);
      List<City> r = [];
      try {
        r = await WeatherService.searchCities(q);
      } catch (_) {}
      if (!mounted || id != _req) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tx('Şehir seç', 'Choose city')),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tx('Şehir ya da ilçe yaz', 'Type a city or district'),
              suffixIcon: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : null,
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _results.isEmpty
                ? Center(child: Text(tx('Sonuç yok', 'No results'), style: TextStyle(color: OAColors.muted)))
                : ListView(
                    children: [
                      for (final c in _results)
                        ListTile(
                          leading: const Icon(Icons.location_on_outlined),
                          title: Text(c.name),
                          subtitle: c.region.isEmpty ? null : Text(c.region),
                          onTap: () => Navigator.pop(context, c),
                        ),
                    ],
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('Vazgeç', 'Cancel')))],
    );
  }
}
