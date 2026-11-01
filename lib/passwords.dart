import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'oa_theme.dart';

/// Bir sitenin kayıtlı girişi.
class SavedLogin {
  SavedLogin({required this.origin, required this.user, required this.pass, required this.updated});

  final String origin; // https://site.com
  final String user;
  String pass;
  int updated;

  String get host => Uri.tryParse(origin)?.host.replaceFirst(RegExp(r'^www\.'), '') ?? origin;

  Map<String, dynamic> toJson() => {'o': origin, 'u': user, 'p': pass, 't': updated};

  static SavedLogin? fromJson(Map j) {
    final o = j['o']?.toString() ?? '';
    final p = j['p']?.toString() ?? '';
    if (o.isEmpty || p.isEmpty) return null;
    return SavedLogin(origin: o, user: j['u']?.toString() ?? '', pass: p, updated: (j['t'] as num?)?.toInt() ?? 0);
  }
}

/// Şifreler cihazın güvenli deposunda (Android Keystore, Windows DPAPI) saklanır; sunucuya gitmez.
class PasswordStore extends ChangeNotifier {
  static const _key = 'oa_passwords';
  static const _neverKey = 'oa_passwords_never';
  final _store = const FlutterSecureStorage();

  List<SavedLogin> items = [];
  Set<String> never = {};
  bool _loaded = false;

  static String originOf(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.hasScheme || u.host.isEmpty || !u.scheme.startsWith('http')) return '';
    return u.origin;
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await _store.read(key: _key);
      if (raw != null) {
        items = (jsonDecode(raw) as List).whereType<Map>().map(SavedLogin.fromJson).whereType<SavedLogin>().toList();
      }
      final n = await _store.read(key: _neverKey);
      if (n != null) never = (jsonDecode(n) as List).map((e) => e.toString()).toSet();
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await _store.write(key: _key, value: jsonEncode(items.map((e) => e.toJson()).toList()));
      await _store.write(key: _neverKey, value: jsonEncode(never.toList()));
    } catch (_) {}
    notifyListeners();
  }

  /// Bu sitenin girişleri, en son kullanılan önce.
  List<SavedLogin> forOrigin(String origin) =>
      items.where((e) => e.origin == origin).toList()..sort((a, b) => b.updated.compareTo(a.updated));

  SavedLogin? find(String origin, String user) {
    for (final e in items) {
      if (e.origin == origin && e.user == user) return e;
    }
    return null;
  }

  Future<void> upsert(String origin, String user, String pass) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final e = find(origin, user);
    if (e != null) {
      e
        ..pass = pass
        ..updated = now;
    } else {
      items.add(SavedLogin(origin: origin, user: user, pass: pass, updated: now));
    }
    never.remove(origin);
    await _save();
  }

  /// Toplu ekleme (içe aktarma). Eklenen ya da güncellenen kayıt sayısını döndürür.
  Future<int> importMany(Iterable<(String, String, String)> logins) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var n = 0;
    for (final (origin, user, pass) in logins) {
      if (origin.isEmpty || pass.isEmpty) continue;
      final e = find(origin, user);
      if (e != null) {
        if (e.pass == pass) continue;
        e
          ..pass = pass
          ..updated = now;
      } else {
        items.add(SavedLogin(origin: origin, user: user, pass: pass, updated: now));
      }
      n++;
    }
    if (n > 0) await _save();
    return n;
  }

  Future<void> touch(SavedLogin e) async {
    e.updated = DateTime.now().millisecondsSinceEpoch;
    await _save();
  }

  Future<void> remove(SavedLogin e) async {
    items.remove(e);
    await _save();
  }

  Future<void> neverFor(String origin) async {
    never.add(origin);
    await _save();
  }

  Future<void> clearNever() async {
    never.clear();
    await _save();
  }
}

/// Cihazın kilidiyle (parmak izi, yüz, PIN; Windows'ta Windows Hello) doğrulama.
class DeviceLock {
  DeviceLock._();
  static final _auth = LocalAuthentication();

  static Future<bool> supported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Doğrulama başarılıysa true. Cihazda kilit yoksa [ifUnsupported] döner.
  static Future<bool> verify(String reason, {bool ifUnsupported = true}) async {
    if (!await supported()) return ifUnsupported;
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }
}

/// Kayıtlı şifreler listesi.
class PasswordsSheet extends StatefulWidget {
  const PasswordsSheet({super.key, required this.store});
  final PasswordStore store;

  @override
  State<PasswordsSheet> createState() => _PasswordsSheetState();
}

class _PasswordsSheetState extends State<PasswordsSheet> {
  final Set<SavedLogin> _shown = {};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final list = s.items
            .where((e) => _q.isEmpty || e.host.contains(_q) || e.user.toLowerCase().contains(_q))
            .toList()
          ..sort((a, b) => a.host.compareTo(b.host));
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          maxChildSize: 0.95,
          builder: (context, scroll) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Row(
                  children: [
                    Icon(Icons.key_outlined, color: OAColors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Şifreler',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: OAColors.text)),
                    ),
                    Text('${s.items.length} kayıt', style: TextStyle(color: OAColors.muted)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Şifreler yalnız bu cihazın güvenli deposunda saklanır, hesabınla eşitlenmez.',
                    style: TextStyle(color: OAColors.muted, fontSize: 13)),
              ),
              if (s.items.length > 6)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Site ya da kullanıcı ara'),
                    onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  ),
                ),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Henüz kayıtlı şifre yok.\nBir siteye giriş yapınca OA Tarayıcı kaydetmeyi sorar.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: OAColors.muted),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scroll,
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final e = list[i];
                          final shown = _shown.contains(e);
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: OAColors.surface2,
                              child: Text(e.host.isEmpty ? '?' : e.host[0].toUpperCase(),
                                  style: TextStyle(color: OAColors.amber, fontWeight: FontWeight.w700)),
                            ),
                            title: Text(e.host, style: TextStyle(color: OAColors.text)),
                            subtitle: Text(
                              '${e.user.isEmpty ? '(kullanıcı adı yok)' : e.user}\n${shown ? e.pass : '•' * 10}',
                              style: TextStyle(color: OAColors.muted),
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: shown ? 'Gizle' : 'Göster',
                                  icon: Icon(shown ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                  onPressed: () => setState(() => shown ? _shown.remove(e) : _shown.add(e)),
                                ),
                                IconButton(
                                  tooltip: 'Şifreyi kopyala',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: e.pass));
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(content: Text('Şifre kopyalandı')));
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Sil',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: const Text('Şifre silinsin mi?'),
                                        content: Text('${e.host} · ${e.user}'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
                                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sil')),
                                        ],
                                      ),
                                    );
                                    if (ok == true) s.remove(e);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (s.never.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: TextButton.icon(
                    icon: const Icon(Icons.restart_alt),
                    label: Text('"Asla kaydetme" denen ${s.never.length} siteyi sıfırla'),
                    onPressed: s.clearNever,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
