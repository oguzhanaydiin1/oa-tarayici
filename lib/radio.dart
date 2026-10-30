import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'web_env.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'oa_theme.dart';

/// Bir radyo istasyonu (OA Radyo ile aynı alanlar).
class Station {
  const Station({
    required this.id,
    required this.name,
    required this.url,
    this.hls = false,
    this.favicon = '',
    this.tags = const [],
    this.country = '',
  });

  final String id;
  final String name;
  final String url;
  final bool hls;
  final String favicon;
  final List<String> tags;
  final String country;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'url': url, 'hls': hls, 'favicon': favicon, 'tags': tags, 'country': country};

  static Station? fromJson(Map j) {
    final url = (j['url'] ?? '').toString();
    if (!url.startsWith('http')) return null;
    return Station(
      id: (j['id'] ?? url).toString(),
      name: (j['name'] ?? 'Adsız istasyon').toString(),
      url: url,
      hls: j['hls'] == true,
      favicon: (j['favicon'] ?? '').toString(),
      tags: (j['tags'] is List) ? (j['tags'] as List).map((e) => e.toString()).toList() : const [],
      country: (j['country'] ?? '').toString(),
    );
  }

  /// Radio Browser API kaydından.
  static Station? fromBrowser(Map j) {
    final url = (j['url_resolved'] ?? j['url'] ?? '').toString().trim();
    if (!url.startsWith('http')) return null;
    return Station(
      id: (j['stationuuid'] ?? url).toString(),
      name: (j['name'] ?? '').toString().trim().isEmpty ? 'Adsız istasyon' : j['name'].toString().trim(),
      url: url,
      hls: j['hls'] == 1 || j['hls'] == true || url.contains('.m3u8'),
      favicon: (j['favicon'] ?? '').toString(),
      tags: (j['tags'] ?? '').toString().split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).take(4).toList(),
      country: (j['countrycode'] ?? '').toString(),
    );
  }
}

enum RadioState { idle, loading, playing, paused, error }

/// Tarayıcının içindeki radyo çalar. Ses görünmez bir web görünümünde çalar
/// (HLS yayınları için hls.js, OA Radyo'nun web sürümüyle aynı); böylece Android ve
/// Windows'ta aynı kodla çalışır, gezinirken sekmeler değişse de radyo susmaz.
class RadioPlayer extends ChangeNotifier {
  static const _servers = ['de1.api.radio-browser.info', 'de2.api.radio-browser.info', 'fi1.api.radio-browser.info'];
  static const _extraUrl =
      'https://raw.githubusercontent.com/oguzhanaydiin1/radyo-app/main/stations/ek-istasyonlar.json';

  HeadlessInAppWebView? _web;
  InAppWebViewController? _c;
  String? _html;

  /// Windows: Edge motoru görünmeyen sayfada sesi başlatmıyor (arka plan sekmesi gibi erteliyor).
  /// Bu yüzden radyo sayfası pencerenin köşesinde 1×1 piksellik görünür bir web görünümünde çalar
  /// ([host]); Android'de ekranda yer kaplamayan görünmez web görünümü yeterli.
  bool hostRequested = false;
  Completer<void>? _hostReady;
  Future<void>? _starting;
  SharedPreferences? _prefs;

  Station? station;
  RadioState state = RadioState.idle;
  String? error;
  double volume = 1;
  List<Station> favorites = [];
  List<Station>? _popular;

