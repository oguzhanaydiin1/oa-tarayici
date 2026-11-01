import 'package:flutter/material.dart';

import 'oa_theme.dart';
import 'wallpaper.dart';

/// Başlangıç sayfasındaki hızlı erişim kutusu. Kullanıcı ekler, düzenler, kaldırır.
class QuickLink {
  const QuickLink(this.name, this.url, {this.color});
  final String name;
  final String url;

  /// İsteğe bağlı kutu rengi: 'amber' (OA uygulamaları), 'harrier'; boşsa nötr.
  final String? color;

  String get letter {
    if (color == 'amber' && name == 'OA Labs') return 'OA';
    final n = name.trim();
    return n.isEmpty ? '?' : n.characters.first.toUpperCase();
  }

  Map<String, String> toJson() => {'name': name, 'url': url, if (color != null) 'color': color!};

  static QuickLink fromJson(Map j) =>
      QuickLink((j['name'] ?? '').toString(), (j['url'] ?? '').toString(),
          color: j['color']?.toString());
}

const kDefaultQuickLinks = <QuickLink>[
  QuickLink('OA Labs', 'https://oalabs.dev', color: 'amber'),
  QuickLink('OA Radyo', 'https://oalabs.dev/radyo/', color: 'amber'),
  QuickLink('Harrier Cleaner', 'https://oalabs.dev/#uygulamalar', color: 'harrier'),
  QuickLink('Vikipedi', 'https://tr.wikipedia.org'),
  QuickLink('GitHub', 'https://github.com'),
  QuickLink('OpenStreetMap', 'https://www.openstreetmap.org'),
];

const kMaxQuickLinks = 12;

enum QuickAction { open, openNewTab, edit, remove }

/// Sitenin ikonu: önce sitenin kendi büyük ikonu (apple-touch-icon), yoksa Google'ın ikon
/// servisi, o da yoksa baş harf. İkonlar yalnız başlangıç sayfasındaki siteler için istenir.
class SiteIcon extends StatelessWidget {
  const SiteIcon({super.key, required this.url, required this.letter, this.bg, this.fg, this.size = 40});
  final String url;
  final String letter;
  final Color? bg;
  final Color? fg;
  final double size;

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(url)?.host ?? '';
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg ?? OAColors.surface2,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(letter, style: oaDisplay(size * 0.42, color: fg ?? OAColors.text2)),
    );
    // OA uygulamalarının renkli kutuları marka rengini korur.
    if (bg != null || host.isEmpty) return fallback;
    Widget img(String src, Widget onError) => Image.network(
          src,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => onError,
          frameBuilder: (_, child, frame, sync) =>
              frame == null && !sync ? fallback : child,
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Container(
        width: size,
        height: size,
        color: OAColors.surface2,
        child: img(
          'https://$host/apple-touch-icon.png',
          img('https://www.google.com/s2/favicons?domain=$host&sz=64', fallback),
        ),
      ),
    );
  }
}

/// OA başlangıç sayfası: yeni sekmede ve ana sayfa düğmesinde açılır.
class StartPage extends StatefulWidget {
  const StartPage({
    super.key,
    required this.incognito,
    required this.engineName,
    required this.quickLinks,
    required this.bookmarks,
    required this.onGo,
    required this.onQuickAction,
    required this.onQuickAdd,
    required this.onQuickReorder,
    required this.onChangeEngine,
    required this.onWallpaper,
    required this.compact,
    this.wallpaperId = 'none',
    this.wallpaperPath,
    this.userFirstName,
    this.corner,
    this.news,
  });

  /// Haber akışı (hızlı erişimin altında).
  final Widget? news;

  /// Sağ üst köşedeki saat ve hava (geniş pencerede köşede, dar pencerede başlığın üstünde).
  final Widget? corner;

  final bool incognito;
  final String engineName;
  final List<QuickLink> quickLinks;
  final List<Map<String, String>> bookmarks;
  final void Function(String input) onGo;
  final void Function(QuickAction action, int index) onQuickAction;
  final VoidCallback onQuickAdd;
  final void Function(int from, int to) onQuickReorder;
  final VoidCallback onChangeEngine;
  final VoidCallback onWallpaper;
  final String wallpaperId;
  final String? wallpaperPath;
  final String? userFirstName;

  /// Telefon düzeni: arama alanı yerine alttaki adres çubuğu kullanılır.
  final bool compact;

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  final _ctl = TextEditingController();
  bool _arranging = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _ctl.text.trim();
    if (text.isEmpty) return;
    widget.onGo(text);
    _ctl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final titleSize = compact ? 38.0 : 56.0;
    final titleStyle = oaDisplay(titleSize).copyWith(
      letterSpacing: -0.035 * titleSize,
      height: 1.0,
    );
    final kicker = widget.incognito
        ? 'Gizli sekme'
        : widget.userFirstName != null
            ? 'Merhaba ${widget.userFirstName}'
            : 'OA Tarayıcı';

