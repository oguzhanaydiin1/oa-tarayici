import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'i18n.dart';
/// Adres çubuğunda yazarken çıkan hızlı cevap ("125*18 = 2.250", "100 dolar = 4.300 TL").
class SmartAnswer {
  const SmartAnswer(this.text, this.source, {this.copy});

  /// Gösterilen cevap, ör. "= 2.250" ya da "100 USD = 4.312,50 TL".
  final String text;

  /// Sağda küçük yazı: "Hesap makinesi", "Birim çevirisi", "Döviz · ECB 30.10.2026".
  final String source;

  /// Dokununca panoya kopyalanacak değer (yalnız sayı).
  final String? copy;
}

/// Sayıyı Türkçe biçimde yazar: 1234.5 → "1.234,5"
String formatTr(double v, {int maxDecimals = 6}) {
  if (v.isNaN || v.isInfinite) return v.toString();
  final neg = v < 0;
  v = v.abs();
  var s = v.toStringAsFixed(maxDecimals);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '${neg ? '-' : ''}$intPart${parts.length > 1 ? ',${parts[1]}' : ''}';
}

/// "1,5" ve "1.5" ikisini de sayı olarak okur; binlik ayıracı "1.000" de olabilir.
double? _num(String s) {
  s = s.trim();
  if (RegExp(r'^\d{1,3}(\.\d{3})+(,\d+)?$').hasMatch(s)) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else {
    s = s.replaceAll(',', '.');
  }
  return double.tryParse(s);
}

// ------------------------------------------------------------------ Hesap makinesi

/// Güvenli, küçük bir aritmetik ayrıştırıcı: + - * / ^ % ve parantez.
class _Calc {
  _Calc(this.src);
  final String src;
  int i = 0;