  bool get active => station != null;
  bool get playing => state == RadioState.playing || state == RadioState.loading;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    try {
      favorites = (jsonDecode(prefs.getString('radio_favs') ?? '[]') as List)
          .whereType<Map>()
          .map(Station.fromJson)
          .whereType<Station>()
          .toList();
      final last = prefs.getString('radio_last');
      if (last != null) station = Station.fromJson(jsonDecode(last) as Map);
      if (station != null) state = RadioState.paused;
    } catch (_) {}
    notifyListeners();
  }

  bool isFavorite(Station s) => favorites.any((f) => f.id == s.id);

  void toggleFavorite(Station s) {
    if (isFavorite(s)) {
      favorites.removeWhere((f) => f.id == s.id);
    } else {
      favorites.insert(0, s);
    }
    _prefs?.setString('radio_favs', jsonEncode(favorites.map((f) => f.toJson()).toList()));
    notifyListeners();
  }

  Future<void> _ensureWeb() => _starting ??= _startWeb();

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        transparentBackground: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      );

  // http taban adresi: pek çok radyo yayını http; https sayfada "karışık içerik" diye engellenir.
  InAppWebViewInitialData get _initialData =>
      InAppWebViewInitialData(data: _html!, baseUrl: WebUri('http://oa-radyo.local/'));

  void _attach(InAppWebViewController c) {
    _c = c;
    c.addJavaScriptHandler(
      handlerName: 'radio',
      callback: (args) {
        final s = args.isNotEmpty ? args[0].toString() : '';
        final e = args.length > 1 ? args[1].toString() : '';
        state = switch (s) {
          'playing' => RadioState.playing,
          'loading' => RadioState.loading,
          'paused' => RadioState.paused,
          'error' => RadioState.error,
          _ => state,
        };
        error = s == 'error' ? (e.isEmpty ? 'Yayın açılamadı' : 'Yayın açılamadı ($e)') : null;
        notifyListeners();
      },
    );
  }

  Future<void> _startWeb() async {
    final hls = await rootBundle.loadString('assets/hls.min.js');
    _html = """<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;background:transparent">
<audio id="a" preload="none"></audio>
<script>$hls</script>
<script>
var a = document.getElementById('a'), h = null;
function send(s, e){ try { window.flutter_inappwebview.callHandler('radio', s, e || ''); } catch (x) {} }
a.addEventListener('playing', function(){ send('playing'); });
a.addEventListener('waiting', function(){ send('loading'); });
a.addEventListener('pause', function(){ send('paused'); });
a.addEventListener('error', function(){ send('error', a.error ? ('kod ' + a.error.code) : ''); });
window.oaPlay = function(url, isHls){
  if (h) { h.destroy(); h = null; }
  a.pause(); a.removeAttribute('src'); a.load();
  send('loading');
  if (isHls && window.Hls && Hls.isSupported() && !a.canPlayType('application/vnd.apple.mpegurl')) {
    h = new Hls({ enableWorker: true });
    h.on(Hls.Events.ERROR, function(ev, d){ if (d && d.fatal) send('error', d.details || 'hls'); });
    h.loadSource(url); h.attachMedia(a);
    h.on(Hls.Events.MANIFEST_PARSED, function(){ a.play().catch(function(e){ send('error', String(e)); }); });
  } else {
    a.src = url; a.play().catch(function(e){ send('error', String(e)); });
  }
};
window.oaPause = function(){ a.pause(); };
window.oaResume = function(){ a.play().catch(function(e){ send('error', String(e)); }); };
window.oaStop = function(){ if (h) { h.destroy(); h = null; } a.pause(); a.removeAttribute('src'); a.load(); };
window.oaVolume = function(v){ a.volume = v; };
</script></body></html>""";

    if (Platform.isWindows) {
      _hostReady = Completer<void>();
      hostRequested = true;
      notifyListeners(); // [host] çizilir, web görünümü oluşunca _hostReady tamamlanır
      await _hostReady!.future.timeout(const Duration(seconds: 20));
    } else {
      _web = HeadlessInAppWebView(
        webViewEnvironment: oaWebEnv,
        initialData: _initialData,
        initialSettings: _settings,
        onWebViewCreated: _attach,
      );
      await _web!.run();
    }
    // Sayfanın yüklenmesini bekle
    for (var i = 0; i < 80; i++) {
      final ok = await _c?.evaluateJavascript(source: 'typeof window.oaPlay === "function"');
      if (ok == true) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    throw Exception('radyo sayfası yüklenmedi');
  }

  /// Windows'ta radyo sayfasını taşıyan 1×1 piksellik web görünümü; pencerenin bir köşesine konur.
  Widget host() {
    if (!hostRequested || _html == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox(
        width: 1,
        height: 1,
        child: InAppWebView(
          webViewEnvironment: oaWebEnv,
          initialData: _initialData,
          initialSettings: _settings,
          onWebViewCreated: (c) {
            _attach(c);
            if (!(_hostReady?.isCompleted ?? true)) _hostReady!.complete();
          },
        ),
      ),
    );
  }

  Future<void> play(Station s) async {
    station = s;
    state = RadioState.loading;
    error = null;
    notifyListeners();
    _prefs?.setString('radio_last', jsonEncode(s.toJson()));
    try {
      await _ensureWeb();
      await _c?.evaluateJavascript(source: 'oaVolume(${volume.clamp(0, 1)}); oaPlay(${jsonEncode(s.url)}, ${s.hls});');
    } catch (e) {
      _starting = null; // bir dahaki sefere yeniden denensin
      state = RadioState.error;
      error = 'Radyo başlatılamadı ($e)';
      notifyListeners();
    }
    // Radio Browser'ın "dinlenme" sayacına katkı (OA Radyo da yapıyor).
    if (!s.id.startsWith('http')) {
      http
          .get(Uri.parse('https://${_servers.first}/json/url/${s.id}'),
              headers: {'User-Agent': 'OATarayici/1.0'})
          .catchError((_) => http.Response('', 500));
    }
  }

  Future<void> toggle() async {
    final s = station;
    if (s == null) return;
    if (state == RadioState.playing || state == RadioState.loading) {
      await _c?.evaluateJavascript(source: 'oaPause();');
      state = RadioState.paused;
      notifyListeners();
    } else if (state == RadioState.paused && _c != null) {
      await _c?.evaluateJavascript(source: 'oaResume();');
    } else {
      await play(s);
    }
  }

  Future<void> stop() async {
    await _c?.evaluateJavascript(source: 'oaStop();');
    station = null;
    state = RadioState.idle;
    error = null;
    _prefs?.remove('radio_last');
    notifyListeners();
  }

  Future<void> setVolume(double v) async {
    volume = v;
    notifyListeners();
    await _c?.evaluateJavascript(source: 'oaVolume($v);');
  }

  Future<List<dynamic>> _api(String path, Map<String, String> params) async {
    for (final s in _servers) {
      try {
        final r = await http
            .get(Uri.https(s, path, params), headers: {'User-Agent': 'OATarayici/1.0'})
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) return jsonDecode(utf8.decode(r.bodyBytes)) as List;
      } catch (_) {}
    }
    throw Exception('İstasyon listesine ulaşılamadı. İnternet bağlantını kontrol et.');
  }

  /// Türkiye'nin en çok dinlenen istasyonları ve OA Radyo'nun ek istasyonları.
  Future<List<Station>> popular() async {
    if (_popular != null) return _popular!;
    final out = <Station>[];
    final seen = <String>{};
    try {
      final r = await http.get(Uri.parse(_extraUrl)).timeout(const Duration(seconds: 6));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        for (final m in (j['stations'] as List).whereType<Map>()) {
          final s = Station.fromJson({...m, 'hls': m['hls'] == true});
          if (s != null && seen.add(s.url)) out.add(s);
        }
      }
    } catch (_) {}
    final list = await _api('/json/stations/search', {
      'countrycode': 'TR',
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
      'limit': '80',
    });
    for (final m in list.whereType<Map>()) {
      final s = Station.fromBrowser(m);
      if (s != null && seen.add(s.url.toLowerCase())) out.add(s);
    }
    return _popular = out;
  }

  Future<List<Station>> search(String q) async {
    final list = await _api('/json/stations/search', {
      'name': q.trim(),
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
      'limit': '50',
    });
    final seen = <String>{};
    return list.whereType<Map>().map(Station.fromBrowser).whereType<Station>().where((s) => seen.add(s.url.toLowerCase())).toList();
  }
}

