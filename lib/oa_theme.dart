import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bir tema için OA Labs renkleri.
class OAPalette {
  const OAPalette({
    required this.brightness,
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.line,
    required this.border,
    required this.border2,
    required this.text,
    required this.text2,
    required this.muted,
    required this.faint,
    required this.amber,
    required this.amberHi,
    required this.amberInk,
    required this.accent,
    required this.green,
    required this.blue,
    required this.danger,
    required this.selection,
  });

  final Brightness brightness;
  final Color bg, bg2, surface, surface2, line, border, border2;
  final Color text, text2, muted, faint;

  /// Dolgu olarak marka rengi (düğme zemini, seçili rozet). Üstündeki yazı [amberInk].
  final Color amber, amberHi, amberInk;

  /// Yazı ve ikon olarak vurgu rengi (bağlantı, seçili yıldız, odak kenarı).
  /// Koyu temada amber'in kendisi; açık temada okunması için koyulaştırılmış hali.
  final Color accent;
  final Color green, blue, danger, selection;

  bool get isDark => brightness == Brightness.dark;
}

/// Koyu tema: oalabs.dev site.css ile birebir.
const kOADark = OAPalette(
  brightness: Brightness.dark,
  bg: Color(0xFF0D0F16),
  bg2: Color(0xFF11131C),
  surface: Color(0xFF151824),
  surface2: Color(0xFF1C2030),
  line: Color(0xFF1E2232),
  border: Color(0xFF262B3D),
  border2: Color(0xFF2A2F43),
  text: Color(0xFFEEEAE2),
  text2: Color(0xFFB7BACA),
  muted: Color(0xFF9EA2B3),
  faint: Color(0xFF7E8296),
  amber: Color(0xFFF2A541),
  amberHi: Color(0xFFF7BF6E),
  amberInk: Color(0xFF14110A),
  accent: Color(0xFFF2A541),
  green: Color(0xFF5BC48C),
  blue: Color(0xFF6EA8FE),
  danger: Color(0xFFF08A7E),
  selection: Color(0x55F2A541),
);

/// Açık tema: sitenin koyu temasından türetildi. Zemin, sitenin kırık beyaz metin
/// renginin açığı; metin, sitenin lacivert-siyah zemini. Bütün metinler 4.5:1'i geçer.
const kOALight = OAPalette(
  brightness: Brightness.light,
  bg: Color(0xFFF5F3EE),
  bg2: Color(0xFFECE9E2),
  surface: Color(0xFFFFFFFF),
  surface2: Color(0xFFEFECE6),
  line: Color(0xFFE3DFD6),
  border: Color(0xFFDAD5CA),
  border2: Color(0xFFC4BDB0),
  text: Color(0xFF15171F),
  text2: Color(0xFF3E4251),
  muted: Color(0xFF5B5F6E),
  faint: Color(0xFF656978),
  amber: Color(0xFFF2A541),
  amberHi: Color(0xFFE8962A),
  amberInk: Color(0xFF14110A),
  accent: Color(0xFF9A5800),
  green: Color(0xFF1D7A4A),
  blue: Color(0xFF2A63C4),
  danger: Color(0xFFB93A2C),
  selection: Color(0x55F2A541),
);

/// Uygulamanın o an kullandığı renkler. Tema değişince [OAColors.use] ile güncellenir
/// ve uygulama yeniden çizilir.
class OAColors {
  OAColors._();
  static OAPalette _p = kOADark;
  static void use(OAPalette p) => _p = p;
  static OAPalette get palette => _p;
  static bool get isDark => _p.isDark;

  static Color get bg => _p.bg;
  static Color get bg2 => _p.bg2;
  static Color get surface => _p.surface;
  static Color get surface2 => _p.surface2;
  static Color get line => _p.line;
  static Color get border => _p.border;
  static Color get border2 => _p.border2;
  static Color get text => _p.text;
  static Color get text2 => _p.text2;
  static Color get muted => _p.muted;
  static Color get faint => _p.faint;
  static Color get amber => _p.amber;
  static Color get amberHi => _p.amberHi;
  static Color get amberInk => _p.amberInk;
  static Color get accent => _p.accent;
  static Color get green => _p.green;
  static Color get blue => _p.blue;
  static Color get danger => _p.danger;
}

/// Kullanıcının tema seçimi: sistem, koyu ya da açık.
final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Vurgu rengi: düğmeler, seçili öğeler, başlangıç sayfası ışığı. Varsayılan OA turuncusu.
class OAAccent {
  const OAAccent(this.id, this.name, this.fill, this.hi, this.lightText);
  final String id;
  final String name;
  final Color fill; // dolgu (koyu ve açık temada)
  final Color hi; // koyu temada üzerine gelince
  final Color lightText; // açık temada yazı rengi olarak okunur hali
}

