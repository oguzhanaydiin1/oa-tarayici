import 'package:flutter/material.dart';

import 'oa_theme.dart';

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
    required this.onChangeEngine,
    required this.compact,
    this.userFirstName,
  });

  final bool incognito;
  final String engineName;
  final List<QuickLink> quickLinks;
  final List<Map<String, String>> bookmarks;
  final void Function(String input) onGo;
  final void Function(QuickAction action, int index) onQuickAction;
  final VoidCallback onQuickAdd;
  final VoidCallback onChangeEngine;
  final String? userFirstName;

  /// Telefon düzeni: arama alanı yerine alttaki adres çubuğu kullanılır.
  final bool compact;

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> {
  final _ctl = TextEditingController();

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

    return ColoredBox(
      color: OAColors.bg,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            compact ? 20 : 24, compact ? 40 : 56, compact ? 20 : 24, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                    Text(
                      compact ? 'Düzenlemek için basılı tut' : 'Düzenlemek için sağ tıkla',
                      style: TextStyle(color: OAColors.faint, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _grid([
                  for (var i = 0; i < widget.quickLinks.length; i++) _quickTile(i),
                  if (widget.quickLinks.length < kMaxQuickLinks) _addTile(),
                ]),
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
    );
  }

  Widget _quickTile(int i) {
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
      onTap: () => widget.onGo(q.url),
      onMenu: (pos) => _tileMenu(i, pos),
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
        color: OAColors.surface,
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
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg ?? OAColors.surface2,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(letter, style: oaDisplay(17, color: fg ?? OAColors.text2)),
                  ),
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
