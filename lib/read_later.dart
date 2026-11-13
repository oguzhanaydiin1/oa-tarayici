import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'oa_theme.dart';

import 'i18n.dart';
// Sonra oku: sayfanın yazısı (Mozilla Readability ile ayıklanır) resimleriyle birlikte cihaza
// kaydedilir; internet yokken de okunur.

class SavedArticle {
  SavedArticle({required this.id, required this.title, required this.url, required this.saved, this.read = false, this.minutes = 1});
  final String id;
  final String title;
  final String url;
  final DateTime saved;
  bool read;
  final int minutes;

  String get host => Uri.tryParse(url)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? url;

  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'url': url, 'saved': saved.millisecondsSinceEpoch, 'read': read, 'min': minutes};
  static SavedArticle fromJson(Map j) => SavedArticle(
        id: j['id'].toString(),
        title: j['title'].toString(),
        url: j['url'].toString(),
        saved: DateTime.fromMillisecondsSinceEpoch((j['saved'] as num).toInt()),
        read: j['read'] == true,
        minutes: (j['min'] as num?)?.toInt() ?? 1,
      );
}

enum SaveResult { saved, already, notArticle, failed }

class ReadingList extends ChangeNotifier {
  SharedPreferences? _prefs;
  List<SavedArticle> items = [];
  static String? _readability;

