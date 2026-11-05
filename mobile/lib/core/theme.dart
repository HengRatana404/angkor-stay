import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const angkorCharcoal = Color(0xFF241C16);
const angkorGold = Color(0xFFC9A227);
const angkorGoldLight = Color(0xFFEAB308);
const angkorCream = Color(0xFFFAF7F2);
const angkorBorder = Color(0xFFE8E0D2);

// Backward-compatible alias so existing references keep working
const angkorBrown = angkorCharcoal;

// Extra tokens (added so screens stop using raw hex values).
const angkorInk = Color(0xFF1E1A17); // darkest text and dark surfaces
const angkorGoldWash = Color(0xFFFEF9EE); // pale gold background
const angkorGoldDeep = Color(
  0xFF926A1A,
); // gold used for text on light surfaces
const angkorGoldSoft = Color(0xFFF7E5BD); // soft gold fill
const angkorMuted = Color(0xFFB5A99B); // quiet text and icons
const angkorSuccess = Color(0xFF15803D);
const angkorSuccessWash = Color(0xFFF0FDF4);
const angkorSuccessBorder = Color(0xFFBBF7D0);
const angkorDanger = Color(0xFFB91C1C);
const angkorDangerWash = Color(0xFFFEF2F2);
const angkorDangerBorder = Color(0xFFFECACA);

/// Colors that change between light and dark. Read them with `context.pal`.
/// Light values are the original look of the app.
@immutable
class AngkorPalette extends ThemeExtension<AngkorPalette> {
  final Color page; // behind everything
  final Color surface; // cards, sheets, nav bar
  final Color surfaceAlt; // chips, quiet fills
  final Color border;
  final Color text; // main text
  final Color textMuted; // secondary text
  final Color strong; // dark pills and bars
  final Color onStrong; // text and icons on them
  final Color accent; // the one accent colour (terracotta)
  final Color onAccent;
  final Color action; // main buttons
  final Color onAction;
  final Color goldWash;
  final Color goldSoft;
  final Color goldDeep; // gold text on a light/dark surface
  final Color success;
  final Color successWash;
  final Color successBorder;
  final Color danger;
  final Color dangerWash;
  final Color dangerBorder;

  const AngkorPalette({
    required this.page,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.strong,
    required this.onStrong,
    required this.accent,
    required this.onAccent,
    required this.action,
    required this.onAction,
    required this.goldWash,
    required this.goldSoft,
    required this.goldDeep,
    required this.success,
    required this.successWash,
    required this.successBorder,
    required this.danger,
    required this.dangerWash,
    required this.dangerBorder,
  });

  // Light: sandstone page, terracotta accent, charcoal brand pill. The "gold*" names are kept
  // from the old look; they now hold the terracotta tints used for icons and small chips.
  static const light = AngkorPalette(
    page: Color(0xFFF3EBDD),
    surface: Color(0xFFFBF6EC),
    surfaceAlt: Color(0xFFEAE0CD),
    border: Color(0xFFDED2BC),
    text: Color(0xFF2B2118),
    textMuted: Color(0xFF6D5F4E),
    strong: Color(0xFF241C16),
    onStrong: Color(0xFFF4EEE4),
    accent: Color(0xFFDC7440),
    onAccent: Color(0xFFFFFFFF),
    action: Color(0xFFDC7440),
    onAction: Colors.white,
    goldWash: Color(0xFFF5E3D6),
    goldSoft: Color(0xFFEBCDB8),
    goldDeep: Color(0xFFC4622F),
    success: Color(0xFF2E6B4F),
    successWash: Color(0xFFE3EFE6),
    successBorder: Color(0xFFBCD6C5),
    danger: Color(0xFFB3261E),
    dangerWash: Color(0xFFFCE9E5),
    dangerBorder: Color(0xFFF1BDB5),
  );

