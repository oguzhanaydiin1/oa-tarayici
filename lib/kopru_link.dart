import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'i18n.dart';
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
        if (ok) return (true, tx('Bilgisayara gönderiliyor', 'Sending to the computer'));
      } catch (_) {}
      return (false, tx('Pusula Köprü kurulu değil', "Pusula Köprü isn't installed"));
    }
    if (Platform.isWindows) {
      try {
        final r = await http
            .post(Uri.parse('http://127.0.0.1:47821/v1/local/send'),
                headers: {'content-type': 'application/json'}, body: jsonEncode({'text': url, 'open': true}))
            .timeout(const Duration(seconds: 10));
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        if (j is Map && j['ok'] == true) return (true, tx('${j['peer'] ?? 'Telefon'} cihazında açıldı', "Opened on ${j['peer'] ?? 'the phone'}"));
        if (j is Map && j['error'] == 'eslesme') return (false, tx('Pusula Köprü\'de eşleşmiş telefon yok', 'No phone is paired in Pusula Köprü'));
        if (j is Map && j['error'] == 'ulasilamadi') {
          return (false, tx('${j['peer'] ?? 'Telefon'} bağlı değil: aynı Wi-Fi\'de ve Pusula Köprü açık mı?', "${j['peer'] ?? 'The phone'} isn't connected: is it on the same Wi-Fi with Pusula Köprü open?"));
        }
      } catch (_) {
        return (false, tx('Pusula Köprü açık değil', "Pusula Köprü isn't open"));
      }
    }
    return (false, tx('Gönderilemedi', "Couldn't send"));
  }
}