const kAccents = <OAAccent>[
  OAAccent('turuncu', 'OA turuncusu', Color(0xFFF2A541), Color(0xFFF7BF6E), Color(0xFF9A5800)),
  OAAccent('mor', 'Mor', Color(0xFFA78BFA), Color(0xFFC4B5FD), Color(0xFF6D4BD8)),
  OAAccent('mavi', 'Mavi', Color(0xFF6EA8FE), Color(0xFF9CC3FF), Color(0xFF2A63C4)),
  OAAccent('yesil', 'Yeşil', Color(0xFF5BC48C), Color(0xFF86D9AB), Color(0xFF1D7A4A)),
  OAAccent('pembe', 'Pembe', Color(0xFFF0729A), Color(0xFFF59DB8), Color(0xFFB8325C)),
  OAAccent('kirmizi', 'Kırmızı', Color(0xFFF08A7E), Color(0xFFF5AEA5), Color(0xFFB93A2C)),
  OAAccent('camgobegi', 'Camgöbeği', Color(0xFF5CC8D7), Color(0xFF8EDCE6), Color(0xFF1E7F8C)),
];

OAAccent accentById(String? id) => kAccents.firstWhere((a) => a.id == id, orElse: () => kAccents.first);

final accentNotifier = ValueNotifier<String>('turuncu');

/// Paletin vurgu rengini değiştirir.
OAPalette withAccent(OAPalette p, OAAccent a) {
  if (a.id == 'turuncu') return p;
  return OAPalette(
    brightness: p.brightness,
    bg: p.bg,
    bg2: p.bg2,
    surface: p.surface,
    surface2: p.surface2,
    line: p.line,
    border: p.border,
    border2: p.border2,
    text: p.text,
    text2: p.text2,
    muted: p.muted,
    faint: p.faint,
    amber: a.fill,
    amberHi: p.isDark ? a.hi : a.lightText,
    amberInk: p.amberInk,
    accent: p.isDark ? a.fill : a.lightText,
    green: p.green,
    blue: p.blue,
    danger: p.danger,
    selection: a.fill.withValues(alpha: 0.33),
  );
}

/// Hazır temalar: vurgu rengi + başlangıç sayfası arka planı.
const kThemePresets = <(String, String, String)>[
  ('OA', 'turuncu', 'glow'),
  ('Gece', 'mor', 'glow'),
  ('Okyanus', 'mavi', 'rings'),
  ('Orman', 'yesil', 'dots'),
  ('Gün batımı', 'pembe', 'dusk'),
  ('Kadran', 'kirmizi', 'dial'),
];

ThemeMode themeModeFromString(String? s) => switch (s) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };

String themeModeToString(ThemeMode m) => switch (m) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };

/// OA Labs köşe yuvarlaklıkları.
class OARadius {
  OARadius._();
  static const xs = 6.0;
  static const sm = 9.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

/// Başlık fontu: Bricolage Grotesque, 800, sıkı harf aralığı.
TextStyle oaDisplay(double size, {Color? color}) => GoogleFonts.bricolageGrotesque(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.02 * size,
      height: 1.05,
      color: color ?? OAColors.text,
    );

/// Sistem çubukları. Uygulama ekranın tamamına çizilir (Android 15 zaten zorunlu kılıyor);
/// çubukların arkasını uygulama kendisi boyar, Android'in gri okunabilirlik perdesi kapatılır.
SystemUiOverlayStyle oaSystemOverlay(OAPalette p, {Color? statusBackground}) {
  final top = statusBackground ?? p.bg;
  final topDark = ThemeData.estimateBrightnessForColor(top) == Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: topDark ? Brightness.light : Brightness.dark,
    statusBarBrightness: topDark ? Brightness.dark : Brightness.light,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );
}