  static const dark = AngkorPalette(
    page: Color(0xFF12100C),
    surface: Color(0xFF1F1B14),
    surfaceAlt: Color(0xFF2A241B),
    border: Color(0xFF4A4030),
    text: Color(0xFFF3EBDD),
    textMuted: Color(0xFFC2B6A0),
    strong: Color(0xFF2C231A),
    onStrong: Color(0xFFF4EEE4),
    accent: Color(0xFFE08A5F),
    onAccent: Color(0xFF1A120C),
    action: Color(0xFFE08A5F),
    onAction: Color(0xFF1A120C),
    goldWash: Color(0xFF33201A),
    goldSoft: Color(0xFF5A3320),
    goldDeep: Color(0xFFF0A27A),
    success: Color(0xFF6CC49A),
    successWash: Color(0xFF16291F),
    successBorder: Color(0xFF2A5A41),
    danger: Color(0xFFFB8A8A),
    dangerWash: Color(0xFF3A1B1D),
    dangerBorder: Color(0xFF74383C),
  );

  @override
  AngkorPalette copyWith() => this;

  @override
  AngkorPalette lerp(ThemeExtension<AngkorPalette>? other, double t) {
    if (other is! AngkorPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AngkorPalette(
      page: l(page, other.page),
      surface: l(surface, other.surface),
      surfaceAlt: l(surfaceAlt, other.surfaceAlt),
      border: l(border, other.border),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      strong: l(strong, other.strong),
      onStrong: l(onStrong, other.onStrong),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      action: l(action, other.action),
      onAction: l(onAction, other.onAction),
      goldWash: l(goldWash, other.goldWash),
      goldSoft: l(goldSoft, other.goldSoft),
      goldDeep: l(goldDeep, other.goldDeep),
      success: l(success, other.success),
      successWash: l(successWash, other.successWash),
      successBorder: l(successBorder, other.successBorder),
      danger: l(danger, other.danger),
      dangerWash: l(dangerWash, other.dangerWash),
      dangerBorder: l(dangerBorder, other.dangerBorder),
    );
  }
}

extension AngkorPaletteContext on BuildContext {
  AngkorPalette get pal =>
      Theme.of(this).extension<AngkorPalette>() ?? AngkorPalette.light;
}

ThemeData buildAngkorTheme([Brightness brightness = Brightness.light]) {
  final isDark = brightness == Brightness.dark;
  final pal = isDark ? AngkorPalette.dark : AngkorPalette.light;

  final scheme = ColorScheme.fromSeed(
    seedColor: pal.accent,
    primary: pal.action,
    onPrimary: pal.onAction,
    secondary: pal.accent,
    surface: pal.surface,
    onSurface: pal.text,
    surfaceContainerHighest: isDark ? pal.surfaceAlt : angkorCharcoal,
    outline: pal.border,
    error: pal.danger,
    brightness: brightness,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [pal],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor: pal.page,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? pal.strong : angkorCharcoal,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      shape: const Border(bottom: BorderSide(color: angkorGold, width: 1.5)),
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 19,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.3,
      ),
      iconTheme: const IconThemeData(color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: pal.surface,
      elevation: isDark ? 0 : 0.5,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: pal.border, width: 1),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: pal.action,
        foregroundColor: pal.onAction,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: pal.accent,
        side: BorderSide(color: pal.accent, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: pal.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? pal.border : const Color(0xFFDCD4C4),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: pal.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: pal.accent, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: pal.danger),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: pal.surfaceAlt,
      selectedColor: pal.goldSoft,
      checkmarkColor: pal.goldDeep,
      labelStyle: TextStyle(
        color: pal.text,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      side: BorderSide(color: pal.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: DividerThemeData(color: pal.border),
    dialogTheme: DialogThemeData(backgroundColor: pal.surface),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? pal.surfaceAlt : angkorCharcoal,
      contentTextStyle: TextStyle(color: isDark ? pal.text : Colors.white),
    ),
  );
}
