import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'oa_theme.dart';

// OA Akış: aynı hesapla giriş yapılmış cihazlar arasında not, bağlantı, fotoğraf ve küçük
// dosya gönderme. Gönderilenler alıcının "inbox:<cihaz>" kaydına yazılır; alıcı açılınca alır,
// dosyaları İndirilenler'e kaydeder ve kaydı boşaltır. Bu cihazdaki akış geçmişi yalnız burada tutulur.

/// Bir dosyanın en büyük boyu (sunucuya base64 olarak gider).
const kFlowFileMax = 600 * 1024;

/// Kayıt türleri: 'tab' (bağlantı / sekme), 'note', 'file'.
String flowKind(Map m) => m['k']?.toString() ?? 'tab';

String flowMime(String name) {
  final e = name.toLowerCase().split('.').last;
  const m = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp',
    'heic': 'image/heic', 'bmp': 'image/bmp', 'pdf': 'application/pdf', 'txt': 'text/plain', 'zip': 'application/zip',
    'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'mp4': 'video/mp4', 'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };
  return m[e] ?? 'application/octet-stream';
}

String flowSize(num b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// Yazılan metin tek bir bağlantıysa onu döndürür.
String? flowLinkOf(String text) {
  final t = text.trim();
  if (t.contains(RegExp(r'\s'))) return null;
  if (RegExp(r'^https?://\S+$').hasMatch(t)) return t;
  if (RegExp(r'^(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)+(/\S*)?$', caseSensitive: false).hasMatch(t)) return 'https://$t';
  return null;
}

/// Hedef cihaz (main.dart'taki RemoteDevice'ın akış için gereken kısmı).
class FlowDevice {
  const FlowDevice(this.id, this.name, this.android);
  final String id;
  final String name;
  final bool android;
}

class FlowSheet extends StatefulWidget {
  const FlowSheet({
    super.key,
    required this.log,
    required this.devices,
    required this.onSend,
    required this.onOpenUrl,
    required this.onOpenFile,
    required this.onClear,
    this.initialText,
  });

  final ValueListenable<List<Map>> log;
  final List<FlowDevice> devices;

  /// Kaydı (bağlantı / not / dosya) seçilen cihaza gönderir; başarılıysa true.
  final Future<bool> Function(FlowDevice d, Map item) onSend;
  final void Function(String url) onOpenUrl;
  final void Function(String path) onOpenFile;
  final VoidCallback onClear;
  final String? initialText;

  @override
  State<FlowSheet> createState() => _FlowSheetState();
}

class _FlowSheetState extends State<FlowSheet> {
  late final TextEditingController _text = TextEditingController(text: widget.initialText ?? '');
  FlowDevice? _to;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.devices.isNotEmpty) _to = widget.devices.first;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _say(String s) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _send(Map item) async {
    final d = _to;
    if (d == null || _busy) return;
    setState(() => _busy = true);
    final ok = await widget.onSend(d, item);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) _say('Gönderilemedi, internet bağlantını kontrol et');
  }

  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    final link = flowLinkOf(t);
    final item = link != null ? {'k': 'tab', 'u': link, 't': ''} : {'k': 'note', 'x': t.length > 20000 ? t.substring(0, 20000) : t};
    await _send(item);
    if (mounted && !_busy) _text.clear();
  }

  Future<void> _pick({required bool image}) async {
    final r = await FilePicker.platform.pickFiles(type: image ? FileType.image : FileType.any, withData: true);
    final f = r?.files.singleOrNull;
    if (f == null) return;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) return;
    if (bytes.length > kFlowFileMax) {
      _say('Dosya çok büyük: en çok ${flowSize(kFlowFileMax)} gönderilebilir (bu dosya ${flowSize(bytes.length)})');
      return;
    }
    await _send({'k': 'file', 'n': f.name, 'm': flowMime(f.name), 's': bytes.length, 'd': base64Encode(bytes), 'p': f.path});
  }

  Widget _bubble(Map m) {
    final out = m['out'] == true;
    final kind = flowKind(m);
    final at = DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0);
    String two(int v) => v.toString().padLeft(2, '0');
    final when = '${two(at.day)}.${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
    final who = out ? '→ ${m['to'] ?? ''}' : '${m['from'] ?? 'Öbür cihaz'}';
    Widget body;
    VoidCallback? tap;
    if (kind == 'note') {
      final x = m['x']?.toString() ?? '';
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SelectableText(x, style: TextStyle(color: OAColors.text, fontSize: 14.5, height: 1.35)),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: x));
              _say('Kopyalandı');
            },
            icon: const Icon(Icons.copy, size: 15),
            label: const Text('Kopyala'),
          ),
        ),
      ]);
    } else if (kind == 'file') {
      final path = m['p']?.toString();
      final exists = path != null && File(path).existsSync();
      final img = (m['m']?.toString() ?? '').startsWith('image/') && exists;
      tap = exists ? () => widget.onOpenFile(path) : null;
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (img)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Image.file(File(path), fit: BoxFit.cover, cacheWidth: 600, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ),
            ),
          ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(img ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 20, color: OAColors.amber),
          const SizedBox(width: 8),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m['n']?.toString() ?? 'dosya',
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: OAColors.text, fontWeight: FontWeight.w600)),
              Text(
                  '${flowSize((m['s'] as num?) ?? 0)}${exists ? (out ? '' : ' · İndirilenler') : ' · dosya artık burada değil'}',
                  style: TextStyle(color: OAColors.muted, fontSize: 12)),
            ]),
          ),
        ]),
      ]);
    } else {
      final u = m['u']?.toString() ?? '';
      final title = m['t']?.toString() ?? '';
      tap = () => widget.onOpenUrl(u);
      body = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.link, size: 20, color: OAColors.amber),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.isNotEmpty ? title : u,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: OAColors.text, fontWeight: FontWeight.w600)),
            Text(Uri.tryParse(u)?.host ?? u, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: OAColors.muted, fontSize: 12)),
          ]),
        ),
      ]);
    }
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            Material(
              color: out ? OAColors.surface2 : OAColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: out ? OAColors.amber.withValues(alpha: 0.35) : OAColors.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: tap,
                child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 10), child: body),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
              child: Text('$who · $when', style: TextStyle(color: OAColors.faint, fontSize: 11)),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('OA Akış', style: oaDisplay(24)),
                Text('Cihazların arasında not, bağlantı, fotoğraf ve dosya', style: TextStyle(color: OAColors.muted, fontSize: 13)),
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'clear') widget.onClear();
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'clear', child: Text('Bu cihazdaki akış geçmişini temizle'))],
            ),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        if (widget.devices.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Text('Başka cihaz bulunamadı. Öbür cihazda OA Tarayıcı\'yı açıp aynı hesapla giriş yap.',
                style: TextStyle(color: OAColors.muted)),
          )
        else
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                for (final d in widget.devices)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(d.android ? Icons.smartphone : Icons.computer, size: 16),
                      label: Text(d.name),
                      selected: _to?.id == d.id,
                      onSelected: (_) => setState(() => _to = d),
                    ),
                  ),
              ],
            ),
          ),
        Divider(height: 1, color: OAColors.line),
        Expanded(
          child: ValueListenableBuilder<List<Map>>(
            valueListenable: widget.log,
            builder: (context, log, _) {
              if (log.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.swap_horiz_rounded, size: 44, color: OAColors.faint),
                      const SizedBox(height: 10),
                      Text('Henüz bir şey gönderilmedi.\nAşağıya bir not ya da bağlantı yaz, ya da dosya ekle.',
                          textAlign: TextAlign.center, style: TextStyle(color: OAColors.muted)),
                    ]),
                  ),
                );
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                itemCount: log.length,
                itemBuilder: (_, i) => _bubble(log[log.length - 1 - i]),
              );
            },
          ),
        ),
        Container(
          decoration: BoxDecoration(color: OAColors.surface, border: Border(top: BorderSide(color: OAColors.line))),
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
          child: SafeArea(
            top: false,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(
                tooltip: 'Fotoğraf gönder',
                onPressed: _to == null || _busy ? null : () => _pick(image: true),
                icon: const Icon(Icons.image_outlined),
              ),
              IconButton(
                tooltip: 'Dosya gönder (en çok ${flowSize(kFlowFileMax)})',
                onPressed: _to == null || _busy ? null : () => _pick(image: false),
                icon: const Icon(Icons.attach_file),
              ),
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 5,
                  enabled: _to != null,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: _to == null ? 'Gönderilecek cihaz yok' : '${_to!.name} cihazına not ya da bağlantı',
                    isDense: true,
                    filled: true,
                    fillColor: OAColors.bg2,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  ),
                  onSubmitted: (_) => _sendText(),
                ),
              ),
              const SizedBox(width: 4),
              _busy
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4)))
                  : IconButton.filled(
                      tooltip: 'Gönder',
                      onPressed: _to == null ? null : _sendText,
                      icon: const Icon(Icons.send_rounded),
                    ),
            ]),
          ),
        ),
      ]),
    );
  }
}
