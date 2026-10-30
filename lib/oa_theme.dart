import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// OA Labs tasarım sistemi renkleri (oalabs.dev site.css ile birebir).
class OAColors {
  OAColors._();

  static const bg = Color(0xFF0D0F16);
  static const bg2 = Color(0xFF11131C);
  static const surface = Color(0xFF151824);
  static const surface2 = Color(0xFF1C2030);
  static const line = Color(0xFF1E2232);
  static const border = Color(0xFF262B3D);
  static const border2 = Color(0xFF2A2F43);

  static const text = Color(0xFFEEEAE2);
  static const text2 = Color(0xFFB7BACA);
  static const muted = Color(0xFF9EA2B3);
  static const faint = Color(0xFF7E8296);

  static const amber = Color(0xFFF2A541);
  static const amberHi = Color(0xFFF7BF6E);
  static const amberInk = Color(0xFF14110A);

  static const green = Color(0xFF5BC48C);
  static const blue = Color(0xFF6EA8FE);
  static const danger = Color(0xFFF08A7E);
  static const betaInk = Color(0xFF8FB8FF);
}

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
TextStyle oaDisplay(double size, {Color color = OAColors.text}) =>
    GoogleFonts.bricolageGrotesque(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.02 * size,
      height: 1.05,
      color: color,
    );

ThemeData buildOATheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: OAColors.amber,
    onPrimary: OAColors.amberInk,
    secondary: OAColors.blue,
    onSecondary: Color(0xFF0E1A30),
    tertiary: OAColors.green,
    onTertiary: Color(0xFF0F2A1C),
    error: OAColors.danger,
    onError: OAColors.amberInk,
    surface: OAColors.surface,
    onSurface: OAColors.text,
    onSurfaceVariant: OAColors.muted,
    surfaceContainerLowest: OAColors.bg,
    surfaceContainerLow: OAColors.bg2,
    surfaceContainer: OAColors.surface,
    surfaceContainerHigh: OAColors.surface2,
    surfaceContainerHighest: OAColors.surface2,
    outline: OAColors.border2,
    outlineVariant: OAColors.border,
  );

  final body = GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme).apply(
    bodyColor: OAColors.text,
    displayColor: OAColors.text,
  );

  final pill = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(OARadius.pill),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: OAColors.bg,
    canvasColor: OAColors.bg,
    dividerColor: OAColors.line,
    textTheme: body.copyWith(
      headlineLarge: oaDisplay(44),
      headlineMedium: oaDisplay(34),
      titleLarge: oaDisplay(22),
      bodyLarge: body.bodyLarge?.copyWith(fontSize: 17, height: 1.6),
      bodyMedium: body.bodyMedium?.copyWith(fontSize: 15, height: 1.5),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    ),
    iconTheme: const IconThemeData(color: OAColors.text2),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: OAColors.amber, linearTrackColor: Colors.transparent),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: OAColors.amber,
      selectionColor: Color(0x55F2A541),
      selectionHandleColor: OAColors.amber,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: OAColors.amber,
        foregroundColor: OAColors.amberInk,
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: pill,
        textStyle: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OAColors.text,
        side: const BorderSide(color: OAColors.border2),
        minimumSize: const Size(0, 54),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: pill,
        textStyle: GoogleFonts.dmSans(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: OAColors.amber, shape: pill),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: OAColors.text2,
        disabledForegroundColor: OAColors.border2,
        hoverColor: OAColors.surface2,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: OAColors.bg,
      hintStyle: GoogleFonts.dmSans(color: OAColors.faint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OARadius.pill),
        borderSide: const BorderSide(color: OAColors.border2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(OARadius.pill),
        borderSide: const BorderSide(color: OAColors.amber),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: OAColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(OARadius.lg),
        side: const BorderSide(color: OAColors.border2),
      ),
      textStyle: GoogleFonts.dmSans(fontSize: 15, color: OAColors.text),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: OAColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(OARadius.xl)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: OAColors.surface2,
      contentTextStyle: GoogleFonts.dmSans(color: OAColors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(OARadius.md)),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: OAColors.text2,
      subtitleTextStyle: TextStyle(color: OAColors.muted, fontSize: 13),
    ),
  );
}

/// OA işareti: 30×30, 9px köşe, kırık beyaz zemin üzerinde "OA".
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
