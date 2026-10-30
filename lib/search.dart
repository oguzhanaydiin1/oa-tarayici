import 'dart:convert';

import 'package:http/http.dart' as http;

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

  String searchUrl(String query) =>
      searchTemplate.replaceAll('%s', Uri.encodeQueryComponent(query));
}

const kEngines = <SearchEngine>[
  SearchEngine(
    id: 'ddg',
    name: 'DuckDuckGo',
    note: 'Seni takip etmez · önerilen',
    homeUrl: 'https://duckduckgo.com/?kae=d',
    searchTemplate: 'https://duckduckgo.com/?kae=d&q=%s',
    suggestTemplate: 'https://duckduckgo.com/ac/?type=list&q=%s',
  ),
  SearchEngine(
    id: 'google',
    name: 'Google',
    note: 'En geniş sonuçlar',
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
    note: 'Türkçe sonuçlarda güçlü',
    homeUrl: 'https://yandex.com.tr/',
    searchTemplate: 'https://yandex.com.tr/search/?text=%s',
    suggestTemplate: 'https://suggest.yandex.com.tr/suggest-ff.cgi?uil=tr&part=%s',
  ),
  SearchEngine(
    id: 'brave',
    name: 'Brave Search',
    note: 'Kendi dizini, takip etmez',
    homeUrl: 'https://search.brave.com/',
    searchTemplate: 'https://search.brave.com/search?q=%s',
    suggestTemplate: 'https://search.brave.com/api/suggest?q=%s',
  ),
  SearchEngine(
    id: 'ecosia',
    name: 'Ecosia',
    note: 'Geliriyle ağaç diker · öneriler DuckDuckGo\'dan',
    homeUrl: 'https://www.ecosia.org/',
    searchTemplate: 'https://www.ecosia.org/search?q=%s',
  ),
  SearchEngine(
    id: 'startpage',
    name: 'Startpage',
    note: 'Google sonuçları, kimliksiz · öneriler DuckDuckGo\'dan',
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
