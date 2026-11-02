import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'oa_theme.dart' show oaAvatarImage;
import 'web_env.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// OA Labs üyeliği (oalabs.dev ile aynı hesap).
///
/// Sunucu: api.oalabs.dev (radyo-app deposu, server/src/auth.js). Giriş şifresiz:
/// e-postaya 6 haneli kod gider, doğrulanınca sunucu `oa_s` oturum çerezini verir.
/// Uygulama bu çerezi cihazın güvenli deposunda saklar, isteklerde `Cookie` başlığıyla
/// gönderir ve tarayıcının içindeki oalabs.dev'e de aktarır (sitede de girişli görünürsün).
class OAUser {
  const OAUser({required this.name, required this.email, this.announce = false, this.avatar});
  final String name;
  final String email;
  final bool announce;
  /// Profil fotoğrafının sürümü (yoksa null). Fotoğrafı yalnızca üyenin kendisi görür.
  final String? avatar;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  static OAUser? fromJson(Object? j) {
    if (j is! Map) return null;
    return OAUser(
      name: (j['name'] ?? '').toString(),
      email: (j['email'] ?? '').toString(),
      announce: j['announce'] == true,
      avatar: j['avatar'] is String && (j['avatar'] as String).isNotEmpty ? j['avatar'] as String : null,
    );
  }
}

/// Sunucunun hata kodları için sitedeki metinlerin aynısı.
const _errors = <String, String>{
  'eposta': 'Bu e-posta adresi geçerli görünmüyor.',
  'ad': 'Adını ve soyadını yaz.',
  'onay': 'Üye olmak için aydınlatma metnini onaylaman gerekiyor.',
  'uye-yok': 'Bu e-postayla bir üyelik bulamadık. Üye olmak ister misin?',
  'uye-var': 'Bu e-postayla zaten bir üyelik var.',
  'bekle': 'Az önce bir kod gönderdik. Bir dakika sonra yeniden isteyebilirsin.',
  'cok': 'Çok fazla deneme oldu, biraz sonra tekrar dene.',
  'kod': 'Kod yanlış. E-postadaki 6 haneli kodu kontrol et.',
  'sure': 'Kodun süresi doldu. Yeni bir kod iste.',
  'deneme': 'Çok fazla yanlış deneme oldu. Yeni bir kod iste.',
  'kapali': 'Üyelik çok yakında açılıyor. Biraz sonra tekrar dene.',
  'gonderilemedi': 'E-posta gönderilemedi, biraz sonra tekrar dene.',
  'giris': 'Oturumun kapanmış. Yeniden giriş yap.',
  'ag': 'Sunucuya ulaşılamadı. İnternet bağlantını kontrol et.',
};

String accountError(String? code) =>
    _errors[code] ?? 'Bir sorun çıktı, biraz sonra tekrar dene.';

class AccountResult {
  const AccountResult(this.ok, {this.error, this.created = false});
  final bool ok;
  final String? error;
  final bool created;
  String get message => accountError(error);
}

class OAAccount extends ChangeNotifier {
  static const api = 'https://api.oalabs.dev';
  static const site = 'https://oalabs.dev';
  static const _cookieName = 'oa_s';
  static const _storeKey = 'oa_session';

  final _store = const FlutterSecureStorage();

  String? _token;
  OAUser? user;
  bool loading = true;

  bool get signedIn => user != null;

  /// Sunucu oturum listesinde bu cihazı "Tarayıcı · Windows" / "Tarayıcı · Android" diye gösterir.
  String get _userAgent {
    final os = Platform.isAndroid
        ? 'Linux; Android'
        : Platform.isWindows
            ? 'Windows NT 10.0'
            : Platform.operatingSystem;
    return 'OATarayici/0.3 ($os)';
  }

  Map<String, String> _headers({bool json = false}) => {
        'User-Agent': _userAgent,
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        if (_token != null) 'Cookie': '$_cookieName=$_token',
      };