  int get unread => items.where((e) => !e.read).length;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    try {
      items = (jsonDecode(prefs.getString('read_later') ?? '[]') as List).whereType<Map>().map(SavedArticle.fromJson).toList();
    } catch (_) {}
    notifyListeners();
  }

  void _persist() {
    _prefs?.setString('read_later', jsonEncode(items.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<Directory> _dir() async {
    final d = Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}okuma');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> _file(String id) async => File('${(await _dir()).path}${Platform.pathSeparator}$id.html');

  bool has(String url) => items.any((e) => e.url == url);

  Future<SaveResult> save(InAppWebViewController c, String url) async {
    if (has(url)) return SaveResult.already;
    try {
      _readability ??= await rootBundle.loadString('assets/readability.js');
      final ready = await c.evaluateJavascript(source: 'typeof Readability === "function"');
      if (ready != true) await c.evaluateJavascript(source: _readability!);
      final r = await c.evaluateJavascript(source: '''
(function(){
  try {
    var a = new Readability(document.cloneNode(true), { charThreshold: 300 }).parse();
    if (!a || !a.content || (a.textContent || '').trim().length < 300) return null;
    return JSON.stringify({ title: a.title || document.title, content: a.content, byline: a.byline || '',
      site: a.siteName || '', words: (a.textContent || '').split(/\\s+/).length });
  } catch (e) { return null; }
})()
''');
      if (r == null) return SaveResult.notArticle;
      final j = jsonDecode(r.toString()) as Map;
      var content = j['content'].toString();
      content = await _inlineImages(content);
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final minutes = ((j['words'] as num?)?.toInt() ?? 200) ~/ 220;
      final art = SavedArticle(
        id: id,
        title: j['title'].toString(),
        url: url,
        saved: DateTime.now(),
        minutes: minutes < 1 ? 1 : minutes,
      );
      final html = _page(art, j['byline'].toString(), j['site'].toString(), content);
      await (await _file(id)).writeAsString(html);
      items.insert(0, art);
      _persist();
      return SaveResult.saved;
    } catch (_) {
      return SaveResult.failed;
    }
  }

  /// Resimler internetsiz de görünsün diye sayfanın içine gömülür (en çok 20 resim).
  Future<String> _inlineImages(String html) async {
    final re = RegExp(r'''<img([^>]*?)\ssrc=["']([^"']+)["']([^>]*)>''', caseSensitive: false);
    final matches = re.allMatches(html).take(20).toList();
    final map = <String, String>{};
    await Future.wait(matches.map((m) async {
      final src = m.group(2)!.replaceAll('&amp;', '&');
      if (!src.startsWith('http') || map.containsKey(src)) return;
      try {
        final r = await http.get(Uri.parse(src)).timeout(const Duration(seconds: 8));
        final type = r.headers['content-type'] ?? 'image/jpeg';
        if (r.statusCode == 200 && type.startsWith('image') && r.bodyBytes.length < 1500000) {
          map[src] = 'data:${type.split(';').first};base64,${base64Encode(r.bodyBytes)}';
        }
      } catch (_) {}
    }));
    return html.replaceAllMapped(re, (m) {
      final src = m.group(2)!.replaceAll('&amp;', '&');
      final data = map[src];
      final attrs = '${m.group(1)}${m.group(3)}'.replaceAll(RegExp(r'''\s(srcset|sizes|loading)=["'][^"']*["']''', caseSensitive: false), '');
      return '<img$attrs src="${data ?? m.group(2)}">';
    });
  }

  String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  String _page(SavedArticle a, String byline, String site, String content) {
    final p = OAColors.palette;
    String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final by = [byline, site].where((e) => e.trim().isNotEmpty).join(' · ');
    return '''<!doctype html><html lang="${L.code}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_esc(a.title)}</title>
<style>
body{margin:0;background:${hex(p.bg)};color:${hex(p.text)};font:400 19px/1.7 "DM Sans","Segoe UI",Roboto,system-ui,sans-serif;-webkit-font-smoothing:antialiased}
.bar{position:sticky;top:0;padding:10px 16px;background:${hex(p.surface)};border-bottom:1px solid ${hex(p.border)};font-size:14px;color:${hex(p.muted)};white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bar a{color:${hex(p.accent)}}
article{max-width:680px;margin:0 auto;padding:32px 20px 80px}
h1.t{font:800 clamp(28px,5vw,40px)/1.1 "Bricolage Grotesque","Segoe UI",sans-serif;letter-spacing:-.02em;margin:0 0 12px}
.by{color:${hex(p.muted)};font-size:15px;margin:0 0 28px}
p,li{margin:0 0 1em}
h2,h3{font-weight:800;line-height:1.2;margin:1.6em 0 .6em}
a{color:${hex(p.accent)}}
img,video,figure{max-width:100%;height:auto;border-radius:12px}
figcaption{color:${hex(p.muted)};font-size:14px}
blockquote{margin:1em 0;padding:4px 0 4px 18px;border-left:3px solid ${hex(p.accent)};color:${hex(p.muted)}}
pre,code{font-family:ui-monospace,Consolas,monospace;font-size:.85em;background:${hex(p.surface)};border-radius:6px}
pre{padding:12px;overflow:auto}
table{border-collapse:collapse;display:block;overflow:auto}
td,th{border:1px solid ${hex(p.border)};padding:6px 10px}
</style></head><body>
<div class="bar">Sonra oku · kaydedildi · <a href="${_esc(a.url)}">${_esc(a.host)}</a></div>
<article><h1 class="t">${_esc(a.title)}</h1><p class="by">${_esc(by.isEmpty ? a.host : by)} · ${a.minutes} dk okuma</p>
$content
</article></body></html>''';
  }

  Future<String?> html(SavedArticle a) async {
    try {
      final f = await _file(a.id);
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  void markRead(SavedArticle a, [bool v = true]) {
    a.read = v;
    _persist();
  }

  Future<void> remove(SavedArticle a) async {
    items.remove(a);
    _persist();
    try {
      final f = await _file(a.id);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

String _date(DateTime d) {
  final m = [tx('Oca', 'Jan'), tx('Şub', 'Feb'), tx('Mar', 'Mar'), tx('Nis', 'Apr'), tx('May', 'May'), tx('Haz', 'Jun'), tx('Tem', 'Jul'), tx('Ağu', 'Aug'), tx('Eyl', 'Sep'), tx('Eki', 'Oct'), tx('Kas', 'Nov'), tx('Ara', 'Dec')];
  return '${d.day} ${m[d.month - 1]}';
}

/// Okuma listesi.
class ReadingListSheet extends StatelessWidget {
  const ReadingListSheet({super.key, required this.list, required this.onOpen});
  final ReadingList list;
  final void Function(SavedArticle a) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: list,
      builder: (context, _) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(children: [
                Icon(Icons.bookmark_added_outlined, color: OAColors.amber),
                const SizedBox(width: 10),
                Expanded(child: Text(tx('Okuma listesi', 'Reading list'), style: oaDisplay(22))),
                Text(tx('${list.unread} okunmadı', '${list.unread} unread'), style: TextStyle(color: OAColors.muted)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(tx('Kaydettiğin yazılar resimleriyle birlikte cihazında; internetsiz de okunur.', 'Saved articles are kept on your device with their images and can be read offline.'),
                  style: TextStyle(color: OAColors.muted, fontSize: 13)),
            ),
            if (list.items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(tx('Liste boş. Bir yazıyı okurken menüden "Sonra oku"ya dokun.', 'The list is empty. While reading an article, tap "Read later" in the menu.'),
                    textAlign: TextAlign.center, style: TextStyle(color: OAColors.muted)),
              ),
            for (final a in list.items)
              ListTile(
                leading: Icon(a.read ? Icons.drafts_outlined : Icons.article_outlined,
                    color: a.read ? OAColors.faint : OAColors.amber),
                title: Text(a.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: a.read ? OAColors.muted : OAColors.text, fontWeight: FontWeight.w600)),
                subtitle: Text(tx('${a.host} · ${a.minutes} dk · ${_date(a.saved)}', '${a.host} · ${a.minutes} min · ${_date(a.saved)}')),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'read') list.markRead(a, !a.read);
                    if (v == 'del') list.remove(a);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'read', child: Text(a.read ? tx('Okunmadı yap', 'Mark as unread') : tx('Okundu yap', 'Mark as read'))),
                     PopupMenuItem(value: 'del', child: Text(tx('Sil', 'Delete'))),
                  ],
                ),
                onTap: () {
                  Navigator.pop(context);
                  onOpen(a);
                },
              ),
          ],
        ),
      ),
    );
  }
}
