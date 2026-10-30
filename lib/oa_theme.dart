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

SystemUiOverlayStyle oaSystemOverlay(OAPalette p) => SystemUiOverlayStyle(
      statusBarColor: p.bg,
      statusBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: p.isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: p.surface,
      systemNavigationBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
    );

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

/// OA işareti: kare içinde "OA". Koyu temada açık kare, açık temada koyu kare.
class OAMark extends StatelessWidget {
  const OAMark({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: OAColors.text,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        'OA',
        style: GoogleFonts.bricolageGrotesque(
          fontSize: size * 0.43,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.04 * size * 0.43,
          color: OAColors.bg,
          height: 1,
        ),
      ),
    );
  }
}

/// Üye avatarı: baş harfler, amber zemin.
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
