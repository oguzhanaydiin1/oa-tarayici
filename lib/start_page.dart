import 'package:flutter/material.dart';

import 'oa_theme.dart';

/// Başlangıç sayfasındaki hızlı erişim kutusu.
class QuickLink {
  const QuickLink(this.name, this.url, this.letter,
      {this.bg = OAColors.surface2, this.fg = OAColors.text2});
  final String name;
  final String url;
  final String letter;
  final Color bg;
  final Color fg;
}

const kQuickLinks = <QuickLink>[
  QuickLink('OA Labs', 'https://oalabs.dev', 'OA', bg: OAColors.amber, fg: OAColors.amberInk),
  QuickLink('OA Radyo', 'https://oalabs.dev/radyo/', 'R', bg: OAColors.amber, fg: OAColors.amberInk),
  QuickLink('Harrier Cleaner', 'https://oalabs.dev/#uygulamalar', 'H',
      bg: Color(0xFF1E3A8A), fg: OAColors.text),
  QuickLink('Vikipedi', 'https://tr.wikipedia.org', 'V'),
  QuickLink('GitHub', 'https://github.com', 'G'),
  QuickLink('OpenStreetMap', 'https://www.openstreetmap.org', 'O'),
];

/// OA başlangıç sayfası: yeni sekmede ve ana sayfa düğmesinde açılır.
class StartPage extends StatefulWidget {
  const StartPage({
    super.key,
    required this.incognito,
    required this.engineName,
    required this.bookmarks,
    required this.onGo,
    required this.onChangeEngine,
    required this.compact,
  });

  final bool incognito;
  final String engineName;
  final List<Map<String, String>> bookmarks;
  final void Function(String input) onGo;
  final VoidCallback onChangeEngine;

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
                Text(
                  widget.incognito ? 'Gizli sekme' : 'OA Tarayıcı',
                  style: const TextStyle(color: OAColors.muted, fontSize: 15),
                ),
                const SizedBox(height: 14),
                Text.rich(
                  TextSpan(
                    style: titleStyle,
                    children: widget.incognito
                        ? const [
                            TextSpan(text: 'Gezdiklerin '),
                            TextSpan(
                                text: 'kaydedilmez.',
                                style: TextStyle(color: OAColors.amber)),
                          ]
                        : const [
                            TextSpan(text: 'Nereye '),
                            TextSpan(
                                text: 'gidiyoruz?',
                                style: TextStyle(color: OAColors.amber)),
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
                Text('Hızlı erişim', style: oaDisplay(22)),
                const SizedBox(height: 14),
                _tiles([
                  for (final q in kQuickLinks)
                    _Tile(q.name, q.url, q.letter, q.bg, q.fg),
                ]),
                const SizedBox(height: 40),
                Text('Yer imleri', style: oaDisplay(22)),
                const SizedBox(height: 14),
                if (widget.bookmarks.isEmpty)
                  Text(
                    compact
                        ? 'Henüz yer imi yok. Bir sayfadayken alttaki yıldıza dokun.'
                        : 'Henüz yer imi yok. Bir sayfadayken yıldıza dokun.',
                    style: const TextStyle(color: OAColors.muted, fontSize: 15),
                  )
                else
                  _tiles([
                    for (final b in widget.bookmarks.take(6))
                      _Tile(
                        b['title'] ?? '',
                        b['url'] ?? '',
                        (b['title'] ?? '?').isEmpty
                            ? '?'
                            : (b['title'] ?? '?')[0].toUpperCase(),
                        OAColors.surface2,
                        OAColors.text2,
                      ),
                  ]),
                const SizedBox(height: 40),
                const Divider(height: 1, color: OAColors.line),
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
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 18, right: 10),
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
            style: const TextStyle(color: OAColors.muted, fontSize: 14)),
        InkWell(
          onTap: widget.onChangeEngine,
          borderRadius: BorderRadius.circular(6),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Text(
              'Değiştir',
              style: TextStyle(
                color: OAColors.amber,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                decoration: TextDecoration.underline,
                decorationColor: OAColors.amber,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tiles(List<_Tile> tiles) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final cols = c.maxWidth < 440 ? 3 : (c.maxWidth / 170).floor().clamp(2, 6);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final t in tiles)
            SizedBox(width: w, child: t.build(widget.onGo, small: w < 130)),
        ],
      );
    });
  }
}

class _Tile {
  const _Tile(this.name, this.url, this.letter, this.bg, this.fg);
  final String name;
  final String url;
  final String letter;
  final Color bg;
  final Color fg;

  Widget build(void Function(String) onGo, {bool small = false}) {
    final shortUrl = url
        .replaceFirst(RegExp(r'^https?://(www\.)?'), '')
        .replaceFirst(RegExp(r'/$'), '');
    return Material(
      color: OAColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OARadius.xl),
        side: const BorderSide(color: OAColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(OARadius.xl),
        onTap: () => onGo(url),
        child: Padding(
          padding: EdgeInsets.all(small ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(letter, style: oaDisplay(17, color: fg)),
              ),
              const SizedBox(height: 12),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(shortUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: OAColors.muted)),
            ],
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
        const Text('✓',
            style: TextStyle(color: OAColors.amber, fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: OAColors.text2, fontSize: 15)),
      ],
    );
  }
}