  /// Kaydedilmiş oturumu yükler; yoksa tarayıcıda sitede açılmış bir oturum varsa onu alır.
  Future<void> load() async {
    try {
      _token = await _store.read(key: _storeKey);
    } catch (_) {
      _token = null;
    }
    if (_token == null) await adoptFromWebView(notify: false);
    if (_token != null) await refresh(notify: false);
    loading = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>> _call(String path, [Map<String, dynamic>? body]) async {
    try {
      final uri = Uri.parse('$api$path');
      final res = body == null
          ? await http.get(uri, headers: _headers()).timeout(const Duration(seconds: 12))
          : await http
              .post(uri,
                  headers: _headers(json: true),
                  body: jsonEncode({'lang': 'tr', ...body}))
              .timeout(const Duration(seconds: 12));
      _readCookie(res.headers['set-cookie']);
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      return data is Map<String, dynamic> ? data : {'ok': false, 'error': 'sunucu'};
    } catch (_) {
      return {'ok': false, 'error': 'ag'};
    }
  }

  void _readCookie(String? header) {
    if (header == null) return;
    final m = RegExp('$_cookieName=([0-9a-f]{64})?').firstMatch(header);
    if (m == null) return;
    final value = m.group(1);
    _token = value; // boş değer: sunucu oturumu kapattı
    _persist();
  }

  Future<void> _persist() async {
    try {
      if (_token == null) {
        await _store.delete(key: _storeKey);
      } else {
        await _store.write(key: _storeKey, value: _token);
      }
    } catch (_) {}
  }

  /// 1. adım: e-postaya kod gönder.
  Future<AccountResult> start({
    required bool register,
    required String email,
    String? name,
    bool consent = false,
    bool announce = false,
  }) async {
    final r = await _call('/v1/auth/start', {
      'mode': register ? 'register' : 'login',
      'email': email.trim(),
      'website': '', // sitedeki bot tuzağı alanı; insanlar boş bırakır
      if (register) ...{'name': (name ?? '').trim(), 'consent': consent, 'announce': announce},
    });
    return AccountResult(r['ok'] == true, error: r['error']?.toString());
  }

  /// 2. adım: kodu doğrula; başarılıysa oturum açılır.
  Future<AccountResult> verify(String email, String code) async {
    final r = await _call('/v1/auth/verify', {'email': email.trim(), 'code': code.trim()});
    if (r['ok'] == true) {
      await refresh(notify: false);
      await syncToWebView();
      notifyListeners();
      return AccountResult(true, created: r['created'] == true);
    }
    return AccountResult(false, error: r['error']?.toString());
  }

  Future<void> refresh({bool notify = true}) async {
    if (_token == null) {
      user = null;
    } else {
      final r = await _call('/v1/me');
      if (r['ok'] == true) {
        user = OAUser.fromJson(r['user']);
      } else if (r['error'] == 'giris') {
        // Oturum sunucuda kapanmış (süresi dolmuş ya da başka cihazdan kapatılmış).
        _token = null;
        user = null;
        await _persist();
      }
    }
    await _loadAvatar();
    if (notify) notifyListeners();
  }

  String? _avatarShown;

  /// Profil fotoğrafını (değiştiyse) oturum çereziyle indirir; yoksa ya da çıkış yapıldıysa temizler.
  Future<void> _loadAvatar() async {
    final key = _token == null ? null : user?.avatar;
    if (key == null) {
      _avatarShown = null;
      oaAvatarImage.value = null;
      return;
    }
    if (key == _avatarShown && oaAvatarImage.value != null) return;
    try {
      final res = await http
          .get(Uri.parse('$api/v1/me/avatar?v=${Uri.encodeQueryComponent(key)}'), headers: {
            'User-Agent': _userAgent,
            'Accept': 'image/*',
            'Cookie': '$_cookieName=$_token',
          })
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        _avatarShown = key;
        oaAvatarImage.value = res.bodyBytes;
      } else if (res.statusCode == 404) {
        _avatarShown = null;
        oaAvatarImage.value = null;
      }
    } catch (_) {
      // Ağ yoksa baş harfler görünmeye devam eder; sonraki yenilemede yeniden denenir.
    }
  }

