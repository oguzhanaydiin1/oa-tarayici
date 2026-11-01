import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'oa_theme.dart';

// Başlangıç sayfasındaki haber akışı: seçilen sitelerin RSS beslemelerinden son haberler.

class NewsSource {
  NewsSource(this.name, this.url, {this.on = true});
  final String name;
  final String url;
  bool on;

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'on': on};
  static NewsSource? fromJson(Map j) {
    final u = j['url']?.toString() ?? '';
    if (!u.startsWith('http')) return null;
    return NewsSource(j['name']?.toString() ?? u, u, on: j['on'] != false);
  }
}

class NewsItem {
  const NewsItem(this.title, this.link, this.source, this.date, this.image);
  final String title;
  final String link;
  final String source;
  final DateTime date;
  final String? image;

  Map<String, dynamic> toJson() =>
      {'t': title, 'l': link, 's': source, 'd': date.millisecondsSinceEpoch, 'i': image};
  static NewsItem fromJson(Map j) => NewsItem(j['t'].toString(), j['l'].toString(), j['s'].toString(),
      DateTime.fromMillisecondsSinceEpoch((j['d'] as num).toInt()), j['i']?.toString());
}

List<NewsSource> _defaults() => [
      NewsSource('BBC Türkçe', 'https://feeds.bbci.co.uk/turkce/rss.xml'),
      NewsSource('NTV', 'https://www.ntv.com.tr/gundem.rss'),
      NewsSource('DW Türkçe', 'https://rss.dw.com/xml/rss-tur-all'),
      NewsSource('Webtekno', 'https://www.webtekno.com/rss.xml'),
      NewsSource('Euronews Türkçe', 'https://tr.euronews.com/rss', on: false),
      NewsSource('ShiftDelete.Net', 'https://shiftdelete.net/feed', on: false),
      NewsSource('Hürriyet', 'https://www.hurriyet.com.tr/rss/anasayfa', on: false),
    ];

