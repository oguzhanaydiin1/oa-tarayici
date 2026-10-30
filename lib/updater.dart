import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Derlenirken verilen sürüm (CI: --dart-define=APP_VERSION=0.6.0).
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');

class UpdateInfo {
  const UpdateInfo(this.version, this.assetUrl, this.assetName, this.pageUrl, this.notes);
  final String version;
  final String assetUrl;
  final String assetName;
  final String pageUrl;
  final String notes;
}

/// Yeni sürüm denetimi: GitHub'daki oa-tarayici sürümlerine bakar (deneme sürümleri dahil).
class Updater {
  Updater._();
  static const _api = 'https://api.github.com/repos/oguzhanaydiin1/oa-tarayici/releases?per_page=5';

  static List<int> _parts(String v) =>
      v.replaceFirst(RegExp(r'^v'), '').split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();

  static bool isNewer(String remote, String local) {
    final a = _parts(remote), b = _parts(local);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// Bu cihaza uygun güncelleme varsa döndürür, yoksa null.
  static Future<UpdateInfo?> check() async {
    if (appVersion == '0.0.0') return null; // geliştirme derlemesi
    final r = await http.get(Uri.parse(_api), headers: {
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'OATarayici/$appVersion',
    }).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    final wanted = Platform.isAndroid ? 'OA-Tarayici-Android.apk' : 'OA-Tarayici-Kurulum.exe';
    for (final rel in list.whereType<Map>()) {
      if (rel['draft'] == true) continue;
      final tag = rel['tag_name']?.toString() ?? '';
      if (!isNewer(tag, appVersion)) return null; // en yenisi bile yeni değil
      for (final a in (rel['assets'] as List? ?? const []).whereType<Map>()) {
        if (a['name'] == wanted) {
          return UpdateInfo(
            tag.replaceFirst(RegExp(r'^v'), ''),
            a['browser_download_url'].toString(),
            wanted,
            rel['html_url']?.toString() ?? '',
            rel['body']?.toString() ?? '',
          );
        }
      }
    }
    return null;
  }
}
