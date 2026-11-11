import 'package:flutter/material.dart';

// Light-mode palette (Soko Kuu style board). Names kept from the old theme
// so existing screens keep compiling.
const cream = Color(0xFFF6ECD9);
const paper = Color(0xFFFFFBF2); // raised card
const charcoal = Color(0xFF2B2322); // ink
const muted = Color(0xFF6B5B52);
const terracotta = Color(0xFFB8452B);
const leaf = Color(0xFF2F6B2F);
const brick = Color(0xFFB3261E);
const ochre = Color(0xFFE9A83A); // fills only, never text
const indigo = Color(0xFF2E3A8C);
const teal = Color(0xFF1F6F68);

// Dark-mode palette.
const darkBg = Color(0xFF1F1822);
const darkCard = Color(0xFF2A2230);
const darkInk = Color(0xFFF3E9DA);
const darkMuted = Color(0xFFC4B5AA);
const darkUp = Color(0xFF6FCF7A);
const darkDown = Color(0xFFFF8A7A);

// Measured kitenge colours (market wall, crate, matatu).
const kitengeRed = Color(0xFF892032);
const kitengeBlue = Color(0xFF337087);
const kitengePurple = Color(0xFF5F296C);
const kitengeOrange = Color(0xFFA35638);

const tabular = [FontFeature.tabularFigures()];

const headingFont = 'Fredoka';
const bodyFont = 'DMSans';

/// Semantic colours that do not fit ColorScheme. Read with `context.tokens`.
const _ochre = ochre, _indigo = indigo, _teal = teal, _muted = muted;

@immutable
class SokoTokens extends ThemeExtension<SokoTokens> {
  const SokoTokens({
    required this.up,
    required this.down,
    required this.ochre,
    required this.indigo,
    required this.onIndigo,
    required this.teal,
    required this.muted,
    required this.card,
    required this.kitenge,
  });

  final Color up, down, ochre, indigo, onIndigo, teal, muted, card;

  /// Red, blue, purple, orange (in that order).
  final List<Color> kitenge;

  static const light = SokoTokens(
    up: leaf,
    down: brick,
    ochre: _ochre,
    indigo: _indigo,
    onIndigo: Colors.white,
    teal: _teal,
    muted: _muted,
    card: paper,
    kitenge: [kitengeRed, kitengeBlue, kitengePurple, kitengeOrange],
  );

  static const dark = SokoTokens(
    up: darkUp,
    down: darkDown,
    ochre: _ochre,
    indigo: Color(0xFF3B49A8),
    onIndigo: Colors.white,
    teal: Color(0xFF63C7BC),
    muted: darkMuted,
    card: darkCard,
    kitenge: [kitengeRed, kitengeBlue, kitengePurple, kitengeOrange],
  );

  @override
  SokoTokens copyWith({
    Color? up,
    Color? down,
    Color? ochre,
    Color? indigo,
    Color? onIndigo,
    Color? teal,
    Color? muted,
    Color? card,
    List<Color>? kitenge,
  }) => SokoTokens(
    up: up ?? this.up,
    down: down ?? this.down,
    ochre: ochre ?? this.ochre,
    indigo: indigo ?? this.indigo,
    onIndigo: onIndigo ?? this.onIndigo,
    teal: teal ?? this.teal,
    muted: muted ?? this.muted,
    card: card ?? this.card,
    kitenge: kitenge ?? this.kitenge,
  );

