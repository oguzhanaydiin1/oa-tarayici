import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Pusula Köprü ile bağlantı: açık sekmeyi eşleşmiş telefona (Windows'ta) ya da
/// bilgisayara (Android'de) gönderir; karşıda bağlantı hemen açılır. Hesap gerekmez, aynı Wi-Fi yeter.
class KopruLink {
  KopruLink._();
  static const _ch = MethodChannel('oa/kopru');
  static const indirUrl = 'https://oalabs.dev/kopru/';

  /// (başarılı mı, kullanıcıya gösterilecek ileti)
  static Future<(bool, String)> send(String url) async {
    if (Platform.isAndroid) {
      try {
        final ok = await _ch.invokeMethod<bool>('gonder', {'url': url}) ?? false;
        if (ok) return (true, 'Bilgisayara gönderiliyor');
      } catch (_) {}
      return (false, 'Pusula Köprü kurulu değil');
    }
    if (Platform.isWindows) {
      try {
        final r = await http
            .post(Uri.parse('http://127.0.0.1:47821/v1/local/send'),
                headers: {'content-type': 'application/json'}, body: jsonEncode({'text': url, 'open': true}))
            .timeout(const Duration(seconds: 10));
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is Map && j['ok'] == true) return (true, '${j['peer'] ?? 'Telefon'} cihazında açıldı');
        if (j is Map && j['error'] == 'eslesme') return (false, 'Pusula Köprü\'de eşleşmiş telefon yok');
        if (j is Map && j['error'] == 'ulasilamadi') {
          return (false, '${j['peer'] ?? 'Telefon'} bağlı değil: aynı Wi-Fi\'de ve Pusula Köprü açık mı?');
        }
      } catch (_) {
        return (false, 'Pusula Köprü açık değil');
      }
    }
    return (false, 'Gönderilemedi');
  }
}