/// İstasyon simgesi: istasyonun ikonu, yoksa baş harf.
class StationIcon extends StatelessWidget {
  const StationIcon({super.key, required this.station, this.size = 44});
  final Station station;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: OAColors.amber, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Text(
        station.name.isEmpty ? 'R' : station.name.characters.first.toUpperCase(),
        style: oaDisplay(size * 0.42, color: OAColors.amberInk).copyWith(height: 1),
      ),
    );
    if (!station.favicon.startsWith('http')) return letter;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        child: Image.network(station.favicon,
            fit: BoxFit.contain, errorBuilder: (_, __, ___) => letter),
      ),
    );
  }
}

/// Alt çubuğun üstündeki ince radyo şeridi.
class RadioMiniBar extends StatelessWidget {
  const RadioMiniBar({super.key, required this.radio, required this.onOpen});
  final RadioPlayer radio;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: radio,
      builder: (context, _) {
        final s = radio.station;
        if (s == null) return const SizedBox.shrink();
        final sub = switch (radio.state) {
          RadioState.loading => 'Bağlanıyor…',
          RadioState.playing => 'OA Radyo · çalıyor',
          RadioState.paused => 'Duraklatıldı',
          RadioState.error => radio.error ?? 'Yayın açılamadı',
          RadioState.idle => '',
        };
        return Material(
          color: OAColors.surface2,
          child: InkWell(
            onTap: onOpen,
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: OAColors.border))),
              child: Row(
                children: [
                  StationIcon(station: s, size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: radio.state == RadioState.error ? OAColors.danger : OAColors.muted)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: radio.playing ? 'Duraklat' : 'Çal',
                    icon: radio.state == RadioState.loading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: OAColors.accent))
                        : Icon(radio.playing ? Icons.pause : Icons.play_arrow, color: OAColors.text),
                    onPressed: radio.toggle,
                  ),
                  IconButton(
                    tooltip: 'Radyoyu kapat',
                    icon: Icon(Icons.close, size: 20, color: OAColors.muted),
                    onPressed: radio.stop,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// İstasyon seçme ekranı: popüler istasyonlar, favoriler ve arama.
class RadioSheet extends StatefulWidget {
  const RadioSheet({super.key, required this.radio});
  final RadioPlayer radio;

  @override
  State<RadioSheet> createState() => _RadioSheetState();
}

class _RadioSheetState extends State<RadioSheet> {
  final _q = TextEditingController();
  bool _favs = false;
  Future<List<Station>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.radio.popular();
    _favs = widget.radio.favorites.isNotEmpty;
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _search(String v) {
    setState(() {
      _favs = false;
      _future = v.trim().isEmpty ? widget.radio.popular() : widget.radio.search(v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radio;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, scroll) => ListenableBuilder(
        listenable: r,
        builder: (context, _) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: OAColors.amber, borderRadius: BorderRadius.circular(10)),
                    child: Text('R', style: oaDisplay(17, color: OAColors.amberInk).copyWith(height: 1)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('OA Radyo', style: oaDisplay(22))),
                  if (r.active)
                    SizedBox(
                      width: 140,
                      child: Row(
                        children: [
                          Icon(Icons.volume_up, size: 18, color: OAColors.muted),
                          Expanded(
                            child: Slider(
                              value: r.volume,
                              onChanged: r.setVolume,
                              activeColor: OAColors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _q,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'İstasyon ara (ör. Kral FM, TRT)',
                  prefixIcon: const Icon(Icons.search),
                  fillColor: OAColors.surface2,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Popüler'),
                    selected: !_favs,
                    onSelected: (_) => _search(''),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('Favoriler (${r.favorites.length})'),
                    selected: _favs,
                    onSelected: (_) => setState(() => _favs = true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _favs
                  ? _list(scroll, r.favorites,
                      empty: 'Henüz favori istasyonun yok. Bir istasyonun yanındaki yıldıza dokun.')
                  : FutureBuilder<List<Station>>(
                      future: _future,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return Center(child: CircularProgressIndicator(color: OAColors.accent));
                        }
                        if (snap.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(snap.error.toString().replaceFirst('Exception: ', ''),
                                  textAlign: TextAlign.center, style: TextStyle(color: OAColors.muted)),
                            ),
                          );
                        }
                        return _list(scroll, snap.data ?? const [], empty: 'İstasyon bulunamadı.');
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(ScrollController scroll, List<Station> list, {required String empty}) {
    final r = widget.radio;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(empty, textAlign: TextAlign.center, style: TextStyle(color: OAColors.muted)),
        ),
      );
    }
    return ListView.builder(
      controller: scroll,
      itemCount: list.length,
      itemBuilder: (_, i) {
        final s = list[i];
        final current = r.station?.id == s.id;
        return ListTile(
          leading: StationIcon(station: s),
          title: Text(s.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                  color: current ? OAColors.accent : OAColors.text)),
          subtitle: s.tags.isEmpty ? null : Text(s.tags.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: IconButton(
            tooltip: r.isFavorite(s) ? 'Favorilerden çıkar' : 'Favorilere ekle',
            icon: Icon(r.isFavorite(s) ? Icons.star : Icons.star_border,
                color: r.isFavorite(s) ? OAColors.amber : OAColors.muted),
            onPressed: () => r.toggleFavorite(s),
          ),
          onTap: () => current ? r.toggle() : r.play(s),
        );
      },
    );
  }
}