/// Sayfanın bildirdiği renk metnini ("#fff", "#0d0f16", "rgb(13, 15, 22)", "rgba(...)", "white") okur.
Color? parseCssColor(String? input) {
  if (input == null) return null;
  var s = input.trim().toLowerCase();
  if (s.isEmpty || s == 'transparent') return null;
  const named = {'white': 0xFFFFFFFF, 'black': 0xFF000000};
  if (named.containsKey(s)) return Color(named[s]!);
  if (s.startsWith('#')) {
    s = s.substring(1);
    final hasAlpha = s.length == 4 || s.length == 8; // #rgba, #rrggbbaa
    if (s.length == 3 || s.length == 4) s = s.split('').map((c) => '$c$c').join();
    if (s.length == 6) s = 'ff$s';
    if (s.length == 8 && hasAlpha) s = s.substring(6) + s.substring(0, 6); // rrggbbaa → aarrggbb
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(v);
  }
  final m = RegExp(r'rgba?\(\s*([\d.]+)[,\s]+([\d.]+)[,\s]+([\d.]+)(?:[,\s/]+([\d.]+%?))?\s*\)').firstMatch(s);
  if (m != null) {
    int ch(String g) => double.parse(g).round().clamp(0, 255);
    var a = 1.0;
    final ag = m.group(4);
    if (ag != null) a = ag.endsWith('%') ? double.parse(ag.substring(0, ag.length - 1)) / 100 : double.parse(ag);
    if (a < 0.5) return null; // neredeyse saydam: sayfanın gerçek rengi değil
    return Color.fromARGB(255, ch(m.group(1)!), ch(m.group(2)!), ch(m.group(3)!));
  }
  return null;
}

ThemeData buildOATheme(OAPalette p) {
  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.amber,
    onPrimary: p.amberInk,
    secondary: p.blue,
    onSecondary: p.isDark ? const Color(0xFF0E1A30) : Colors.white,
    tertiary: p.green,
    onTertiary: p.isDark ? const Color(0xFF0F2A1C) : Colors.white,
    error: p.danger,
    onError: p.isDark ? p.amberInk : Colors.white,
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.muted,
    surfaceContainerLowest: p.bg,
    surfaceContainerLow: p.bg2,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surface2,
    surfaceContainerHighest: p.surface2,
    outline: p.border2,
    outlineVariant: p.border,
  );

  final base = p.isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
  final body = GoogleFonts.dmSansTextTheme(base).apply(
    bodyColor: p.text,
    displayColor: p.text,
  );

  const pill = StadiumBorder();

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    dividerColor: p.line,
    dividerTheme: DividerThemeData(color: p.line),
    textTheme: body.copyWith(
      headlineLarge: oaDisplay(44, color: p.text),
      headlineMedium: oaDisplay(34, color: p.text),
      titleLarge: oaDisplay(22, color: p.text),
      bodyLarge: body.bodyLarge?.copyWith(fontSize: 17, height: 1.6),
      bodyMedium: body.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    iconTheme: IconThemeData(color: p.text2),
    progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.amber, linearTrackColor: Colors.transparent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.accent,
      selectionColor: p.selection,
      selectionHandleColor: p.amber,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.amber,
        foregroundColor: p.amberInk,
        disabledBackgroundColor: p.surface2,
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: pill,
        textStyle: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        side: BorderSide(color: p.border2),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: pill,
        textStyle: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.accent, shape: pill),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: p.text2,
        disabledForegroundColor: p.border2,
        hoverColor: p.surface2,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.amber : Colors.transparent),
      checkColor: WidgetStatePropertyAll(p.amberInk),
      side: BorderSide(color: p.border2, width: 2),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.bg,
      hintStyle: GoogleFonts.dmSans(color: p.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OARadius.pill),
        borderSide: BorderSide(color: p.border2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OARadius.pill),
        borderSide: BorderSide(color: p.accent),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OARadius.lg),
        side: BorderSide(color: p.border2),
      ),
      textStyle: GoogleFonts.dmSans(fontSize: 15, color: p.text),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(OARadius.xl)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: p.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.isDark ? p.surface2 : p.text,
      contentTextStyle: GoogleFonts.dmSans(color: p.isDark ? p.text : p.bg),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OARadius.md)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.text2,
      textColor: p.text,
      subtitleTextStyle: TextStyle(color: p.muted, fontSize: 13),
    ),
  );
}

/// OA Labs işareti: amber A'nın içinden geçen O. O, temanın yazı renginde.
class OAMark extends StatelessWidget {
  const OAMark({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: OALabsMarkPainter(ring: OAColors.text, legs: OAColors.amber)),
    );
  }
}