  @override
  SokoTokens lerp(ThemeExtension<SokoTokens>? other, double t) {
    if (other is! SokoTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SokoTokens(
      up: l(up, other.up),
      down: l(down, other.down),
      ochre: l(ochre, other.ochre),
      indigo: l(indigo, other.indigo),
      onIndigo: l(onIndigo, other.onIndigo),
      teal: l(teal, other.teal),
      muted: l(muted, other.muted),
      card: l(card, other.card),
      kitenge: t < .5 ? kitenge : other.kitenge,
    );
  }
}

extension SokoThemeX on BuildContext {
  SokoTokens get tokens =>
      Theme.of(this).extension<SokoTokens>() ?? SokoTokens.light;
}

TextTheme _textTheme(Color ink) {
  TextStyle h(double size, FontWeight w, [double? height]) => TextStyle(
    fontFamily: headingFont,
    fontSize: size,
    fontWeight: w,
    height: height,
    color: ink,
  );
  TextStyle b(double size, FontWeight w, [double? height]) => TextStyle(
    fontFamily: bodyFont,
    fontSize: size,
    fontWeight: w,
    height: height,
    color: ink,
  );
  return TextTheme(
    displayLarge: h(44, FontWeight.w600, 1.1),
    displayMedium: h(36, FontWeight.w600, 1.15),
    displaySmall: h(30, FontWeight.w600, 1.15),
    headlineLarge: h(28, FontWeight.w600, 1.2),
    headlineMedium: h(24, FontWeight.w600, 1.2),
    headlineSmall: h(20, FontWeight.w600, 1.25),
    titleLarge: h(20, FontWeight.w600, 1.25),
    titleMedium: h(16, FontWeight.w600, 1.3),
    titleSmall: h(14, FontWeight.w600, 1.3),
    bodyLarge: b(16, FontWeight.w400, 1.4),
    bodyMedium: b(14, FontWeight.w400, 1.4),
    bodySmall: b(12, FontWeight.w400, 1.35),
    labelLarge: b(14, FontWeight.w600, 1.2),
    labelMedium: b(12, FontWeight.w600, 1.2),
    labelSmall: b(11, FontWeight.w600, 1.2),
  );
}

ThemeData buildTheme() => _build(
  ColorScheme(
    brightness: Brightness.light,
    primary: terracotta,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFF3D5C8),
    onPrimaryContainer: const Color(0xFF4A1A0D),
    secondary: leaf,
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFD5E8D0),
    onSecondaryContainer: const Color(0xFF123012),
    tertiary: indigo,
    onTertiary: Colors.white,
    tertiaryContainer: const Color(0xFFDDE0F5),
    onTertiaryContainer: const Color(0xFF111A5C),
    error: brick,
    onError: Colors.white,
    errorContainer: const Color(0xFFF9DAD6),
    onErrorContainer: const Color(0xFF4A0D09),
    surface: cream,
    onSurface: charcoal,
    onSurfaceVariant: muted,
    surfaceContainerLowest: paper,
    surfaceContainerLow: paper,
    surfaceContainer: paper,
    surfaceContainerHigh: const Color(0xFFF1E4CC),
    surfaceContainerHighest: const Color(0xFFEBDCC0),
    outline: const Color(0xFF8A7A70),
    outlineVariant: const Color(0xFFDDCFB8),
    inverseSurface: charcoal,
    onInverseSurface: cream,
    inversePrimary: const Color(0xFFFF9A80),
    shadow: Colors.black,
  ),
  SokoTokens.light,
);

/// Dark theme. main.dart can opt in with `darkTheme: buildDarkTheme()`.
ThemeData buildDarkTheme() => _build(
  ColorScheme(
    brightness: Brightness.dark,
    primary: const Color(0xFFFF9A80),
    onPrimary: const Color(0xFF3A1208),
    primaryContainer: const Color(0xFF7A2C19),
    onPrimaryContainer: const Color(0xFFFFDBD0),
    secondary: darkUp,
    onSecondary: const Color(0xFF0B2D10),
    secondaryContainer: const Color(0xFF1F4A25),
    onSecondaryContainer: const Color(0xFFCDEFC9),
    tertiary: const Color(0xFFB4BCFF),
    onTertiary: const Color(0xFF111A5C),
    tertiaryContainer: const Color(0xFF3B49A8),
    onTertiaryContainer: const Color(0xFFE0E3FF),
    error: darkDown,
    onError: const Color(0xFF4A0D09),
    errorContainer: const Color(0xFF8C1D18),
    onErrorContainer: const Color(0xFFFFDAD5),
    surface: darkBg,
    onSurface: darkInk,
    onSurfaceVariant: darkMuted,
    surfaceContainerLowest: const Color(0xFF181219),
    surfaceContainerLow: darkCard,
    surfaceContainer: darkCard,
    surfaceContainerHigh: const Color(0xFF332A3A),
    surfaceContainerHighest: const Color(0xFF3D3345),
    outline: const Color(0xFF9C8D93),
    outlineVariant: const Color(0xFF4A3F50),
    inverseSurface: darkInk,
    onInverseSurface: darkBg,
    inversePrimary: terracotta,
    shadow: Colors.black,
  ),
  SokoTokens.dark,
);

ThemeData _build(ColorScheme s, SokoTokens t) {
  final text = _textTheme(s.onSurface);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  const minSize = Size(48, 48);
  return ThemeData(
    useMaterial3: true,
    colorScheme: s,
    brightness: s.brightness,
    extensions: [t],
    fontFamily: bodyFont,
    textTheme: text,
    scaffoldBackgroundColor: s.surface,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      foregroundColor: s.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: t.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: s.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.card,
      indicatorColor: s.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: minSize,
        shape: shape,
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: minSize,
        shape: shape,
        side: BorderSide(color: s.outline),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: minSize,
        foregroundColor: t.teal,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: minSize),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: s.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: s.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: s.primary, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      labelStyle: text.labelLarge,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: shape,
      contentTextStyle: text.bodyMedium?.copyWith(color: s.onInverseSurface),
    ),
    dividerTheme: DividerThemeData(color: s.outlineVariant, space: 1),
  );
}