  Future<void> logout() async {
    if (_token != null) await _call('/v1/auth/logout', {});
    _token = null;
    user = null;
    _avatarShown = null;
    oaAvatarImage.value = null;
    await _persist();
    try {
      await oaCookies()
          .deleteCookie(url: WebUri(site), name: _cookieName, domain: '.oalabs.dev');
    } catch (_) {}
    notifyListeners();
  }

  // ---------------------------------------------------------------- Eşitleme

  /// Sunucudaki eşitlenmiş koleksiyonlar: { "bookmarks": SyncItem, "quick": SyncItem }.
  /// Sunucu eşitlemeyi henüz desteklemiyorsa (eski sürüm) null döner.
  Future<Map<String, SyncItem>?> pullSync() async {
    if (_token == null) return null;
    final r = await _call('/v1/me/sync');
    return r['ok'] == true ? SyncItem.parseAll(r['items']) : null;
  }

  /// Yerel koleksiyonları gönderir; sunucu daha yenisini tutuyorsa onu döndürür.
  Future<Map<String, SyncItem>?> pushSync(Map<String, SyncItem> items) async {
    if (_token == null) return null;
    final r = await _call('/v1/me/sync', {
      'items': {for (final e in items.entries) e.key: e.value.toJson()},
    });
    return r['ok'] == true ? SyncItem.parseAll(r['items']) : null;
  }

  /// Uygulamadaki oturumu tarayıcının içindeki oalabs.dev'e aktarır.
  Future<void> syncToWebView() async {
    final t = _token;
    if (t == null) return;
    try {
      await oaCookies().setCookie(
        url: WebUri(site),
        name: _cookieName,
        value: t,
        domain: '.oalabs.dev',
        path: '/',
        isSecure: true,
        isHttpOnly: true,
        sameSite: HTTPCookieSameSitePolicy.LAX,
        expiresDate:
            DateTime.now().add(const Duration(days: 60)).millisecondsSinceEpoch,
      );
    } catch (e) {
      debugPrint('Oturum tarayıcıya aktarılamadı: $e');
    }
  }

  /// Kullanıcı sitede (tarayıcının içinde) giriş yaptıysa o oturumu uygulamaya alır.
  /// oalabs.dev sayfası her yüklendiğinde çağrılır.
  Future<void> adoptFromWebView({bool notify = true}) async {
    try {
      final c = await oaCookies()
          .getCookie(url: WebUri('$site/'), name: _cookieName);
      final v = c?.value?.toString() ?? '';
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(v)) {
        if (v == _token) return;
        _token = v;
        await _persist();
        await refresh(notify: notify);
      } else if (_token != null && user != null && c == null) {
        // Sitede çıkış yapılmış olabilir; sunucuya sorup öğren.
        await refresh(notify: notify);
      }
    } catch (_) {}
  }
}

/// Eşitlenen bir koleksiyon: son değişiklik zamanı ve içerik.
class SyncItem {
  const SyncItem(this.updated, this.data);
  final DateTime updated;
  final List<dynamic> data;

  Map<String, dynamic> toJson() => {'updated': updated.toUtc().toIso8601String(), 'data': data};

  static Map<String, SyncItem> parseAll(Object? j) {
    final out = <String, SyncItem>{};
    if (j is! Map) return out;
    j.forEach((k, v) {
      if (v is Map && v['data'] is List) {
        final t = DateTime.tryParse(v['updated']?.toString() ?? '');
        if (t != null) out[k.toString()] = SyncItem(t, v['data'] as List);
      }
    });
    return out;
  }
}
