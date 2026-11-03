import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'oa_theme.dart';

// Oyun köşesi (başlangıç sayfası): Epic Games Store'da şu an ücretsiz olan ve yakında ücretsiz
// olacak oyunlar ile Steam'deki öne çıkan indirimler. Mağazaların herkese açık verileri kullanılır.

class GameDeal {
  GameDeal({
    required this.title,
    required this.url,
    required this.image,
    required this.store,
    this.note = '',
    this.price = '',
    this.oldPrice = '',
    this.discount = 0,
    this.upcoming = false,
  });

  final String title;
  final String url;
  final String image;
  final String store; // 'epic' | 'steam'
  final String note; // "13 Kas'a kadar" gibi
  final String price;
  final String oldPrice;
  final int discount;
  final bool upcoming;

  Map<String, dynamic> toJson() => {
        't': title, 'u': url, 'i': image, 's': store, 'n': note, 'p': price, 'o': oldPrice, 'd': discount, 'up': upcoming,
      };

  static GameDeal fromJson(Map m) => GameDeal(
        title: m['t']?.toString() ?? '',
        url: m['u']?.toString() ?? '',
        image: m['i']?.toString() ?? '',
        store: m['s']?.toString() ?? '',
        note: m['n']?.toString() ?? '',
        price: m['p']?.toString() ?? '',
        oldPrice: m['o']?.toString() ?? '',
        discount: (m['d'] as num?)?.toInt() ?? 0,
        upcoming: m['up'] == true,
      );
}

const _months = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
String _day(DateTime d) => '${d.toLocal().day} ${_months[d.toLocal().month - 1]}';

