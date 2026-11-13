import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'oa_theme.dart';

import 'i18n.dart';
// Başlangıç sayfasındaki döviz ve altın kartı: dolar, euro, gram altın (TL).
// Kaynak: Truncgil Finans (anlık, ücretsiz); ulaşılamazsa dolar ve euro için Avrupa Merkez Bankası
// kurları (frankfurter.dev).

class Quote {
  const Quote(this.label, this.value, this.change);
  final String label;
  final double value;
  final double? change; // yüzde
}

class MarketService extends ChangeNotifier {
  SharedPreferences? _prefs;
  List<Quote> quotes = [];
  DateTime? updated;
  bool loading = false;
  Timer? _timer;

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    try {
      final c = prefs.getString('market_cache');
      if (c != null) {
        quotes = [
          for (final m in (jsonDecode(c) as List).whereType<Map>())
            Quote(m['l'].toString(), (m['v'] as num).toDouble(), (m['c'] as num?)?.toDouble())
        ];
      }
    } catch (_) {}
    notifyListeners();
  }

  void start() {
    refresh();
    _timer ??= Timer.periodic(const Duration(minutes: 15), (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static double? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    var s = v.toString().replaceAll('%', '').replaceAll(' ', '').trim();
    // "2.950,12" ya da "34,1234" (Türkçe biçim) ya da "34.12"
    if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(s);
  }

  static dynamic _field(Map m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k)) return m[k];
    }
    return null;
  }

  Future<void> refresh() async {
    if (loading) return;
    if (updated != null && DateTime.now().difference(updated!) < const Duration(minutes: 10)) return;
    loading = true;
    notifyListeners();
    List<Quote> q = [];
    try {
      final r = await http.get(Uri.parse('https://finans.truncgil.com/today.json')).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
        for (final (key, label) in [('USD', tx('Dolar', 'Dollar')), ('EUR', 'Euro'), ('gram-altin', tx('Gram altın', 'Gold (gram)'))]) {
          final m = j[key] ?? j[key.toUpperCase()];
          if (m is! Map) continue;
          final v = _num(_field(m, ['Satış', 'Satis', 'satis', 'Selling', 'selling']));
          if (v == null) continue;
          q.add(Quote(label, v, _num(_field(m, ['Değişim', 'Degisim', 'degisim', 'Change', 'change']))));
        }
      }
    } catch (_) {}
    if (q.length < 2) {
      try {
        final r = await http
            .get(Uri.parse('https://api.frankfurter.dev/v1/latest?base=TRY&symbols=USD,EUR'))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final rates = (jsonDecode(r.body) as Map)['rates'] as Map;
          final gold = q.where((e) => e.label == tx('Gram altın', 'Gold (gram)')).toList();
          q = [
            if (rates['USD'] != null) Quote(tx('Dolar', 'Dollar'), 1 / (rates['USD'] as num).toDouble(), null),
            if (rates['EUR'] != null) Quote('Euro', 1 / (rates['EUR'] as num).toDouble(), null),
            ...gold,
          ];
        }
      } catch (_) {}
    }
    if (q.isNotEmpty) {
      quotes = q;
      updated = DateTime.now();
      _prefs?.setString(
          'market_cache', jsonEncode([for (final e in q) {'l': e.label, 'v': e.value, 'c': e.change}]));
    }
    loading = false;
    notifyListeners();
  }
}

String trMoney(double v) {
  final fixed = v >= 1000 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => L.en ? ',' : '.');
  return parts.length > 1 ? '$intPart${L.en ? '.' : ','}${parts[1]}' : intPart;
}

/// Döviz ve altın: yan yana küçük kutular.
class MarketStrip extends StatefulWidget {
  const MarketStrip({super.key, required this.market, this.alignEnd = false});
  final MarketService market;
  final bool alignEnd;

  @override
  State<MarketStrip> createState() => _MarketStripState();
}

class _MarketStripState extends State<MarketStrip> {
  @override
  void initState() {
    super.initState();
    widget.market.start();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.market,
      builder: (context, _) {
        final q = widget.market.quotes;
        if (q.isEmpty) return const SizedBox.shrink();
        return Wrap(
          alignment: widget.alignEnd ? WrapAlignment.end : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          children: [for (final e in q) _chip(e)],
        );
      },
    );
  }

  Widget _chip(Quote e) {
    final c = e.change;
    final up = (c ?? 0) > 0;
    final down = (c ?? 0) < 0;
    final color = up ? OAColors.green : (down ? OAColors.danger : OAColors.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: OAColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: OAColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(e.label, style: TextStyle(color: OAColors.muted, fontSize: 11.5)),
        const SizedBox(height: 2),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${trMoney(e.value)} ₺', style: TextStyle(color: OAColors.text, fontSize: 14, fontWeight: FontWeight.w700)),
          if (c != null) ...[
            const SizedBox(width: 6),
            Icon(up ? Icons.arrow_drop_up : (down ? Icons.arrow_drop_down : Icons.remove), size: 18, color: color),
            Text('%${c.abs().toStringAsFixed(2).replaceAll('.', ',')}', style: TextStyle(color: color, fontSize: 11.5)),
          ],
        ]),
      ]),
    );
  }
}