class NewsService extends ChangeNotifier {
  SharedPreferences? _prefs;
  List<NewsSource> sources = _defaults();
  List<NewsItem> items = [];
  bool loading = false;
  DateTime? updated;
  Timer? _timer;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    try {
      final s = prefs.getString('news_sources');
      if (s != null) {
        final list = (jsonDecode(s) as List).whereType<Map>().map(NewsSource.fromJson).whereType<NewsSource>().toList();
        if (list.isNotEmpty) sources = list;
      }
      final c = prefs.getString('news_cache');
      if (c != null) items = (jsonDecode(c) as List).whereType<Map>().map(NewsItem.fromJson).toList();
    } catch (_) {}
    notifyListeners();
  }

  /// Başlangıç sayfası görünürken çağrılır; 20 dakikada bir yeniler.
  void start() {
    refresh();
    _timer ??= Timer.periodic(const Duration(minutes: 20), (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _saveSources() => _prefs?.setString('news_sources', jsonEncode(sources.map((e) => e.toJson()).toList()));

  void toggle(NewsSource s, bool on) {
    s.on = on;
    _saveSources();
    refresh(force: true);
  }

  void add(String name, String url) {
    sources.add(NewsSource(name.trim().isEmpty ? (Uri.tryParse(url)?.host ?? url) : name.trim(), url.trim()));
    _saveSources();
    refresh(force: true);
  }

  void remove(NewsSource s) {
    sources.remove(s);
    _saveSources();
    refresh(force: true);
  }

  Future<void> refresh({bool force = false}) async {
    if (loading) return;
    if (!force && updated != null && DateTime.now().difference(updated!) < const Duration(minutes: 15)) return;
    final on = sources.where((s) => s.on).toList();
    if (on.isEmpty) {
      items = [];
      notifyListeners();
      return;
    }
    loading = true;
    notifyListeners();
    final results = await Future.wait(on.map(_fetch));
    final all = <NewsItem>[for (final r in results) ...r];
    final seen = <String>{};
    all.sort((a, b) => b.date.compareTo(a.date));
    final now = DateTime.now().add(const Duration(minutes: 5));
    items = [
      for (final i in all)
        if (!i.date.isAfter(now) && seen.add(i.link)) i
    ].take(80).toList();
    if (items.isNotEmpty) _prefs?.setString('news_cache', jsonEncode(items.map((e) => e.toJson()).toList()));
    updated = DateTime.now();
    loading = false;
    notifyListeners();
  }

  Future<List<NewsItem>> _fetch(NewsSource s) async {
    try {
      final r = await http.get(Uri.parse(s.url), headers: {'User-Agent': 'Mozilla/5.0 OATarayici'}).timeout(
            const Duration(seconds: 10),
          );
      if (r.statusCode != 200) return [];
      return parseFeed(utf8.decode(r.bodyBytes, allowMalformed: true), s.name);
    } catch (_) {
      return [];
    }
  }
}

String _clean(String s) => s
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

DateTime? _date(String? s) {
  if (s == null || s.trim().isEmpty) return null;
  final t = s.trim();
  final iso = DateTime.tryParse(t);
  if (iso != null) return iso.toLocal();
  // RFC 822: "Sun, 01 Nov 2026 05:12:00 +0300"
  final m = RegExp(r'(\d{1,2})\s+(\w{3})\w*\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|GMT|UTC|Z|[A-Z]{3})?')
      .firstMatch(t);
  if (m == null) return null;
  const mons = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  final mon = mons.indexOf(m.group(2)!.toLowerCase()) + 1;
  if (mon == 0) return null;
  var d = DateTime.utc(int.parse(m.group(3)!), mon, int.parse(m.group(1)!), int.parse(m.group(4)!),
      int.parse(m.group(5)!), int.tryParse(m.group(6) ?? '0') ?? 0);
  final z = m.group(7);
  if (z != null && (z.startsWith('+') || z.startsWith('-'))) {
    final sign = z.startsWith('-') ? -1 : 1;
    final off = Duration(hours: int.parse(z.substring(1, 3)), minutes: int.parse(z.substring(3, 5)));
    d = sign > 0 ? d.subtract(off) : d.add(off);
  }
  return d.toLocal();
}

XmlElement? _child(XmlElement e, String qname) {
  for (final c in e.childElements) {
    if (c.name.qualified == qname) return c;
  }
  return null;
}

String? _imageOf(XmlElement e) {
  for (final el in e.descendantElements) {
    final n = el.name.local;
    if ((n == 'content' || n == 'thumbnail') && el.name.prefix == 'media') {
      final u = el.getAttribute('url');
      if (u != null && u.startsWith('http')) return u;
    }
    if (n == 'enclosure') {
      final u = el.getAttribute('url');
      final t = el.getAttribute('type') ?? 'image';
      if (u != null && t.startsWith('image')) return u;
    }
  }
  final html = [
    _child(e, 'description')?.innerText,
    _child(e, 'content:encoded')?.innerText,
    _child(e, 'content')?.innerText,
  ].whereType<String>().join(' ');
  final m = RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false).firstMatch(html);
  final u = m?.group(1);
  return u != null && u.startsWith('http') ? u : null;
}

List<NewsItem> parseFeed(String xml, String source) {
  final out = <NewsItem>[];
  final doc = XmlDocument.parse(xml);
  final entries = [
    ...doc.findAllElements('item'),
    ...doc.findAllElements('entry'),
  ];
  for (final e in entries.take(30)) {
    final title = _clean(_child(e, 'title')?.innerText ?? '');
    String link = (_child(e, 'link')?.innerText ?? '').trim();
    if (link.isEmpty) {
      final l = e.findElements('link').firstWhere(
            (x) => (x.getAttribute('rel') ?? 'alternate') == 'alternate',
            orElse: () => XmlElement(XmlName('x')),
          );
      link = l.getAttribute('href') ?? '';
    }
    if (title.isEmpty || !link.startsWith('http')) continue;
    final date = _date(_child(e, 'pubDate')?.innerText) ??
        _date(_child(e, 'dc:date')?.innerText) ??
        _date(_child(e, 'published')?.innerText) ??
        _date(_child(e, 'updated')?.innerText) ??
        DateTime.now().subtract(const Duration(hours: 12));
    out.add(NewsItem(title, link, source, date, _imageOf(e)));
  }
  return out;
}

String _ago(DateTime d) {
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'şimdi';
  if (m < 60) return '$m dk önce';
  final h = m ~/ 60;
  if (h < 24) return '$h sa önce';
  return '${h ~/ 24} gün önce';
}

/// Başlangıç sayfasındaki haber listesi.
class NewsFeed extends StatefulWidget {
  const NewsFeed({super.key, required this.news, required this.onOpen, this.compact = false});
  final NewsService news;
  final void Function(String url) onOpen;
  final bool compact;

  @override
  State<NewsFeed> createState() => _NewsFeedState();
}

class _NewsFeedState extends State<NewsFeed> {
  int _show = 10;

  @override
  void initState() {
    super.initState();
    widget.news.start();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.news,
      builder: (context, _) {
        final n = widget.news;
        final list = n.items.take(_show).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text('Haberler', style: oaDisplay(22))),
              if (n.loading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              TextButton.icon(
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Kaynaklar'),
                onPressed: () => showNewsSources(context, n),
              ),
            ]),
            const SizedBox(height: 8),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  n.loading
                      ? 'Haberler yükleniyor…'
                      : n.sources.any((s) => s.on)
                          ? 'Haberler alınamadı. İnternet bağlantını kontrol et.'
                          : 'Kaynak seçilmedi. "Kaynaklar"dan haber sitelerini seç.',
                  style: TextStyle(color: OAColors.muted),
                ),
              ),
            for (final it in list) _card(it),
            if (n.items.length > _show)
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _show += 10),
                  child: const Text('Daha fazla haber'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _card(NewsItem it) {
    final img = it.image;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: OAColors.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => widget.onOpen(it.link),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: OAColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (img != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      img,
                      width: widget.compact ? 92 : 120,
                      height: widget.compact ? 68 : 78,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: widget.compact ? 92 : 120,
                        height: widget.compact ? 68 : 78,
                        color: OAColors.surface2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: OAColors.text, fontSize: 15, fontWeight: FontWeight.w600, height: 1.3)),
                      const SizedBox(height: 6),
                      Text('${it.source} · ${_ago(it.date)}', style: TextStyle(color: OAColors.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showNewsSources(BuildContext context, NewsService n) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('Haber kaynakları', style: oaDisplay(22)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Başlangıç sayfasında hangi sitelerin haberleri görünsün?',
                  style: TextStyle(color: OAColors.muted)),
            ),
            for (final s in n.sources)
              SwitchListTile(
                value: s.on,
                activeThumbColor: OAColors.amberInk,
                activeTrackColor: OAColors.amber,
                title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(Uri.tryParse(s.url)?.host ?? s.url),
                secondary: _defaults().any((d) => d.url == s.url)
                    ? null
                    : IconButton(
                        tooltip: 'Kaldır',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          n.remove(s);
                          setS(() {});
                        },
                      ),
                onChanged: (v) {
                  n.toggle(s, v);
                  setS(() {});
                },
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('RSS adresiyle kaynak ekle'),
              onTap: () async {
                final name = TextEditingController();
                final url = TextEditingController();
                final ok = await showDialog<bool>(
                  context: ctx,
                  builder: (d) => AlertDialog(
                    title: const Text('Kaynak ekle'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(controller: name, decoration: const InputDecoration(labelText: 'Adı (isteğe bağlı)')),
                      const SizedBox(height: 10),
                      TextField(
                        controller: url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'RSS adresi', hintText: 'https://site.com/rss'),
                      ),
                    ]),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Ekle')),
                    ],
                  ),
                );
                final u = url.text.trim();
                if (ok == true && u.startsWith('http')) {
                  n.add(name.text, u);
                  setS(() {});
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}
