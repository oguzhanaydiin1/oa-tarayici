import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'oa_theme.dart';

/// Başlangıç sayfası arka planları. Hepsi OA renklerinden kodla çizilir (dosya indirmez);
/// "photo" kullanıcının seçtiği fotoğraftır.
class Wallpaper {
  const Wallpaper(this.id, this.name);
  final String id;
  final String name;

  static const none = Wallpaper('none', 'Düz');
  static const all = <Wallpaper>[
    none,
    Wallpaper('glow', 'Amber ışık'),
    Wallpaper('dots', 'Noktalar'),
    Wallpaper('dial', 'Radyo kadranı'),
    Wallpaper('rings', 'Halkalar'),
    Wallpaper('dusk', 'Gün batımı'),
  ];

  static Wallpaper byId(String? id) =>
      all.firstWhere((w) => w.id == id, orElse: () => none);
}

/// Arka plan katmanı. Fotoğrafta yazılar okunsun diye üstüne zemin renginde bir perde iner.
class WallpaperLayer extends StatelessWidget {
  const WallpaperLayer({super.key, required this.id, this.photoPath});
  final String id;
  final String? photoPath;

  @override
  Widget build(BuildContext context) {
    final p = OAColors.palette;
    if (id == 'photo' && photoPath != null && File(photoPath!).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(photoPath!), fit: BoxFit.cover),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  p.bg.withValues(alpha: 0.55),
                  p.bg.withValues(alpha: 0.78),
                  p.bg.withValues(alpha: 0.92),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (id == 'none' || id == 'photo') return ColoredBox(color: p.bg);
    return CustomPaint(painter: _WallpaperPainter(id, p), child: const SizedBox.expand());
  }
}

class _WallpaperPainter extends CustomPainter {
  _WallpaperPainter(this.id, this.p);
  final String id;
  final OAPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = p.bg);
    final glow = p.isDark ? 0.22 : 0.30;
    switch (id) {
      case 'glow':
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(0.85, -0.9),
              radius: 1.1,
              colors: [p.amber.withValues(alpha: glow), p.amber.withValues(alpha: 0)],
            ).createShader(rect),
        );
        canvas.drawRect(
          rect,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-1, 1),
              radius: 0.9,
              colors: [p.blue.withValues(alpha: glow * 0.5), p.blue.withValues(alpha: 0)],
            ).createShader(rect),
        );
      case 'dots':
        final paint = Paint()..color = p.border2.withValues(alpha: p.isDark ? 0.9 : 0.8);
        const step = 24.0;
        for (var y = step / 2; y < size.height; y += step) {
          for (var x = step / 2; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), 1.3, paint);
          }
        }
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.bg.withValues(alpha: 0), p.bg],
              stops: const [0.4, 1],
            ).createShader(rect),
        );
      case 'dial':
        // OA Radyo kartındaki kadran çizgileri, sayfanın üst kısmında
        final h = math.min(220.0, size.height * 0.35);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, h),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.amber.withValues(alpha: glow), p.amber.withValues(alpha: 0)],
            ).createShader(Rect.fromLTWH(0, 0, size.width, h)),
        );
        final tick = Paint()
          ..color = p.accent.withValues(alpha: 0.45)
          ..strokeWidth = 2;
        var i = 0;
        for (var x = 12.0; x < size.width; x += 20, i++) {
          final len = i % 8 == 0 ? 36.0 : (i % 4 == 0 ? 24.0 : 12.0);
          canvas.drawLine(Offset(x, h - 30), Offset(x, h - 30 - len), tick);
        }
        canvas.drawLine(
          Offset(size.width * 0.62, 8),
          Offset(size.width * 0.62, h - 22),
          Paint()
            ..color = p.accent
            ..strokeWidth = 3,
        );
      case 'rings':
        final c = Offset(size.width * 0.92, size.height * 0.08);
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = p.blue.withValues(alpha: p.isDark ? 0.22 : 0.28);
        for (var r = 60.0; r < size.longestSide * 1.2; r += 60) {
          canvas.drawCircle(c, r, ring);
        }
      case 'dusk':
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: p.isDark
                  ? [const Color(0xFF1B2A45), p.bg, const Color(0xFF2A1D10)]
                  : [const Color(0xFFDCE6F7), p.bg, const Color(0xFFF8E3C4)],
              stops: const [0, 0.55, 1],
            ).createShader(rect),
        );
    }
  }

  @override
  bool shouldRepaint(_WallpaperPainter old) => old.id != id || old.p != p;
}

/// Seçim kutusundaki küçük önizleme.
class WallpaperSwatch extends StatelessWidget {
  const WallpaperSwatch({
    super.key,
    required this.id,
    required this.label,
    required this.selected,
    required this.onTap,
    this.photoPath,
    this.icon,
  });
  final String id;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? photoPath;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 64,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? OAColors.accent : OAColors.border,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: icon != null
                ? ColoredBox(
                    color: OAColors.surface2,
                    child: Center(child: Icon(icon, color: OAColors.text2)),
                  )
                : WallpaperLayer(id: id, photoPath: photoPath),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? OAColors.text : OAColors.muted)),
        ],
      ),
    );
  }
}