/// OA Labs işaretini (A'nın içinden geçen O) çizer. 100 birimlik kutuda: A bacakları
/// (26,86)–(52,14)–(78,86), O merkezi (52,58) yarıçap 28; yatayda 2 birim sola kaydırılır.
class OALabsMarkPainter extends CustomPainter {
  OALabsMarkPainter({required this.ring, required this.legs});
  final Color ring;
  final Color legs;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 100;
    canvas.save();
    canvas.translate((size.width - 100 * s) / 2 - 2 * s, (size.height - 100 * s) / 2);
    final w = (size.shortestSide < 24 ? 12.0 : 10.0) * s;
    final legPaint = Paint()
      ..color = legs
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(26 * s, 86 * s)
      ..lineTo(52 * s, 14 * s)
      ..lineTo(78 * s, 86 * s);
    canvas.drawPath(path, legPaint);
    canvas.drawCircle(
      Offset(52 * s, 58 * s),
      28 * s,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(OALabsMarkPainter old) => old.ring != ring || old.legs != legs;
}

/// Üye avatarı: baş harfler, amber zemin.
/// Giriş yapmış üyenin profil fotoğrafı (OAAccount doldurur, çıkışta boşaltır).
final ValueNotifier<Uint8List?> oaAvatarImage = ValueNotifier<Uint8List?>(null);

class OAAvatar extends StatelessWidget {
  const OAAvatar({super.key, this.name, this.size = 34});
  final String? name;
  final double size;

  static String initials(String? name) {
    final p = (name ?? '').trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (p.isEmpty) return '';
    final s = p.first[0] + (p.length > 1 ? p.last[0] : '');
    return s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final ini = initials(name);
    final on = ini.isNotEmpty;
    if (!on) return _initials(ini, on);
    // Üyenin profil fotoğrafı (yalnızca kendisi görür); yoksa baş harfleri.
    return ValueListenableBuilder<Uint8List?>(
      valueListenable: oaAvatarImage,
      builder: (context, bytes, _) => bytes == null
          ? _initials(ini, on)
          : ClipOval(
              child: Image.memory(bytes,
                  width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => _initials(ini, on)),
            ),
    );
  }

  Widget _initials(String ini, bool on) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? OAColors.amber : OAColors.surface2,
        shape: BoxShape.circle,
      ),
      child: on
          ? Text(ini, style: oaDisplay(size * 0.4, color: OAColors.amberInk).copyWith(height: 1))
          : Icon(Icons.person_outline, size: size * 0.55, color: OAColors.text2),
    );
  }
}

/// OA Labs mühürü: iki halka, aralarında dönen "OA LABS · ATÖLYE · 2026" yazısı, ortada A.
/// Yazı 40 saniyede bir tur döner; sistemde hareketi azaltma açıksa durur.
class OALabsSeal extends StatefulWidget {
  const OALabsSeal({
    super.key,
    this.size = 96,
    required this.color,
    required this.accent,
    this.text = 'OA LABS · ATÖLYE · 2026 · OA LABS · ATÖLYE · 2026 · ',
  });
  final double size;
  final Color color;
  final Color accent;
  final String text;

  @override
  State<OALabsSeal> createState() => _OALabsSealState();
}

class _OALabsSealState extends State<OALabsSeal> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(seconds: 40));
  List<TextPainter> _glyphs = const [];

  void _layoutGlyphs() {
    _glyphs = widget.text
        .split('')
        .map((ch) => TextPainter(
              text: TextSpan(
                text: ch,
                style: TextStyle(color: widget.color, fontSize: 11, fontWeight: FontWeight.w600, height: 1),
              ),
              textDirection: TextDirection.ltr,
            )..layout())
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _layoutGlyphs();
  }

  @override
  void didUpdateWidget(OALabsSeal old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.color != widget.color) _layoutGlyphs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'OA Labs',
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _turn,
          builder: (context, _) => CustomPaint(
            painter: _OALabsSealPainter(
              color: widget.color,
              accent: widget.accent,
              glyphs: _glyphs,
              turn: _turn.value * 2 * math.pi,
            ),
          ),
        ),
      ),
    );
  }
}

class _OALabsSealPainter extends CustomPainter {
  _OALabsSealPainter({required this.color, required this.accent, required this.glyphs, required this.turn});
  final Color color;
  final Color accent;
  final List<TextPainter> glyphs;
  final double turn;

  @override
  void paint(Canvas canvas, Size size) {
    // Çizim 140 birimlik kutuda, merkez (0,0).
    final s = size.shortestSide / 140;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(Offset.zero, 64, ring);
    canvas.drawCircle(Offset.zero, 42, ring);
    if (glyphs.isNotEmpty) {
      final step = 2 * math.pi / glyphs.length;
      for (var i = 0; i < glyphs.length; i++) {
        final g = glyphs[i];
        canvas.save();
        canvas.rotate(turn + i * step);
        canvas.translate(0, -53);
        g.paint(canvas, Offset(-g.width / 2, -g.height / 2));
        canvas.restore();
      }
    }
    final a = Path()
      ..moveTo(-15, 18)
      ..lineTo(0, -20)
      ..lineTo(15, 18);
    canvas.drawPath(
      a,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OALabsSealPainter old) =>
      old.turn != turn || old.color != color || old.accent != accent || old.glyphs != glyphs;
}
