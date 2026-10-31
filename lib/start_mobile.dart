import 'package:flutter/material.dart';

import 'oa_theme.dart';
import 'start_page.dart';
import 'wallpaper.dart';

/// Başlangıç sayfasındaki kaydırmalı kartlar: OA Labs'in kendi uygulamaları ve üyelik.
class Promo {
  const Promo(this.id, this.title, this.text, this.letter, this.bg, this.fg, {this.url});
  final String id;
  final String title;
  final String text;
  final String letter;
  final Color bg;
  final Color fg;
  final String? url; // null: üyelik kartı (hesap ekranını açar)
}

/// Telefon başlangıç sayfası: arka plan ekranın en üstüne kadar, ortada OA logosu ve arama kutusu,
/// altında OA kartları ve uygulama simgesi gibi hızlı erişim kutuları.
class MobileStartPage extends StatefulWidget {
  const MobileStartPage({
    super.key,
    required this.incognito,
    required this.engineName,
    required this.quickLinks,
    required this.onGo,
    required this.onQuickAction,
    required this.onQuickAdd,
    required this.onQuickReorder,
    required this.onSearch,
    required this.onCustomize,
    required this.onAccount,
    required this.onRadio,
    required this.onAdblock,
    required this.adblockOn,
    required this.signedIn,
    required this.hiddenPromos,
    required this.onHidePromo,
    this.weatherCard,
    this.onQr,
    this.userName,
    this.wallpaperId = 'none',
    this.wallpaperPath,
  });

  final bool incognito;
  final String engineName;
  final List<QuickLink> quickLinks;
  final void Function(String input) onGo;
  final void Function(QuickAction action, int index) onQuickAction;
  final VoidCallback onQuickAdd;
  final void Function(int from, int to) onQuickReorder;
  final VoidCallback onSearch;
  final VoidCallback onCustomize;
  final VoidCallback onAccount;
  final VoidCallback onRadio;
  final VoidCallback onAdblock;
  final VoidCallback? onQr;
  final bool adblockOn;
  final bool signedIn;
  final String? userName;
  final Set<String> hiddenPromos;
  final void Function(String id) onHidePromo;

  /// Saat ve hava kartı (gösteriliyorsa OA kartlarının yerine geçer).
  final Widget? weatherCard;
  final String wallpaperId;
  final String? wallpaperPath;

  @override
  State<MobileStartPage> createState() => _MobileStartPageState();
}