  static double? eval(String input) {
    var s = input
        .replaceAll('×', '*')
        .replaceAll('x', '*')
        .replaceAll('X', '*')
        .replaceAll('÷', '/')
        .replaceAll(':', '/')
        .replaceAll(' ', '');
    s = s.replaceAll(RegExp(r'=$'), '');
    if (s.isEmpty) return null;
    // Türkçe ondalık: "1,5+2" → "1.5+2"
    s = s.replaceAll(',', '.');
    final c = _Calc(s);
    try {
      final v = c._expr();
      if (c.i != s.length) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  String? get _peek => i < src.length ? src[i] : null;

  double _expr() {
    var v = _term();
    while (_peek == '+' || _peek == '-') {
      final op = src[i++];
      final r = _term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double _term() {
    var v = _power();
    while (_peek == '*' || _peek == '/' || _peek == '%') {
      final op = src[i++];
      if (op == '%' && (_peek == null || !RegExp(r'[\d(.]').hasMatch(_peek!))) {
        v = v / 100; // "50%" → 0,5
        continue;
      }
      final r = _power();
      v = op == '*' ? v * r : op == '/' ? v / r : v % r;
    }
    return v;
  }

  double _power() {
    final b = _unary();
    if (_peek == '^') {
      i++;
      return math.pow(b, _power()).toDouble();
    }
    return b;
  }

  double _unary() {
    if (_peek == '-') {
      i++;
      return -_unary();
    }
    if (_peek == '+') {
      i++;
      return _unary();
    }
    return _atom();
  }

  double _atom() {
    if (_peek == '(') {
      i++;
      final v = _expr();
      if (_peek != ')') throw const FormatException();
      i++;
      return v;
    }
    final start = i;
    while (_peek != null && RegExp(r'[\d.]').hasMatch(_peek!)) {
      i++;
    }
    if (start == i) throw const FormatException();
    return double.parse(src.substring(start, i));
  }
}

SmartAnswer? _calculator(String q) {
  final s = q.trim();
  // En az bir işlem ve yalnız izin verilen karakterler; tek başına sayı ya da tarih değil.
  if (!RegExp(r'^[\d\s.,+\-*/x×÷:^%()=]+$').hasMatch(s)) return null;
  if (!RegExp(r'\d\s*[+\-*/x×÷:^%]\s*[\d(]|\d\s*%').hasMatch(s)) return null;
  if (RegExp(r'^\d{1,2}[./-]\d{1,2}[./-]\d{2,4}$').hasMatch(s)) return null; // 30.10.2026
  // Telefon numarası ya da tarih gibi yalnız tire ve rakam: 0532-123-45-67, 2026-10-30
  if (RegExp(r'^[\d\s-]+$').hasMatch(s) && s.replaceAll(RegExp(r'\D'), '').length >= 7) {
    return null;
  }
  final v = _Calc.eval(s);
  if (v == null || v.isNaN || v.isInfinite) return null;
  final text = formatTr(v, maxDecimals: 8);
  return SmartAnswer('= $text', tx('Hesap makinesi', 'Calculator'), copy: text);
}

// ------------------------------------------------------------------ Birim çevirisi

class _Unit {
  const _Unit(this.name, this.kind, this.toBase, {this.offset = 0});
  final String name; // gösterilen kısa ad
  final String kind; // uzunluk, ağırlık, sıcaklık, hacim
  final double toBase;
  final double offset;
}

const _units = <String, _Unit>{
  'km': _Unit('km', 'uzunluk', 1000),
  'kilometre': _Unit('km', 'uzunluk', 1000),
  'm': _Unit('m', 'uzunluk', 1),
  'metre': _Unit('m', 'uzunluk', 1),
  'cm': _Unit('cm', 'uzunluk', 0.01),
  'santim': _Unit('cm', 'uzunluk', 0.01),
  'mm': _Unit('mm', 'uzunluk', 0.001),
  'mil': _Unit('mil', 'uzunluk', 1609.344),
  'mile': _Unit('mil', 'uzunluk', 1609.344),
  'mi': _Unit('mil', 'uzunluk', 1609.344),
  'inç': _Unit(tx('inç', 'in'), 'uzunluk', 0.0254),
  'inc': _Unit(tx('inç', 'in'), 'uzunluk', 0.0254),
  'inch': _Unit(tx('inç', 'in'), 'uzunluk', 0.0254),
  'in': _Unit(tx('inç', 'in'), 'uzunluk', 0.0254),
  'ft': _Unit('ft', 'uzunluk', 0.3048),
  'feet': _Unit('ft', 'uzunluk', 0.3048),
  'fit': _Unit('ft', 'uzunluk', 0.3048),
  'kg': _Unit('kg', 'ağırlık', 1),
  'kilo': _Unit('kg', 'ağırlık', 1),
  'g': _Unit('g', 'ağırlık', 0.001),
  'gr': _Unit('g', 'ağırlık', 0.001),
  'gram': _Unit('g', 'ağırlık', 0.001),
  'lb': _Unit('lb', 'ağırlık', 0.45359237),
  'lbs': _Unit('lb', 'ağırlık', 0.45359237),
  'libre': _Unit('lb', 'ağırlık', 0.45359237),
  'pound': _Unit('lb', 'ağırlık', 0.45359237),
  'oz': _Unit('oz', 'ağırlık', 0.028349523125),
  'ons': _Unit('oz', 'ağırlık', 0.028349523125),
  'c': _Unit('°C', 'sıcaklık', 1),
  '°c': _Unit('°C', 'sıcaklık', 1),
  'derece': _Unit('°C', 'sıcaklık', 1),
  'f': _Unit('°F', 'sıcaklık', 5 / 9, offset: -32),
  '°f': _Unit('°F', 'sıcaklık', 5 / 9, offset: -32),
  'fahrenheit': _Unit('°F', 'sıcaklık', 5 / 9, offset: -32),
  'l': _Unit('L', 'hacim', 1),
  'lt': _Unit('L', 'hacim', 1),
  'litre': _Unit('L', 'hacim', 1),
  'ml': _Unit('mL', 'hacim', 0.001),
  'galon': _Unit('galon', 'hacim', 3.785411784),
  'gal': _Unit('galon', 'hacim', 3.785411784),
};

/// Hedef verilmezse en yaygın karşılık.
const _defaultTarget = <String, String>{
  'km': 'mil', 'mil': 'km', 'm': 'ft', 'ft': 'm', 'cm': 'inç', 'inç': 'cm', 'mm': 'inç',
  'kg': 'lb', 'lb': 'kg', 'g': 'oz', 'oz': 'g', '°C': '°F', '°F': '°C',
  'L': 'galon', 'galon': 'L', 'mL': 'oz',
};

double _convert(double v, _Unit from, _Unit to) {
  if (from.kind == 'sıcaklık') {
    final c = from.name == '°F' ? (v - 32) * 5 / 9 : v;
    return to.name == '°F' ? c * 9 / 5 + 32 : c;
  }
  return v * from.toBase / to.toBase;
}

_Unit? _unitByName(String n) {
  for (final u in _units.values) {
    if (u.name == n) return u;
  }
  return null;
}

final _unitRe = RegExp(
    r'^(-?\d+(?:[.,]\d+)?)\s*([a-zçğıöşü°]+)\s*(?:(?:kaç|kac|to|in|=|->|→|ne kadar|nedir)\s*([a-zçğıöşü°]+)?\s*(?:eder|yapar)?)?\s*\??$');

SmartAnswer? _unitConvert(String q) {
  final m = _unitRe.firstMatch(q.trim().toLowerCase());
  if (m == null) return null;
  final v = _num(m.group(1)!);
  final from = _units[m.group(2)!];
  if (v == null || from == null) return null;
  _Unit? to = m.group(3) != null ? _units[m.group(3)!] : null;
  to ??= _unitByName(_defaultTarget[from.name] ?? '');
  if (to == null || to.kind != from.kind || to.name == from.name) return null;
  final r = _convert(v, from, to);
  final text = formatTr(r, maxDecimals: r.abs() < 10 ? 3 : 2);
  return SmartAnswer('${formatTr(v)} ${from.name} = $text ${to.name}', tx('Birim çevirisi', 'Unit conversion'), copy: text);
}

// ------------------------------------------------------------------ Döviz

const _currencyNames = <String, String>{
  'tl': 'TRY', 'try': 'TRY', 'lira': 'TRY', '₺': 'TRY', 'türk lirası': 'TRY',
  'dolar': 'USD', 'usd': 'USD', r'$': 'USD', 'amerikan doları': 'USD',
  'euro': 'EUR', 'eur': 'EUR', 'avro': 'EUR', '€': 'EUR', 'öro': 'EUR',
  'sterlin': 'GBP', 'gbp': 'GBP', '£': 'GBP', 'ingiliz sterlini': 'GBP',
  'frank': 'CHF', 'chf': 'CHF', 'isviçre frangı': 'CHF',
  'yen': 'JPY', 'jpy': 'JPY',
  'kanada doları': 'CAD', 'cad': 'CAD',
  'avustralya doları': 'AUD', 'aud': 'AUD',
  'riyal': 'SAR', 'sar': 'SAR',
  'dirhem': 'AED', 'aed': 'AED',
  'leva': 'BGN', 'bgn': 'BGN',
  'kron': 'SEK', 'sek': 'SEK',
  'yuan': 'CNY', 'cny': 'CNY',
};

final _curRe = RegExp(
    r'^(\d+(?:[.,]\d+)*)\s*([a-zçğıöşü$€£₺ ]+?)\s*(?:(?:kaç|kac|to|in|=|->|→|ne kadar)\s*([a-zçğıöşü$€£₺ ]+?))?\s*(?:eder|yapar)?\s*\??$');

/// Döviz kurları: Avrupa Merkez Bankası verisi, frankfurter.dev üzerinden (ücretsiz, anahtarsız).
/// Oturum boyunca bir kez indirilir.
class Rates {
  Rates._();
  static Map<String, double>? _eurRates; // 1 EUR = x birim
  static String? date;
  static Future<void>? _loading;

  static bool get ready => _eurRates != null;

  static Future<void> load() => _loading ??= _fetch();

  static Future<void> _fetch() async {
    for (final url in [
      'https://api.frankfurter.dev/v1/latest?base=EUR',
      'https://api.frankfurter.app/latest?from=EUR',
    ]) {
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
        if (res.statusCode != 200) continue;
        final j = jsonDecode(res.body) as Map;
        final rates = <String, double>{'EUR': 1};
        (j['rates'] as Map).forEach((k, v) => rates[k.toString()] = (v as num).toDouble());
        _eurRates = rates;
        date = j['date']?.toString();
        return;
      } catch (_) {}
    }
    _loading = null; // sonra yeniden denensin
  }

  static double? convert(double amount, String from, String to) {
    final r = _eurRates;
    if (r == null || r[from] == null || r[to] == null) return null;
    return amount / r[from]! * r[to]!;
  }
}

String? _currencyCode(String? s) {
  if (s == null) return null;
  final t = s.trim();
  return _currencyNames[t] ?? (RegExp(r'^[a-z]{3}$').hasMatch(t) ? t.toUpperCase() : null);
}

/// Döviz cevabı; kurlar henüz yüklenmediyse null döner ve yüklemeyi başlatır.
SmartAnswer? _currency(String q) {
  final m = _curRe.firstMatch(q.trim().toLowerCase());
  if (m == null) return null;
  final amount = _num(m.group(1)!);
  final from = _currencyCode(m.group(2));
  if (amount == null || from == null) return null;
  final to = _currencyCode(m.group(3)) ?? (from == 'TRY' ? 'USD' : 'TRY');
  if (to == from) return null;
  if (!Rates.ready) {
    Rates.load();
    return null;
  }
  final v = Rates.convert(amount, from, to);
  if (v == null) return null;
  String sym(String c) => switch (c) { 'TRY' => 'TL', _ => c };
  final text = formatTr(v, maxDecimals: 2);
  final d = Rates.date;
  final dateTr = d != null && d.length == 10 ? '${d.substring(8)}.${d.substring(5, 7)}.${d.substring(0, 4)}' : '';
  return SmartAnswer('${formatTr(amount)} ${sym(from)} = $text ${sym(to)}',
      tx('Döviz · ECB${dateTr.isEmpty ? '' : ' $dateTr'}', "Currency · ECB${dateTr.isEmpty ? '' : ' $dateTr'}"), copy: text);
}

/// Yazılan için hızlı cevap varsa döndürür. Döviz kuru gerekiyorsa ve henüz inmemişse
/// [needsRates] true olur; çağıran, kurlar inince yeniden sorabilir.
SmartAnswer? smartAnswer(String q) {
  if (q.trim().length < 2) return null;
  return _calculator(q) ?? _unitConvert(q) ?? _currency(q);
}

/// Yazılan bir döviz sorusuna benziyor mu? (kurları önceden indirmek için)
bool looksLikeCurrency(String q) {
  final m = _curRe.firstMatch(q.trim().toLowerCase());
  return m != null && _currencyCode(m.group(2)) != null;
}
