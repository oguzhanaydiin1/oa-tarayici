import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'i18n.dart';

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
      'User-Agent': 'PusulaBrowser/$appVersion',
    }).timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final list = jsonDecode(utf8.decode(r.bodyBytes)) as List;
    // Yeni ad önce; eski sürümlerde yalnız eski ad vardı
    final names = Platform.isAndroid
        ? ['Pusula-Android.apk', 'OA-Tarayici-Android.apk']
        : ['Pusula-Kurulum.exe', 'OA-Tarayici-Kurulum.exe'];
    for (final rel in list.whereType<Map>()) {
      if (rel['draft'] == true) continue;
      final tag = rel['tag_name']?.toString() ?? '';
      if (!isNewer(tag, appVersion)) return null; // en yenisi bile yeni değil
      final assets = (rel['assets'] as List? ?? const []).whereType<Map>().toList();
      for (final wanted in names) {
        final a = assets.where((x) => x['name'] == wanted).firstOrNull;
        if (a != null) {
          return UpdateInfo(
            tag.replaceFirst(RegExp(r'^v'), ''),
            a['browser_download_url'].toString(),
            wanted,
            rel['html_url']?.toString() ?? '',
            // Sürüm notunun altındaki "---" sonrası (site bağlantısı) uygulamada gösterilmez.
            _notesFor((rel['body']?.toString() ?? '').split('\n---\n').first.trim()),
          );
        }
      }
    }
    return null;
  }
}

/// Windows: kurulum dosyasını geçici klasöre indirir ([onProgress] 0..1).
/// İndirilenler listesine eklenmez; her sürüm kendi adıyla iner (eski bir kurulum açık kalsa da çakışmaz).
Future<File?> downloadInstaller(UpdateInfo u, void Function(double) onProgress) async {
  final client = http.Client();
  try {
    final res = await client.send(http.Request('GET', Uri.parse(u.assetUrl))
      ..headers['User-Agent'] = 'PusulaBrowser/$appVersion');
    if (res.statusCode != 200) return null;
    final f = File('${Directory.systemTemp.path}${Platform.pathSeparator}Pusula-Kurulum-${u.version}.exe');
    final sink = f.openWrite();
    final total = res.contentLength ?? 0;
    var got = 0;
    await for (final chunk in res.stream) {
      sink.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress(got / total);
    }
    await sink.close();
    if (total > 0 && got != total) return null;
    return f;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// Kurulumu sessizce başlatır. Uygulama, kurulum klasörü dışından (örn. zip'ten açılmış)
/// çalışıyorsa güncelleme bulunduğu klasöre yapılır; böylece açılan sürüm gerçekten yenilenir.
Future<bool> runInstaller(File setup) async {
  final dir = File(Platform.resolvedExecutable).parent.path;
  var writable = false;
  try {
    final probe = File('$dir${Platform.pathSeparator}.pusula-yazma-denemesi');
    probe.writeAsStringSync('1');
    probe.deleteSync();
    writable = true;
  } catch (_) {}
  try {
    await Process.start(
      setup.path,
      ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/NOCANCEL', if (writable) '/DIR=$dir'],
      mode: ProcessStartMode.detached,
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Sürüm notu önce Türkçe, boş bir satırdan sonra İngilizce maddeler içerir;
/// uygulamanın diline uyan kısmı gösterilir.
String _notesFor(String body) {
  final parts = body.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).toList();
  if (parts.length < 2) return body;
  return L.en ? parts.sublist(1).join('\n\n').trim() : parts.first.trim();
}