class _MobileStartPageState extends State<MobileStartPage> {
  final _pager = PageController(viewportFraction: 0.92);
  int _page = 0;
  bool _arranging = false;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  List<Promo> get _promos => [
        Promo('radyo', 'OA Radyo', 'Gezinirken radyo dinle. Dokun, istasyonunu seç.', 'R',
            OAColors.amber, OAColors.amberInk,
            url: 'https://oalabs.dev/radyo/'),
        const Promo('harrier', 'Harrier Cleaner', 'Bilgisayarını derli toplu ve hızlı tutar.', 'H',
            Color(0xFF1E3A8A), Color(0xFFEEEAE2),
            url: 'https://oalabs.dev/#uygulamalar'),
        if (!widget.signedIn)
          Promo('uye', 'OA Labs’e üye ol', 'Yer imlerin ve hızlı erişimin bütün cihazlarında.', 'OA',
              OAColors.text, OAColors.bg),
      ].where((p) => !widget.hiddenPromos.contains(p.id)).toList();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final promos = widget.incognito ? <Promo>[] : _promos;
    if (_page >= promos.length) _page = 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        WallpaperLayer(id: widget.wallpaperId, photoPath: widget.wallpaperPath),
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, top + 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _roundButton(
                    tooltip: widget.signedIn ? 'Hesabım' : 'Giriş yap',
                    onTap: widget.onAccount,
                    child: OAAvatar(name: widget.userName, size: 34),
                  ),
                  const Spacer(),
                  if (widget.onQr != null) ...[
                    _roundButton(
                      tooltip: 'QR kod okut',
                      onTap: widget.onQr!,
                      child: Icon(Icons.qr_code_scanner, size: 26, color: OAColors.text),
                    ),
                    const SizedBox(width: 12),
                  ],
                  _roundButton(
                    tooltip: 'Özelleştir',
                    onTap: widget.onCustomize,
                    child: Icon(Icons.tune, size: 26, color: OAColors.text),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.sizeOf(context).height < 700 ? 40 : 72),
              _logo(),
              if (widget.incognito) ...[
                const SizedBox(height: 10),
                Text('Gizli sekme · gezdiklerin kaydedilmez',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: OAColors.text2, fontSize: 15)),
              ],
              const SizedBox(height: 36),
              _searchBox(),
              if (widget.weatherCard != null) ...[
                const SizedBox(height: 18),
                widget.weatherCard!,
              ] else if (promos.isNotEmpty) ...[
                const SizedBox(height: 18),
                _promoCarousel(promos),
              ],
              const SizedBox(height: 26),
              _grid(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roundButton({required String tooltip, required VoidCallback onTap, required Widget child}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: OAColors.surface,
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(width: 54, height: 54, child: Center(child: child)),
        ),
      ),
    );
  }

  Widget _logo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const OAMark(size: 50),
        const SizedBox(width: 12),
        Text('Tarayıcı', style: oaDisplay(46).copyWith(letterSpacing: -1.6, height: 1)),
      ],
    );
  }

  Widget _searchBox() {
    return Material(
      color: OAColors.surface,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            Tooltip(
              message: widget.adblockOn ? 'Reklam engelleme açık' : 'Reklam engelleme kapalı',
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
                onTap: widget.onAdblock,
                child: SizedBox(
                  width: 62,
                  height: 64,
                  child: Icon(
                    widget.adblockOn ? Icons.shield : Icons.shield_outlined,
                    size: 28,
                    color: widget.adblockOn ? OAColors.green : OAColors.muted,
                  ),
                ),
              ),
            ),
            Container(width: 1, height: 30, color: OAColors.border),
            Expanded(
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(24)),
                onTap: widget.onSearch,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: OAColors.surface2,
                          shape: BoxShape.circle,
                        ),
                        child: Text(widget.engineName[0],
                            style: oaDisplay(15, color: OAColors.text2).copyWith(height: 1)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${widget.engineName} içinde ara',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 18, color: OAColors.faint),
                        ),
                      ),
                      Icon(Icons.search, color: OAColors.muted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _promoCarousel(List<Promo> promos) {
    return Column(
      children: [
        SizedBox(
          height: 128,
          child: PageView.builder(
            controller: _pager,
            padEnds: false,
            itemCount: promos.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _promoCard(promos[i]),
            ),
          ),
        ),
        if (promos.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < promos.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _page ? OAColors.accent : OAColors.border2,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _promoCard(Promo p) {
    return Material(
      color: OAColors.surface,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => p.id == 'radyo'
            ? widget.onRadio()
            : (p.url == null ? widget.onAccount() : widget.onGo(p.url!)),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 44, 16),
              child: Row(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.bg,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Text(p.letter, style: oaDisplay(p.letter.length > 1 ? 26 : 34, color: p.fg)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: oaDisplay(20).copyWith(height: 1.15)),
                        const SizedBox(height: 4),
                        Text(p.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, height: 1.35, color: OAColors.text2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: IconButton(
                tooltip: 'Bu kartı gizle',
                visualDensity: VisualDensity.compact,
                style: IconButton.styleFrom(backgroundColor: OAColors.surface2),
                icon: Icon(Icons.close, size: 18, color: OAColors.text2),
                onPressed: () => widget.onHidePromo(p.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Uygulama simgesi gibi kutular: 5 sütun, kare simge ve altında ad.
  Widget _grid() {
    return LayoutBuilder(builder: (context, c) {
      const cols = 5;
      final w = c.maxWidth / cols;
      final items = <Widget>[
        for (var i = 0; i < widget.quickLinks.length; i++) _cell(i, w),
        if (_arranging && widget.quickLinks.length < kMaxQuickLinks)
          _actionCell(w, Icons.add, 'Ekle', widget.onQuickAdd),
        _actionCell(w, _arranging ? Icons.check : Icons.edit_outlined, _arranging ? 'Bitti' : '',
            () => setState(() => _arranging = !_arranging),
            highlighted: _arranging),
      ];
      return Wrap(runSpacing: 14, children: items);
    });
  }

  Widget _iconBox(Widget child, {Color? color}) => Material(
        color: color ?? OAColors.surface,
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(width: 60, height: 60, child: Center(child: child)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: OAColors.text, fontWeight: FontWeight.w500),
        ),
      );

  Widget _cell(int i, double w) {
    final q = widget.quickLinks[i];
    final (Color? bg, Color? fg) = switch (q.color) {
      'amber' => (OAColors.amber, OAColors.amberInk),
      'harrier' => (const Color(0xFF1E3A8A), const Color(0xFFEEEAE2)),
      _ => (null, null),
    };
    final icon = bg != null
        ? _iconBox(Text(q.letter, style: oaDisplay(q.letter.length > 1 ? 20 : 24, color: fg)), color: bg)
        : _iconBox(SiteIcon(url: q.url, letter: q.letter, size: 36));
    final content = SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(mainAxisSize: MainAxisSize.min, children: [icon, _label(q.name)]),
      ),
    );

    if (_arranging) {
      final tile = Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(
            top: -6,
            right: w / 2 - 38,
            child: Material(
              color: OAColors.surface2,
              shape: CircleBorder(side: BorderSide(color: OAColors.border2)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => widget.onQuickAction(QuickAction.remove, i),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(Icons.close, size: 15, color: OAColors.text2),
                ),
              ),
            ),
          ),
        ],
      );
      return DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != i,
        onAcceptWithDetails: (d) => widget.onQuickReorder(d.data, i),
        builder: (context, candidates, _) => AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: candidates.isNotEmpty ? 1.1 : 1,
          child: LongPressDraggable<int>(
            data: i,
            delay: const Duration(milliseconds: 200),
            feedback: Material(color: Colors.transparent, child: content),
            childWhenDragging: Opacity(opacity: 0.3, child: content),
            child: GestureDetector(
              onTap: () => widget.onQuickAction(QuickAction.edit, i),
              child: tile,
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => widget.onGo(q.url),
      onLongPress: () => _menu(i),
      child: content,
    );
  }

  Widget _actionCell(double w, IconData icon, String label, VoidCallback onTap, {bool highlighted = false}) {
    return SizedBox(
      width: w,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _iconBox(
                Icon(icon, size: 28, color: highlighted ? OAColors.amberInk : OAColors.muted),
                color: highlighted ? OAColors.amber : OAColors.surface.withValues(alpha: 0.75),
              ),
              _label(label),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menu(int i) async {
    final q = widget.quickLinks[i];
    final action = await showModalBottomSheet<QuickAction>(
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
              leading: const Icon(Icons.drag_indicator),
              title: const Text('Yerlerini değiştir'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _arranging = true);
              },
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
    if (action != null) widget.onQuickAction(action, i);
  }
}