class GameService extends ChangeNotifier {
  SharedPreferences? _prefs;
  List<GameDeal> epic = [];
  List<GameDeal> steam = [];
  DateTime? updated;
  bool loading = false;
  Timer? _timer;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    try {
      final c = jsonDecode(prefs.getString('games_cache') ?? '{}') as Map;
      epic = [for (final m in (c['epic'] as List? ?? const []).whereType<Map>()) GameDeal.fromJson(m)];
      steam = [for (final m in (c['steam'] as List? ?? const []).whereType<Map>()) GameDeal.fromJson(m)];
      // Süresi geçmiş ücretsiz oyunlar önbellekten de düşsün diye zamanı tutulur
      final at = DateTime.tryParse(c['at']?.toString() ?? '');
      if (at != null && DateTime.now().difference(at) < const Duration(hours: 3)) updated = at;
    } catch (_) {}
    notifyListeners();
  }

  void start() {
    refresh();
    _timer ??= Timer.periodic(const Duration(hours: 3), (_) => refresh(force: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _img(List? imgs, List<String> prefer) {
    final list = (imgs ?? const []).whereType<Map>().toList();
    for (final t in prefer) {
      for (final m in list) {
        if (m['type'] == t && (m['url']?.toString() ?? '').startsWith('http')) return m['url'].toString();
      }
    }
    return list.isNotEmpty ? list.first['url']?.toString() ?? '' : '';
  }

  static Map? _offer(Map? promos, String key) {
    final outer = (promos?[key] as List?)?.whereType<Map>().toList() ?? const [];
    for (final o in outer) {
      for (final p in (o['promotionalOffers'] as List? ?? const []).whereType<Map>()) {
        final pct = (p['discountSetting'] as Map?)?['discountPercentage'];
        if (pct == 0) return p;
      }
    }
    return null;
  }

  Future<List<GameDeal>> _loadEpic() async {
    final r = await http
        .get(Uri.parse('https://store-site-backend-static.ak.epicgames.com/freeGamesPromotions?locale=tr&country=TR&allowCountries=TR'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return const [];
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final els = ((((j['data'] as Map?)?['Catalog'] as Map?)?['searchStore'] as Map?)?['elements'] as List?) ?? const [];
    final now = <GameDeal>[];
    final soon = <GameDeal>[];
    for (final e in els.whereType<Map>()) {
      final promos = e['promotions'] as Map?;
      final cur = _offer(promos, 'promotionalOffers');
      final next = _offer(promos, 'upcomingPromotionalOffers');
      if (cur == null && next == null) continue;
      String slug = e['productSlug']?.toString() ?? '';
      for (final k in ['catalogNs', 'offerMappings']) {
        if (slug.isNotEmpty && slug != '[]') break;
        final maps = k == 'catalogNs' ? ((e['catalogNs'] as Map?)?['mappings'] as List?) : (e['offerMappings'] as List?);
        final first = maps?.whereType<Map>().firstOrNull;
        slug = first?['pageSlug']?.toString() ?? '';
      }
      slug = slug.replaceAll(RegExp(r'/home$'), '');
      final url = slug.isNotEmpty ? 'https://store.epicgames.com/tr/p/$slug' : 'https://store.epicgames.com/tr/free-games';
      final image = _img(e['keyImages'] as List?, ['OfferImageWide', 'DieselStoreFrontWide', 'featuredMedia', 'Thumbnail']);
      final title = e['title']?.toString() ?? '';
      if (title.isEmpty || title.toLowerCase().contains('mystery game')) continue;
      final old = ((e['price'] as Map?)?['totalPrice'] as Map?)?['fmtPrice'] as Map?;
      if (cur != null) {
        final end = DateTime.tryParse(cur['endDate']?.toString() ?? '');
        now.add(GameDeal(
          title: title, url: url, image: image, store: 'epic',
          price: 'Ücretsiz', oldPrice: old?['originalPrice']?.toString() ?? '', discount: 100,
          note: end != null ? '${_day(end)} tarihine kadar' : '',
        ));
      } else if (next != null) {
        final start = DateTime.tryParse(next['startDate']?.toString() ?? '');
        soon.add(GameDeal(
          title: title, url: url, image: image, store: 'epic', upcoming: true,
          price: 'Yakında ücretsiz', note: start != null ? '${_day(start)} tarihinde' : '',
        ));
      }
    }
    return [...now, ...soon];
  }

  static String _money(num cents, String cur) {
    final v = cents / 100;
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    switch (cur) {
      case 'TRY':
        return '$s ₺';
      case 'USD':
        return '\$$s';
      case 'EUR':
        return '$s €';
      default:
        return '$s $cur';
    }
  }

  Future<List<GameDeal>> _loadSteam() async {
    final r = await http
        .get(Uri.parse('https://store.steampowered.com/api/featuredcategories?cc=tr&l=turkish'))
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return const [];
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
    final items = ((j['specials'] as Map?)?['items'] as List?) ?? const [];
    final seen = <String>{};
    final out = <GameDeal>[];
    for (final e in items.whereType<Map>()) {
      final id = e['id']?.toString() ?? '';
      final pct = (e['discount_percent'] as num?)?.toInt() ?? 0;
      if (id.isEmpty || pct <= 0 || !seen.add(id)) continue;
      final cur = e['currency']?.toString() ?? 'USD';
      final end = (e['discount_expiration'] as num?)?.toInt();
      out.add(GameDeal(
        title: e['name']?.toString() ?? '',
        url: 'https://store.steampowered.com/app/$id/',
        image: (e['header_image'] ?? e['large_capsule_image'] ?? '').toString(),
        store: 'steam',
        discount: pct,
        price: _money((e['final_price'] as num?) ?? 0, cur),
        oldPrice: _money((e['original_price'] as num?) ?? 0, cur),
        note: end != null ? '${_day(DateTime.fromMillisecondsSinceEpoch(end * 1000))} tarihine kadar' : '',
      ));
      if (out.length >= 12) break;
    }
    return out;
  }

  Future<void> refresh({bool force = false}) async {
    if (loading) return;
    if (!force && updated != null && DateTime.now().difference(updated!) < const Duration(hours: 3)) return;
    loading = true;
    notifyListeners();
    final results = await Future.wait([
      _loadEpic().catchError((_) => <GameDeal>[]),
      _loadSteam().catchError((_) => <GameDeal>[]),
    ]);
    if (results[0].isNotEmpty) epic = results[0];
    if (results[1].isNotEmpty) steam = results[1];
    if (results[0].isNotEmpty || results[1].isNotEmpty) {
      updated = DateTime.now();
      _prefs?.setString(
          'games_cache',
          jsonEncode({
            'at': updated!.toIso8601String(),
            'epic': [for (final g in epic) g.toJson()],
            'steam': [for (final g in steam) g.toJson()],
          }));
    }
    loading = false;
    notifyListeners();
  }
}

/// Başlangıç sayfasındaki oyun köşesi.
class GameCorner extends StatefulWidget {
  const GameCorner({super.key, required this.games, required this.onOpen, this.compact = false});
  final GameService games;
  final void Function(String url) onOpen;
  final bool compact;

  @override
  State<GameCorner> createState() => _GameCornerState();
}

class _GameCornerState extends State<GameCorner> {
  String _tab = 'epic';

  @override
  void initState() {
    super.initState();
    widget.games.start();
  }

  Widget _card(GameDeal g) {
    final w = widget.compact ? 220.0 : 250.0;
    final free = g.store == 'epic' && !g.upcoming;
    return SizedBox(
      width: w,
      child: Material(
        color: OAColors.surface.withValues(alpha: 0.85),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: OAColors.border)),
        child: InkWell(
          onTap: () => widget.onOpen(g.url),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 460 / 215,
              child: Stack(fit: StackFit.expand, children: [
                if (g.image.isNotEmpty)
                  Image.network(g.image,
                      fit: BoxFit.cover,
                      cacheWidth: 520,
                      errorBuilder: (_, __, ___) => Container(color: OAColors.bg2))
                else
                  Container(color: OAColors.bg2),
                if (g.discount > 0 || g.upcoming)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: g.upcoming ? OAColors.surface2 : (free ? OAColors.amber : OAColors.green),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        g.upcoming ? 'Yakında' : (free ? 'ÜCRETSİZ' : '-%${g.discount}'),
                        style: TextStyle(
                          color: g.upcoming ? OAColors.text : (free ? OAColors.amberInk : Colors.white),
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: OAColors.text, fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 3),
                Row(children: [
                  Text(g.price,
                      style: TextStyle(color: free ? OAColors.amber : OAColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
                  if (g.oldPrice.isNotEmpty && g.oldPrice != g.price && !g.upcoming) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(g.oldPrice,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: OAColors.faint, fontSize: 12, decoration: TextDecoration.lineThrough)),
                    ),
                  ],
                ]),
                if (g.note.isNotEmpty)
                  Text(g.note, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: OAColors.muted, fontSize: 11.5)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.games,
      builder: (context, _) {
        final epic = widget.games.epic;
        final steam = widget.games.steam;
        if (epic.isEmpty && steam.isEmpty) return const SizedBox.shrink();
        var tab = _tab;
        if (tab == 'epic' && epic.isEmpty) tab = 'steam';
        if (tab == 'steam' && steam.isEmpty) tab = 'epic';
        final list = tab == 'epic' ? epic : steam;
        Widget seg(String id, String label, int n) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: ChoiceChip(
                label: Text(label),
                selected: tab == id,
                visualDensity: VisualDensity.compact,
                onSelected: n == 0 ? null : (_) => setState(() => _tab = id),
              ),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(Icons.sports_esports_outlined, size: 20, color: OAColors.amber),
            const SizedBox(width: 8),
            Expanded(child: Text('Oyun köşesi', style: oaDisplay(widget.compact ? 18 : 20))),
            seg('epic', 'Epic ücretsiz', epic.length),
            seg('steam', 'Steam indirim', steam.length),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            height: (widget.compact ? 220.0 : 250.0) * 215 / 460 + 78,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _card(list[i]),
            ),
          ),
        ]);
      },
    );
  }
}
