import 'package:flutter/material.dart';

const cream = Color(0xFFFFF6E5);
const terracotta = Color(0xFFC8553D);
const ochre = Color(0xFFE0A030);
const leaf = Color(0xFF2F6B3F);
const charcoal = Color(0xFF2B2118);
const paper = Color(0xFFFBEBCB);

const tabular = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: terracotta,
        brightness: Brightness.light,
      ).copyWith(
        primary: terracotta,
        secondary: leaf,
        tertiary: ochre,
        surface: cream,
        onSurface: charcoal,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: cream,
      foregroundColor: charcoal,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: charcoal.withValues(alpha: .08)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: paper,
      indicatorColor: ochre.withValues(alpha: .35),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: charcoal,
      displayColor: charcoal,
    ),
  );
}
