import 'package:flutter/material.dart';

const angkorGold = Color(0xFFC9A227);
const angkorBrown = Color(0xFF3E2A1C);

ThemeData buildAngkorTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: angkorGold,
    primary: angkorBrown,
    secondary: angkorGold,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFFAF6EE),
    appBarTheme: const AppBarTheme(
      backgroundColor: angkorBrown,
      foregroundColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(backgroundColor: angkorBrown),
    ),
  );
}