    final wide = MediaQuery.sizeOf(context).width >= 1180;
    return Stack(
      fit: StackFit.expand,
      children: [
        WallpaperLayer(id: widget.wallpaperId, photoPath: widget.wallpaperPath),
        SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            compact ? 20 : 24, compact ? 40 : 56, compact ? 20 : 24, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.corner != null && !wide) ...[
                  Align(alignment: Alignment.centerRight, child: widget.corner!),
                  const SizedBox(height: 20),
                ],
                Text(kicker, style: TextStyle(color: OAColors.muted, fontSize: 15)),
                const SizedBox(height: 14),
                Text.rich(
                  TextSpan(
                    style: titleStyle,
                    children: widget.incognito
                        ? [
                            const TextSpan(text: 'Gezdiklerin '),
                            TextSpan(
                                text: 'kaydedilmez.',
                                style: TextStyle(color: OAColors.accent)),
                          ]
                        : [
                            const TextSpan(text: 'Nereye '),
                            TextSpan(
                                text: 'gidiyoruz?',
                                style: TextStyle(color: OAColors.accent)),
                          ],
                  ),
                ),
                const SizedBox(height: 28),
                if (!compact) ...[
                  _searchField(),
                  const SizedBox(height: 12),
                ],
                _engineLine(),
                const SizedBox(height: 40),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: Text('Hızlı erişim', style: oaDisplay(22))),
                    if (widget.quickLinks.length > 1 || _arranging)
                      TextButton.icon(
                        onPressed: () => setState(() => _arranging = !_arranging),
                        icon: Icon(_arranging ? Icons.check : Icons.drag_indicator, size: 18),
                        label: Text(_arranging ? 'Bitti' : 'Düzenle'),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 12),
                  child: Text(
                    _arranging
                        ? (compact
                            ? 'Kutuyu basılı tutup sürükleyerek yerini değiştir. Dokununca düzenlenir.'
                            : 'Kutuyu sürükleyerek yerini değiştir. Tıklayınca düzenlenir.')
                        : (compact
                            ? 'Bir kutuyu basılı tutarak düzenleyebilir ya da kaldırabilirsin.'
                            : 'Bir kutuya sağ tıklayarak düzenleyebilir ya da kaldırabilirsin.'),
                    style: TextStyle(color: OAColors.faint, fontSize: 13),
                  ),
                ),
                _grid([
                  for (var i = 0; i < widget.quickLinks.length; i++)
                    _arranging ? _arrangeTile(i) : _quickTile(i),
                  if (widget.quickLinks.length < kMaxQuickLinks && !_arranging) _addTile(),
                ]),
                if (widget.news != null) ...[
                  const SizedBox(height: 40),
                  widget.news!,
                ],
                const SizedBox(height: 40),
                Text('Yer imleri', style: oaDisplay(22)),
                const SizedBox(height: 14),
                if (widget.bookmarks.isEmpty)
                  Text(
                    compact
                        ? 'Henüz yer imi yok. Bir sayfadayken alttaki yıldıza dokun.'
                        : 'Henüz yer imi yok. Bir sayfadayken yıldıza dokun.',
                    style: TextStyle(color: OAColors.muted, fontSize: 15),
                  )
                else
                  _grid([
                    for (final b in widget.bookmarks.take(6))
                      _Tile(
                        name: b['title'] ?? '',
                        url: b['url'] ?? '',
                        letter: QuickLink(b['title'] ?? '', '').letter,
                        onTap: () => widget.onGo(b['url'] ?? ''),
                      ),
                  ]),
                const SizedBox(height: 40),
                Divider(height: 1, color: OAColors.line),
                const SizedBox(height: 20),
                const Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _Perk('Reklam yok'),
                    _Perk('Hesap zorunlu değil'),
                    _Perk('Geçmişin cihazında kalır'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
        // Kaydırılan sayfanın üstünde olmalı; altında kalırsa tıklanmıyor.
        if (widget.corner != null && wide)
          Positioned(top: 56, right: 72, child: widget.corner!),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton(
              tooltip: 'Arka plan',
              icon: const Icon(Icons.wallpaper_outlined),
              style: IconButton.styleFrom(
                backgroundColor: OAColors.surface.withValues(alpha: 0.7),
              ),
              onPressed: widget.onWallpaper,
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickTile(int i, {bool arranging = false}) {
    final q = widget.quickLinks[i];
    final (Color? bg, Color? fg) = switch (q.color) {
      'amber' => (OAColors.amber, OAColors.amberInk),
      'harrier' => (const Color(0xFF1E3A8A), const Color(0xFFEEEAE2)),
      _ => (null, null),
    };
    return _Tile(
      name: q.name,
      url: q.url,
      letter: q.letter,
      bg: bg,
      fg: fg,
      onTap: arranging
          ? () => widget.onQuickAction(QuickAction.edit, i)
          : () => widget.onGo(q.url),
      onMenu: arranging ? null : (pos) => _tileMenu(i, pos),
    );
  }

  /// Düzenleme modunda kutu: sürüklenir, üzerine bırakılan kutunun yerine geçer.
  Widget _arrangeTile(int i) {
    final tile = _quickTile(i, arranging: true);
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(width: 140, child: Opacity(opacity: 0.9, child: tile)),
    );
    final draggable = widget.compact
        ? LongPressDraggable<int>(
            data: i,
            delay: const Duration(milliseconds: 250),
            feedback: feedback,
            childWhenDragging: Opacity(opacity: 0.3, child: tile),
            child: tile,
          )
        : Draggable<int>(
            data: i,
            feedback: feedback,
            childWhenDragging: Opacity(opacity: 0.3, child: tile),
            child: tile,
          );
    return DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != i,
      onAcceptWithDetails: (d) => widget.onQuickReorder(d.data, i),
      builder: (context, candidates, _) => AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: candidates.isNotEmpty ? 1.05 : 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            draggable,
            Positioned(
              top: -6,
              right: -6,
              child: Material(
                color: OAColors.surface2,
                shape: CircleBorder(side: BorderSide(color: OAColors.border2)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => widget.onQuickAction(QuickAction.remove, i),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: OAColors.text2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addTile() {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OARadius.xl),
        side: BorderSide(color: OAColors.border2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(OARadius.xl),
        onTap: widget.onQuickAdd,
        child: SizedBox(
          height: 112,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, color: OAColors.muted),
              const SizedBox(height: 8),
              Text('Ekle',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: OAColors.text2)),
            ],
          ),
        ),
      ),
    );
  }

  /// Basılı tutunca (telefon) alttan, sağ tıklayınca (bilgisayar) imlecin yanında menü.
  Future<void> _tileMenu(int index, Offset? globalPos) async {
    final q = widget.quickLinks[index];
    QuickAction? action;
    if (globalPos != null) {
      final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
      action = await showMenu<QuickAction>(
        context: context,
        position: RelativeRect.fromRect(
            globalPos & const Size(1, 1), Offset.zero & overlay.size),
        items: const [
          PopupMenuItem(value: QuickAction.openNewTab, child: Text('Yeni sekmede aç')),
          PopupMenuItem(value: QuickAction.edit, child: Text('Düzenle')),
          PopupMenuItem(value: QuickAction.remove, child: Text('Kaldır')),
        ],
      );
    } else {
      action = await showModalBottomSheet<QuickAction>(
        context: context,
        useSafeArea: true,
        builder: (ctx) => Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(q.name, style: oaDisplay(20)),
                subtitle: Text(q.url, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const Divider(height: 8),
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: const Text('Yeni sekmede aç'),
                onTap: () => Navigator.pop(ctx, QuickAction.openNewTab),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Düzenle'),
                onTap: () => Navigator.pop(ctx, QuickAction.edit),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: OAColors.danger),
                title: Text('Kaldır', style: TextStyle(color: OAColors.danger)),
                onTap: () => Navigator.pop(ctx, QuickAction.remove),
              ),
            ],
          ),
        ),
      );
    }
    if (action != null) widget.onQuickAction(action, index);
  }

  Widget _searchField() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctl,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(fontSize: 17),
            decoration: InputDecoration(
              hintText: '${widget.engineName} ile ara veya adres yaz',
              fillColor: OAColors.surface,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 18, right: 10),
                child: Icon(Icons.search, color: OAColors.muted, size: 22),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0),
              contentPadding: const EdgeInsets.symmetric(vertical: 17),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(onPressed: _submit, child: const Text('Git')),
      ],
    );
  }

  Widget _engineLine() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Arama motoru: ${widget.engineName} · ',
            style: TextStyle(color: OAColors.muted, fontSize: 14)),
        InkWell(
          onTap: widget.onChangeEngine,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Text(
              'Değiştir',
              style: TextStyle(
                color: OAColors.accent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                decoration: TextDecoration.underline,
                decorationColor: OAColors.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _grid(List<Widget> tiles) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final cols = c.maxWidth < 440 ? 3 : (c.maxWidth / 170).floor().clamp(2, 6);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final t in tiles) SizedBox(width: w, child: t)],
      );
    });
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.name,
    required this.url,
    required this.letter,
    required this.onTap,
    this.onMenu,
    this.bg,
    this.fg,
  });
  final String name;
  final String url;
  final String letter;
  final Color? bg;
  final Color? fg;
  final VoidCallback onTap;

  /// Menü isteği: sağ tıkta imlecin konumu, basılı tutmada null.
  final void Function(Offset? globalPos)? onMenu;

  @override
  Widget build(BuildContext context) {
    final shortUrl = url
        .replaceFirst(RegExp(r'^https?://(www\.)?'), '')
        .replaceFirst(RegExp(r'/$'), '');
    return GestureDetector(
      onSecondaryTapDown:
          onMenu == null ? null : (d) => onMenu!(d.globalPosition),
      child: Material(
        color: OAColors.surface.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OARadius.xl),
          side: BorderSide(color: OAColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(OARadius.xl),
          onTap: onTap,
          onLongPress: onMenu == null ? null : () => onMenu!(null),
          child: SizedBox(
            height: 112,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SiteIcon(url: url, letter: letter, bg: bg, fg: fg),
                  const Spacer(),
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(shortUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: OAColors.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('✓', style: TextStyle(color: OAColors.accent, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: OAColors.text2, fontSize: 15)),
      ],
    );
  }
}
