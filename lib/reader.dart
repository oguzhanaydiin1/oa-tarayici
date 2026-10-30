import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'oa_theme.dart';

enum ReaderResult { opened, closed, notAvailable, failed }

/// Okuma modu: Mozilla Readability (assets/readability.js, Apache 2.0) sayfadaki asıl yazıyı
/// ayıklar; assets/reader.js onu OA fontları ve renkleriyle sayfanın üstünde gösterir.
class Reader {
  Reader._();
  static String? _script;

  static Future<String> _load() async => _script ??=
      '${await rootBundle.loadString('assets/readability.js')}\n${await rootBundle.loadString('assets/reader.js')}';

  static String _hex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  static Future<ReaderResult> toggle(InAppWebViewController c, {int fontSize = 19}) async {
    try {
      final ready = await c.evaluateJavascript(source: 'typeof window.__oaReader === "function"');
      if (ready != true) await c.evaluateJavascript(source: await _load());
      final p = OAColors.palette;
      final opts = '{bg:"${_hex(p.bg.toARGB32())}",text:"${_hex(p.text.toARGB32())}",'
          'muted:"${_hex(p.muted.toARGB32())}",surface:"${_hex(p.surface.toARGB32())}",'
          'border:"${_hex(p.border.toARGB32())}",accent:"${_hex(p.accent.toARGB32())}",size:$fontSize}';
      final r = await c.evaluateJavascript(source: 'window.__oaReader($opts)');
      return switch (r?.toString()) {
        'acik' => ReaderResult.opened,
        'kapali' => ReaderResult.closed,
        'yok' => ReaderResult.notAvailable,
        _ => ReaderResult.failed,
      };
    } catch (_) {
      return ReaderResult.failed;
    }
  }
}
