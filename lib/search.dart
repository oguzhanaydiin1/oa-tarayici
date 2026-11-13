import 'dart:convert';

import 'package:http/http.dart' as http;

import 'i18n.dart';
/// Bir arama motoru: kullanıcının yazdığı, motorun arama adresine eklenir.
class SearchEngine {
  const SearchEngine({
    required this.id,
    required this.name,
    required this.note,
    required this.homeUrl,
    required this.searchTemplate,
    this.suggestTemplate,
  });

  final String id;
  final String name;
  final String note;
  final String homeUrl;

  /// `%s` yerine aranan metin (URL kodlanmış) gelir.
  final String searchTemplate;

  /// OpenSearch biçiminde öneri döndüren adres: `["sorgu", ["öneri1", "öneri2", ...]]`.
  /// null ise öneriler DuckDuckGo'dan alınır.
  final String? suggestTemplate;

  /// `%k`: DuckDuckGo'nun tema parametresi; uygulama koyu temadaysa sonuçlar da koyu açılır.
  String searchUrl(String query, {bool dark = true}) => searchTemplate
      .replaceAll('%k', dark ? 'd' : '-1')
      .replaceAll('%s', Uri.encodeQueryComponent(query));

  String home({bool dark = true}) => homeUrl.replaceAll('%k', dark ? 'd' : '-1');
}

final kEngines = <SearchEngine>[
  SearchEngine(
    id: 'ddg',
    name: 'DuckDuckGo',
    note: tx('Seni takip etmez · önerilen', "Doesn't track you · recommended"),
    homeUrl: 'https://duckduckgo.com/?kae=%k',
    searchTemplate: 'https://duckduckgo.com/?kae=%k&q=%s',
    suggestTemplate: 'https://duckduckgo.com/ac/?type=list&q=%s',
  ),
  SearchEngine(
    id: 'google',
    name: 'Google',
    note: tx('En geniş sonuçlar', 'Broadest results'),
    homeUrl: 'https://www.google.com/',
    searchTemplate: 'https://www.google.com/search?q=%s',
    suggestTemplate:
        'https://suggestqueries.google.com/complete/search?client=firefox&hl=tr&ie=utf-8&oe=utf-8&q=%s',
  ),
  SearchEngine(
    id: 'bing',
    name: 'Bing',
    note: 'Microsoft',
    homeUrl: 'https://www.bing.com/',
    searchTemplate: 'https://www.bing.com/search?q=%s',
    suggestTemplate: 'https://api.bing.com/osjson.aspx?query=%s',
  ),
  SearchEngine(
    id: 'yandex',
    name: 'Yandex',
    note: tx('Türkçe sonuçlarda güçlü', 'Strong for Turkish results'),
    homeUrl: 'https://yandex.com.tr/',
    searchTemplate: 'https://yandex.com.tr/search/?text=%s',
    suggestTemplate: 'https://suggest.yandex.com.tr/suggest-ff.cgi?uil=tr&part=%s',
  ),
  SearchEngine(
    id: 'brave',
    name: 'Brave Search',
    note: tx('Kendi dizini, takip etmez', "Its own index, doesn't track you"),
    homeUrl: 'https://search.brave.com/',
    searchTemplate: 'https://search.brave.com/search?q=%s',
    suggestTemplate: 'https://search.brave.com/api/suggest?q=%s',
  ),
  SearchEngine(
    id: 'ecosia',
    name: 'Ecosia',
    note: tx('Geliriyle ağaç diker · öneriler DuckDuckGo\'dan', 'Plants trees with its income · suggestions from DuckDuckGo'),
    homeUrl: 'https://www.ecosia.org/',
    searchTemplate: 'https://www.ecosia.org/search?q=%s',
  ),
  SearchEngine(
    id: 'startpage',
    name: 'Startpage',
    note: tx('Google sonuçları, kimliksiz · öneriler DuckDuckGo\'dan', 'Google results, anonymously · suggestions from DuckDuckGo'),
    homeUrl: 'https://www.startpage.com/',
    searchTemplate: 'https://www.startpage.com/sp/search?query=%s',
  ),
];

SearchEngine engineById(String? id) =>
    kEngines.firstWhere((e) => e.id == id, orElse: () => kEngines.first);

/// Seçilen motordan canlı öneri ister. Hata olursa boş liste döner;
/// öneri gelmemesi tarayıcıyı hiçbir zaman bozmamalı.
///
/// Not: Bu öneri adresleri motorların tarayıcılar için açık tuttuğu, ama resmî
/// olarak belgelenmemiş adresler. Değişirlerse yalnız bu dosya güncellenir.
Future<List<String>> fetchSuggestions(SearchEngine engine, String query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final template = engine.suggestTemplate ?? kEngines.first.suggestTemplate!;
  final uri = Uri.parse(template.replaceAll('%s', Uri.encodeQueryComponent(q)));
  try {
    final res = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 3));
    if (res.statusCode != 200) return const [];
    final data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    if (data is List && data.length > 1 && data[1] is List) {
      return (data[1] as List)
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty && s.toLowerCase() != q.toLowerCase())
          .take(6)
          .toList();
    }
  } catch (_) {
    // Ağ yok, zaman aşımı ya da beklenmeyen biçim: öneri göstermeyiz.
  }
  return const [];
}

enum SuggestionKind { go, search, remote, pastSearch, page, bookmark }

class Suggestion {
  const Suggestion(this.kind, this.value, this.label, {this.url});
  final SuggestionKind kind;

  /// Seçilince gidilecek değer: arama metni ya da adres.
  final String value;
  final String label;
  final String? url;

  bool get isSearch =>
      kind == SuggestionKind.search ||
      kind == SuggestionKind.remote ||
      kind == SuggestionKind.pastSearch;
}

/// Adres çubuğuna yazılan bir URL'ye mi benziyor?
bool looksLikeUrl(String text) {
  final s = text.trim();
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(s)) return true;
  if (s.contains(' ')) return false;
  return RegExp(r'^[^.\s]+\.[^\s]{2,}').hasMatch(s) || s.startsWith('localhost');
}
