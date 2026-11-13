import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'i18n.dart';
/// Şifre eşitlemesi için kasa anahtarı. Kullanıcının eşitleme parolasından (PBKDF2) türetilir;
/// şifreler cihazdan AES-256-GCM ile şifrelenmiş olarak çıkar, sunucu içini göremez.
/// Parola hiçbir yere gönderilmez; türetilen anahtar yalnız cihazın güvenli deposunda durur.
class Vault {
  static const _keyK = 'oa_vault_key';
  static const _saltK = 'oa_vault_salt';
  static const _iterations = 120000;
  final _store = const FlutterSecureStorage();
  final _aes = AesGcm.with256bits();

  List<int>? _key;
  String? _salt;

  bool get enabled => _key != null;

  Future<void> load() async {
    try {
      final k = await _store.read(key: _keyK);
      _salt = await _store.read(key: _saltK);
      if (k != null && _salt != null) _key = base64Decode(k);
    } catch (_) {}
  }

  static Future<List<int>> _derive(String pass, List<int> salt) async {
    final pbkdf2 = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _iterations, bits: 256);
    final k = await pbkdf2.deriveKeyFromPassword(password: pass, nonce: salt);
    return k.extractBytes();
  }

  /// Parolayla kasayı açar. Sunucuda kasa varsa parola onunla denenir.
  /// Hata metni döner; başarılıysa null.
  Future<String?> enable(String pass, Map? remote) async {
    if (pass.length < 8) return tx('Parola en az 8 karakter olmalı', 'Password must be at least 8 characters');
    String salt;
    if (remote != null && remote['s'] is String) {
      salt = remote['s'] as String;
    } else {
      final r = Random.secure();
      salt = base64Encode(List<int>.generate(16, (_) => r.nextInt(256)));
    }
    final key = await _derive(pass, base64Decode(salt));
    if (remote != null && remote['c'] is String) {
      final ok = await _open(remote, key) != null;
      if (!ok) return tx('Parola yanlış: öbür cihazda belirlediğin eşitleme parolasını yaz', 'Wrong password: enter the sync password you set on your other device');
    }
    _key = key;
    _salt = salt;
    await _store.write(key: _keyK, value: base64Encode(key));
    await _store.write(key: _saltK, value: salt);
    return null;
  }

  Future<void> disable() async {
    _key = null;
    _salt = null;
    await _store.delete(key: _keyK);
    await _store.delete(key: _saltK);
  }

  Future<Map<String, dynamic>> seal(Map<String, dynamic> data) async {
    final box = await _aes.encrypt(utf8.encode(jsonEncode(data)), secretKey: SecretKey(_key!));
    return {
      'v': 1,
      's': _salt,
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    };
  }

  Future<Map?> open(Map box) async => _key == null ? null : _open(box, _key!);

  /// Kasadaki tuz bizimkinden farklıysa (kasa başka parolayla baştan kuruldu) açılamaz.
  bool sameSalt(Map box) => box['s'] == _salt;

  Future<Map?> _open(Map box, List<int> key) async {
    try {
      final sb = SecretBox(
        base64Decode(box['c'] as String),
        nonce: base64Decode(box['n'] as String),
        mac: Mac(base64Decode(box['m'] as String)),
      );
      final clear = await _aes.decrypt(sb, secretKey: SecretKey(key));
      return jsonDecode(utf8.decode(clear)) as Map;
    } catch (_) {
      return null;
    }
  }
}
