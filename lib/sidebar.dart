import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'oa_theme.dart';
import 'start_page.dart' show SiteIcon;

// Kenar çubuğu (bilgisayar): WhatsApp, Gmail, Instagram… sitelerin web sürümleri soldaki küçük
// panelde açılır; sekme açmadan kullanılır. Simgeler fare üzerine gelince büyür (dock gibi).

class SideApp {
  SideApp(this.id, this.name, this.url);
  final String id;
  final String name;
  final String url;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'url': url};
  static SideApp? fromJson(Map j) {
    final u = j['url']?.toString() ?? '';
    if (!u.startsWith('http')) return null;
    return SideApp(j['id']?.toString() ?? u, j['name']?.toString() ?? u, u);
  }
}

/// OA Radyo kenar çubuğunda web sayfası değil, uygulamanın kendi radyosu olarak açılır.
const kSideRadio = 'oaradyo';

List<SideApp> defaultSideApps() => [
      SideApp(kSideRadio, 'OA Radyo', 'https://oalabs.dev/radyo/'),
      SideApp('whatsapp', 'WhatsApp', 'https://web.whatsapp.com/'),
      SideApp('gmail', 'Gmail', 'https://mail.google.com/mail/'),
      SideApp('instagram', 'Instagram', 'https://www.instagram.com/direct/inbox/'),
      SideApp('messenger', 'Messenger', 'https://www.messenger.com/'),
      SideApp('spotify', 'Spotify', 'https://open.spotify.com/'),
      SideApp('ytmusic', 'YouTube Music', 'https://music.youtube.com/'),
    ];

/// "Ekle" listesindeki hazır öneriler.
List<SideApp> suggestedSideApps() => [
      SideApp('telegram', 'Telegram', 'https://web.telegram.org/a/'),
      SideApp('discord', 'Discord', 'https://discord.com/app'),
      SideApp('gcal', 'Google Takvim', 'https://calendar.google.com/'),
      SideApp('outlook', 'Outlook', 'https://outlook.live.com/mail/'),
      SideApp('x', 'X', 'https://x.com/'),
      SideApp('twitch', 'Twitch', 'https://www.twitch.tv/'),
      SideApp('keep', 'Google Keep', 'https://keep.google.com/'),
      SideApp('translate', 'Google Çeviri', 'https://translate.google.com/'),
    ];

/// Sayfa başlığındaki okunmamış sayısı: "(3) WhatsApp", "Gelen Kutusu (12) - Gmail".
int unreadFromTitle(String? title) {
  if (title == null) return 0;
  final m = RegExp(r'\((\d{1,4})\)').firstMatch(title);
  return m == null ? 0 : int.parse(m.group(1)!);
}

/// Soldaki simge şeridi. Fare yaklaştıkça simgeler büyür, komşuları biraz daha az büyür.
class SidebarDock extends StatefulWidget {
  const SidebarDock({
    super.key,
    required this.apps,
    required this.active,
    required this.loaded,
    required this.badges,
    required this.onTap,
    required this.onMenu,
    required this.onAdd,
  });

  final List<SideApp> apps;
  final String? active; // açık panel
  final Set<String> loaded; // arkada açık olanlar (nokta gösterilir)
  final Map<String, int> badges;
  final void Function(SideApp a) onTap;
  final void Function(SideApp a, Offset pos) onMenu;
  final VoidCallback onAdd;

  static const double width = 56;

  @override
  State<SidebarDock> createState() => _SidebarDockState();
}

class _SidebarDockState extends State<SidebarDock> with SingleTickerProviderStateMixin {
  static const double _base = 30; // dinlenirken simge boyu
  static const double _gap = 10;
  static const double _maxScale = 1.5; // farenin tam üstündeki simge
  static const double _reach = 100; // büyümenin yayıldığı mesafe
  double? _hoverY;
  String? _bouncing;
  late final AnimationController _bounce =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  double _scaleFor(int i) {
    final y = _hoverY;
    if (y == null) return 1;
    final center = 10 + i * (_base + _gap) + _base / 2;
    final d = (y - center).abs();
    if (d > _reach) return 1;
    final t = math.cos((d / _reach) * math.pi / 2); // 1 → 0
    return 1 + (_maxScale - 1) * t * t;
  }

  void _tap(SideApp a) {
    setState(() => _bouncing = a.id);
    _bounce.forward(from: 0);
    widget.onTap(a);
  }

  Widget _icon(int i, SideApp a) {
    final s = _base * _scaleFor(i);
    final active = widget.active == a.id;
    final badge = widget.badges[a.id] ?? 0;
    return SizedBox(
      height: s + _gap,
      child: Row(
        children: [
          // Açık olan uygulamanın göstergesi (macOS'taki nokta gibi)
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 3,
            height: active ? 20 : (widget.loaded.contains(a.id) ? 6 : 0),
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              color: active ? OAColors.amber : OAColors.text2,
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
            ),
          ),
          Tooltip(
            message: a.name,
            waitDuration: const Duration(milliseconds: 250),
            preferBelow: false,
            child: GestureDetector(
              onTap: () => _tap(a),
              onSecondaryTapUp: (d) => widget.onMenu(a, d.globalPosition),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: AnimatedBuilder(
                  animation: _bounce,
                  builder: (context, child) {
                    // Tıklayınca küçük bir zıplama
                    final dy = _bouncing == a.id ? -math.sin(_bounce.value * math.pi * 2).abs() * 8 * (1 - _bounce.value) : 0.0;
                    return Transform.translate(offset: Offset(0, dy), child: child);
                  },
                  child: Stack(clipBehavior: Clip.none, children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      curve: Curves.easeOut,
                      width: s,
                      height: s,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(s * 0.28),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: active ? 0.45 : 0.25), blurRadius: s * 0.25, offset: Offset(0, s * 0.08)),
                        ],
                        border: active ? Border.all(color: OAColors.amber, width: 2) : null,
                      ),
                      child: a.id == kSideRadio
                          ? Container(
                              decoration: BoxDecoration(color: OAColors.amber, borderRadius: BorderRadius.circular(s * 0.28)),
                              child: Icon(Icons.radio_rounded, color: OAColors.amberInk, size: s * 0.56),
                            )
                          : FittedBox(child: SiteIcon(url: a.url, letter: a.name.characters.first.toUpperCase(), size: 64)),
                    ),
                    if (badge > 0)
                      Positioned(
                        right: -3,
                        top: -3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 15),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5484D),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: OAColors.bg2, width: 1.5),
                          ),
                          child: Text(badge > 99 ? '99+' : '$badge',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: SidebarDock.width,
      decoration: BoxDecoration(
        color: OAColors.bg2,
        border: Border(right: BorderSide(color: OAColors.line)),
      ),
      child: MouseRegion(
        onHover: (e) => setState(() => _hoverY = e.localPosition.dy),
        onExit: (_) => setState(() => _hoverY = null),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 10, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.apps.length; i++) _icon(i, widget.apps[i]),
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Tooltip(
                  message: 'Kenar çubuğuna ekle',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: widget.onAdd,
                    child: Container(
                      width: _base,
                      height: _base,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: OAColors.border2),
                      ),
                      child: Icon(Icons.add, color: OAColors.muted),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
